import Foundation

enum UI16Protocol {
    struct Message: Equatable, Sendable {
        let key: String
        let value: String
    }

    static func parse(_ raw: String) -> Message? {
        let parts = raw.split(separator: "^", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, parts[0] == "SETD" else { return nil }
        return Message(key: parts[1], value: parts.dropFirst(2).joined(separator: "^"))
    }

    static func set(_ key: String, _ value: some LosslessStringConvertible) -> String {
        "SETD^\(key)^\(value)"
    }

    static func set(_ key: String, _ value: Bool) -> String {
        set(key, value ? 1 : 0)
    }
}

@MainActor
final class UI16Store: ObservableObject {
    @Published private(set) var state = UI16State()
    @Published private(set) var connection: UI16WebSocket.ConnectionState = .disconnected

    private var socket: UI16WebSocket?

    func connect(ip: String) {
        let socket = UI16WebSocket(ip: ip)
        self.socket = socket
        Task {
            await socket.setCallbacks(
                onMessage: { [weak self] raw in
                    Task { @MainActor in self?.apply(raw: raw) }
                },
                onStateChange: { [weak self] status in
                    Task { @MainActor in
                        self?.connection = status
                        self?.state.connected = (status == .connected)
                    }
                }
            )
            await socket.connect()
        }
    }

    func disconnect() {
        guard let socket else { return }
        Task { await socket.disconnect() }
    }

    func setMaster(_ value: Double) {
        state.masterLevel = value
        send(UI16Protocol.set("m.0.mix", value))
    }

    func setMasterMute(_ muted: Bool) {
        state.masterMuted = muted
        send(UI16Protocol.set("m.0.mute", muted))
    }

    func setChannelLevel(_ channel: Int, value: Double) {
        state.channels[channel, default: .init()].level = value
        send(UI16Protocol.set("i.\(channel).mix", value))
    }

    func setChannelMute(_ channel: Int, muted: Bool) {
        state.channels[channel, default: .init()].muted = muted
        send(UI16Protocol.set("i.\(channel).mute", muted))
    }

    func send(_ message: String) {
        guard let socket else { return }
        Task { await socket.send(message) }
    }

    private func apply(raw: String) {
        guard let message = UI16Protocol.parse(raw) else { return }
        let value = message.value
        switch message.key {
        case "m.0.mix":
            state.masterLevel = Double(value) ?? state.masterLevel
        case "m.0.mute":
            state.masterMuted = value == "1"
        default:
            break
        }
    }
}

private extension UI16WebSocket {
    func setCallbacks(
        onMessage: @escaping @Sendable (String) -> Void,
        onStateChange: @escaping @Sendable (ConnectionState) -> Void
    ) {
        self.onMessage = onMessage
        self.onStateChange = onStateChange
    }
}
