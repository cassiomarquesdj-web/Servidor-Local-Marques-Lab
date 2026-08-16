import Foundation

actor UI16WebSocket {
    enum ConnectionState: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed(String)
    }

    private let ip: String
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private(set) var state: ConnectionState = .disconnected
    private var keepAliveTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    var onMessage: (@Sendable (String) -> Void)?
    var onStateChange: (@Sendable (ConnectionState) -> Void)?

    init(ip: String) {
        self.ip = ip
        self.session = URLSession(configuration: .default)
    }

    func connect() {
        guard task == nil else { return }
        reconnectTask?.cancel()
        update(.connecting)

        guard let url = URL(string: "ws://\(ip)") else {
            update(.failed("IP inválido"))
            return
        }

        let webSocket = session.webSocketTask(with: url)
        task = webSocket
        webSocket.resume()
        update(.connected)

        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(webSocket)
        }

        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                await self.sendRaw("ALIVE")
            }
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        receiveTask?.cancel()
        keepAliveTask?.cancel()
        receiveTask = nil
        keepAliveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        update(.disconnected)
    }

    func send(_ message: String) async {
        await sendRaw(message)
    }

    private func sendRaw(_ message: String) async {
        guard let task, state == .connected else { return }
        do {
            try await task.send(.string("3:::\(message)"))
        } catch {
            await scheduleReconnect()
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                switch message {
                case .string(let value):
                    parseFrame(value)
                case .data(let data):
                    if let value = String(data: data, encoding: .utf8) {
                        parseFrame(value)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            if !Task.isCancelled {
                await scheduleReconnect()
            }
        }
    }

    private func parseFrame(_ frame: String) {
        let clean = frame.hasPrefix("3:::") ? String(frame.dropFirst(4)) : frame
        clean.split(separator: "\n", omittingEmptySubsequences: true).forEach { line in
            onMessage?(String(line))
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil, state != .disconnected else { return }
        update(.reconnecting)
        task = nil
        receiveTask = nil
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.reconnectNow()
        }
    }

    private func reconnectNow() {
        reconnectTask = nil
        connect()
    }

    private func update(_ newState: ConnectionState) {
        state = newState
        onStateChange?(newState)
    }

    func setCallbacks(
        onMessage: @escaping @Sendable (String) -> Void,
        onStateChange: @escaping @Sendable (ConnectionState) -> Void
    ) {
        self.onMessage = onMessage
        self.onStateChange = onStateChange
    }
}
