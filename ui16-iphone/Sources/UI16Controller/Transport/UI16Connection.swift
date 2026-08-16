import Foundation

/// WebSocket transport for the Soundcraft Ui mixer.
///
/// Protocol facts confirmed against fmalcher/soundcraft-ui (`mixer-connection.ts`):
/// - Endpoint is a bare WebSocket at `ws://<ip>` (default port 80).
/// - Outbound payloads are framed as `3:::<payload>`.
/// - A keepalive payload `ALIVE` must be sent about once per second or the mixer drops us.
/// - Inbound frames strip the `3:::` prefix and may carry several newline-separated payloads.
///
/// Connection state is tracked from the real socket lifecycle via `URLSessionWebSocketDelegate`,
/// so "connected" reflects an actually-open socket rather than an optimistic guess.
public actor UI16Connection {

    public enum State: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed(String)
    }

    public let host: String
    public let port: Int
    public var keepAliveInterval: Duration = .seconds(1)
    public var reconnectDelay: Duration = .seconds(2)

    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var delegate: SocketDelegate!

    private(set) public var state: State = .disconnected
    private var intentionallyClosed = false

    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    var onMessage: (@Sendable (String) -> Void)?
    var onStateChange: (@Sendable (State) -> Void)?

    /// - Parameters:
    ///   - host: mixer address. May include a port (`10.10.2.1:8080`), which wins over `port`.
    ///   - port: port to use when `host` does not carry one. The mixer serves on 80.
    public init(host: String, port: Int = 80) {
        let (h, p) = Self.splitHostPort(host, fallback: port)
        self.host = h
        self.port = p
        self.delegate = SocketDelegate()
        self.session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.delegate.owner = self
    }

    public func setCallbacks(
        onMessage: @escaping @Sendable (String) -> Void,
        onStateChange: @escaping @Sendable (State) -> Void
    ) {
        self.onMessage = onMessage
        self.onStateChange = onStateChange
    }

    /// Split an `address` or `address:port` string. IPv6 literals in brackets are preserved.
    public static func splitHostPort(_ raw: String, fallback: Int) -> (String, Int) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Only treat a single trailing ":digits" as a port (avoids breaking IPv6).
        if let colon = trimmed.lastIndex(of: ":"),
           !trimmed.hasSuffix("]"),
           trimmed.filter({ $0 == ":" }).count == 1 {
            let hostPart = String(trimmed[trimmed.startIndex..<colon])
            let portPart = String(trimmed[trimmed.index(after: colon)...])
            if let p = Int(portPart), p > 0, p < 65536, !hostPart.isEmpty {
                return (hostPart, p)
            }
        }
        return (trimmed, fallback)
    }

    // MARK: Lifecycle

    public func connect() {
        guard task == nil else { return }
        intentionallyClosed = false
        reconnectTask?.cancel(); reconnectTask = nil
        update(state == .reconnecting ? .reconnecting : .connecting)

        guard var comps = URLComponents(string: "ws://\(host)") else {
            update(.failed("Endereço inválido")); return
        }
        comps.port = port
        guard let url = comps.url else { update(.failed("Endereço inválido")); return }

        let ws = session.webSocketTask(with: url)
        task = ws
        ws.resume()
        // `connected` is set by the delegate's didOpen; start loops now so no messages are missed.
        startReceiveLoop(ws)
        startKeepAlive()
    }

    public func disconnect() {
        intentionallyClosed = true
        reconnectTask?.cancel(); reconnectTask = nil
        receiveTask?.cancel(); receiveTask = nil
        keepAliveTask?.cancel(); keepAliveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        update(.disconnected)
    }

    public func send(_ payload: String) async {
        guard let task, state == .connected else { return }
        do {
            try await task.send(.string(UI16Message.frame(payload)))
        } catch {
            scheduleReconnect()
        }
    }

    // MARK: Delegate callbacks (from the socket lifecycle)

    fileprivate func socketDidOpen() {
        guard !intentionallyClosed else { return }
        update(.connected)
    }

    fileprivate func socketDidClose(_ reason: String?) {
        guard !intentionallyClosed else { return }
        scheduleReconnect()
    }

    // MARK: Internals

    private func startReceiveLoop(_ ws: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(ws)
        }
    }

    private func receiveLoop(_ ws: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await ws.receive()
                switch message {
                case .string(let text): dispatch(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { dispatch(text) }
                @unknown default: break
                }
            }
        } catch {
            if !Task.isCancelled { scheduleReconnect() }
        }
    }

    private func dispatch(_ frame: String) {
        for payload in UI16Message.unframe(frame) {
            onMessage?(payload)
        }
    }

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        let interval = keepAliveInterval
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                await self?.send("ALIVE")
            }
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil, !intentionallyClosed, state != .disconnected else { return }
        receiveTask?.cancel(); receiveTask = nil
        keepAliveTask?.cancel(); keepAliveTask = nil
        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil
        update(.reconnecting)
        let delay = reconnectDelay
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            await self.performReconnect()
        }
    }

    private func performReconnect() {
        reconnectTask = nil
        guard !intentionallyClosed else { return }
        connect()
    }

    private func update(_ newState: State) {
        guard newState != state else { return }
        state = newState
        onStateChange?(newState)
    }
}

/// Bridges `URLSessionWebSocketDelegate` open/close events into the connection actor.
private final class SocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    weak var owner: UI16Connection?

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        Task { await owner?.socketDidOpen() }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) }
        Task { await owner?.socketDidClose(text) }
    }
}
