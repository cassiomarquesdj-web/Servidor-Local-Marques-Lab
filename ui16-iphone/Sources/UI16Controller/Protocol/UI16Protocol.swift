import Foundation
import Combine

public enum UI16Protocol {
    public struct Message: Equatable, Sendable {
        public let key: String
        public let value: String
        public init(key: String, value: String) { self.key = key; self.value = value }
    }
    public static func parse(_ raw: String) -> Message? {
        let parts = raw.split(separator: "^", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, parts[0] == "SETD" else { return nil }
        return Message(key: parts[1], value: parts.dropFirst(2).joined(separator: "^"))
    }
    public static func set(_ key: String, _ value: some LosslessStringConvertible) -> String { "SETD^\(key)^\(value)" }
    public static func set(_ key: String, _ value: Bool) -> String { set(key, value ? 1 : 0) }
}

@MainActor
public final class UI16Store: ObservableObject {
    @Published public private(set) var state = UI16State()
    @Published public private(set) var connection: UI16WebSocket.ConnectionState = .disconnected
    private var socket: UI16WebSocket?
    public init() {}

    public func connect(ip: String) {
        let socket = UI16WebSocket(ip: ip); self.socket = socket
        Task {
            await socket.setCallbacks(
                onMessage: { [weak self] raw in Task { @MainActor in self?.apply(raw: raw) } },
                onStateChange: { [weak self] status in Task { @MainActor in self?.connection = status; self?.state.connected = (status == .connected) } }
            )
            await socket.connect()
        }
    }
    public func disconnect() { guard let socket else { return }; Task { await socket.disconnect() } }
    public func setMaster(_ value: Double) { state.masterLevel = value; send(UI16Protocol.set("m.0.mix", value)) }
    public func setMasterMute(_ muted: Bool) { state.masterMuted = muted; send(UI16Protocol.set("m.0.mute", muted)) }
    public func setChannelLevel(_ channel: Int, value: Double) { mutate(channel) { $0.level = value }; send(UI16Protocol.set("i.\(channel - 1).mix", value)) }
    public func setChannelMute(_ channel: Int, muted: Bool) { mutate(channel) { $0.muted = muted }; send(UI16Protocol.set("i.\(channel - 1).mute", muted)) }
    public func setChannelSolo(_ channel: Int, solo: Bool) { mutate(channel) { $0.solo = solo }; send(UI16Protocol.set("i.\(channel - 1).solo", solo)) }
    public func setChannelPan(_ channel: Int, value: Double) { mutate(channel) { $0.pan = value }; send(UI16Protocol.set("i.\(channel - 1).pan", value)) }
    public func setChannelGain(_ channel: Int, value: Double) { mutate(channel) { $0.gain = value }; send(UI16Protocol.set("i.\(channel - 1).gain", value)) }
    public func setPhantom(_ channel: Int, enabled: Bool) { mutate(channel) { $0.phantom = enabled }; send(UI16Protocol.set("i.\(channel - 1).phantom", enabled)) }
    public func setPhase(_ channel: Int, enabled: Bool) { mutate(channel) { $0.phase = enabled }; send(UI16Protocol.set("i.\(channel - 1).phase", enabled)) }
    public func setHPF(_ channel: Int, value: Double) { mutate(channel) { $0.highPass = value }; send(UI16Protocol.set("i.\(channel - 1).hpf", value)) }
    public func setAux(_ channel: Int, aux: Int, value: Double) { mutate(channel) { $0.auxSends[aux] = value }; send(UI16Protocol.set("i.\(channel - 1).aux.\(aux - 1)", value)) }
    public func setRaw(_ key: String, value: String) { state.metrics[key] = value; send(UI16Protocol.set(key, value)) }
    public func send(_ message: String) { guard let socket else { return }; Task { await socket.send(message) } }

    private func mutate(_ channel: Int, _ change: (inout UI16State.ChannelState) -> Void) { var item = state.channels[channel, default: .init()]; change(&item); state.channels[channel] = item }

    private func apply(raw: String) {
        if raw.hasPrefix("VU2^") { parseVU(String(raw.dropFirst(4))); return }
        guard let message = UI16Protocol.parse(raw) else { return }
        state.lastMessage = raw; state.metrics[message.key] = message.value
        let value = message.value; let number = Double(value); let bool = value == "1" || value.lowercased() == "true"
        switch message.key {
        case "m.0.mix": state.masterLevel = number ?? state.masterLevel
        case "m.0.mute": state.masterMuted = bool
        default:
            guard message.key.hasPrefix("i.") else { return }
            let pieces = message.key.split(separator: ".").map(String.init)
            guard pieces.count >= 3, let zero = Int(pieces[1]) else { return }
            let ch = zero + 1
            mutate(ch) { item in
                switch pieces.dropFirst(2).joined(separator: ".") {
                case "mix": item.level = number ?? item.level
                case "mute": item.muted = bool
                case "solo": item.solo = bool
                case "pan": item.pan = number ?? item.pan
                case "gain": item.gain = number ?? item.gain
                case "phantom": item.phantom = bool
                case "phase": item.phase = bool
                case "hpf": item.highPass = number ?? item.highPass
                default: break
                }
            }
        }
    }

    private func parseVU(_ base64: String) {
        guard let data = Data(base64Encoded: base64), data.count >= 8 else { return }
        let bytes = [UInt8](data); let factor = 0.004167508166392142
        let counts = [bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6]]
        let names = ["input", "player", "sub", "fx", "aux", "master", "line"]
        var index = 8
        for type in 0..<7 {
            let amount = Int(counts[type])
            let block = [6, 6, 7, 7, 5, 5, 6][type]
            for channel in 0..<amount {
                guard index + block <= bytes.count else { return }
                let n = names[type]
                switch n {
                case "input", "player", "line":
                    state.meters["vu.\(n).\(channel+1).pre"] = Double(bytes[index]) * factor
                    state.meters["vu.\(n).\(channel+1).post"] = Double(bytes[index+1]) * factor
                    state.meters["vu.\(n).\(channel+1).fader"] = Double(bytes[index+2]) * factor
                case "aux":
                    state.meters["vu.aux.\(channel+1).post"] = Double(bytes[index]) * factor
                    state.meters["vu.aux.\(channel+1).fader"] = Double(bytes[index+1]) * factor
                case "fx", "sub":
                    state.meters["vu.\(n).\(channel+1).L"] = Double(bytes[index]) * factor
                    state.meters["vu.\(n).\(channel+1).R"] = Double(bytes[index+1]) * factor
                    state.meters["vu.\(n).\(channel+1).faderL"] = Double(bytes[index+2]) * factor
                    state.meters["vu.\(n).\(channel+1).faderR"] = Double(bytes[index+3]) * factor
                case "master":
                    state.meters["vu.master.L"] = Double(bytes[index]) * factor
                    state.meters["vu.master.R"] = Double(bytes[index+1]) * factor
                    state.meters["vu.master.faderL"] = Double(bytes[index+2]) * factor
                    state.meters["vu.master.faderR"] = Double(bytes[index+3]) * factor
                default: break
                }
                index += block
            }
        }
    }
}

private extension UI16WebSocket {
    func setCallbacks(onMessage: @escaping @Sendable (String) -> Void, onStateChange: @escaping @Sendable (ConnectionState) -> Void) { self.onMessage = onMessage; self.onStateChange = onStateChange }
}
