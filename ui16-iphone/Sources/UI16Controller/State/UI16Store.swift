import Foundation
import Combine

/// Observable façade over the mixer: holds live state, applies incoming messages,
/// and sends corrected protocol commands. UI binds to `state` and `connection`.
@MainActor
public final class UI16Store: ObservableObject {
    @Published public private(set) var state = UI16State()
    @Published public private(set) var connection: UI16Connection.State = .disconnected

    private var socket: UI16Connection?

    /// Coalesces continuous writes (faders, gain, pan, sends) so drags don't flood the mixer.
    private let throttle = CommandThrottle()

    public init() {
        throttle.send = { [weak self] payload in self?.transmit(payload) }
    }

    // MARK: Connection

    public func connect(host: String, port: Int = 80) {
        if let existing = socket { Task { await existing.disconnect() } }
        let socket = UI16Connection(host: host, port: port)
        self.socket = socket
        Task {
            await socket.setCallbacks(
                onMessages: { [weak self] payloads in
                    // One hop to the main actor per frame, not per message.
                    Task { @MainActor in
                        guard let self else { return }
                        for payload in payloads { self.apply(payload) }
                    }
                },
                onStateChange: { [weak self] newState in
                    Task { @MainActor in
                        guard let self else { return }
                        self.connection = newState
                        self.state.connected = (newState == .connected)
                        // Shows/snapshots/cues are per-client and only sent on request,
                        // so they must be re-fetched on every (re)connect.
                        if newState == .connected { self.refreshShows() }
                    }
                }
            )
            await socket.connect()
        }
    }

    public func disconnect() {
        guard let socket else { return }
        Task { await socket.disconnect() }
    }

    // MARK: Outbound commands (corrected addresses)

    public func setMasterLevel(_ value: Double) {
        state.master.level = clamp01(value)
        sendContinuous(MasterAddress.mix, UI16Message.setd(MasterAddress.mix, state.master.level))
    }
    public func setMasterMute(_ muted: Bool) {
        state.master.muted = muted
        send(UI16Message.setd(MasterAddress.mute, muted))
    }
    public func setMasterPan(_ value: Double) {
        state.master.pan = round3(clamp01(value))
        sendContinuous(MasterAddress.pan, UI16Message.setd(MasterAddress.pan, state.master.pan))
    }
    public func setMasterDim(_ dim: Bool) {
        state.master.dim = dim
        send(UI16Message.setd(MasterAddress.dim, dim))
    }

    public func setLevel(_ ref: ChannelRef, _ value: Double) {
        mutate(ref) { $0.level = clamp01(value) }
        sendContinuous(UI16Key.mix(ref), UI16Message.setd(UI16Key.mix(ref), clamp01(value)))
    }
    public func setMute(_ ref: ChannelRef, _ muted: Bool) {
        mutate(ref) { $0.muted = muted }
        send(UI16Message.setd(UI16Key.mute(ref), muted))
    }
    public func setSolo(_ ref: ChannelRef, _ solo: Bool) {
        mutate(ref) { $0.solo = solo }
        send(UI16Message.setd(UI16Key.solo(ref), solo))
    }
    public func setPan(_ ref: ChannelRef, _ value: Double) {
        let v = round3(clamp01(value))
        mutate(ref) { $0.pan = v }
        sendContinuous(UI16Key.pan(ref), UI16Message.setd(UI16Key.pan(ref), v))
    }
    public func setGain(_ ref: ChannelRef, _ value: Double) {
        mutate(ref) { $0.gain = clamp01(value) }
        sendContinuous(UI16Key.gain(ref), UI16Message.setd(UI16Key.gain(ref), clamp01(value)))
    }
    public func setPhantom(_ ref: ChannelRef, _ enabled: Bool) {
        mutate(ref) { $0.phantom = enabled }
        send(UI16Message.setd(UI16Key.phantom(ref), enabled))
    }
    public func setName(_ ref: ChannelRef, _ name: String) {
        mutate(ref) { $0.name = name }
        send(UI16Message.sets(UI16Key.name(ref), name))
    }

    public func setSend(_ ref: ChannelRef, to bus: BusKind, _ busNumber: Int, _ value: Double) {
        let key = "\(bus.rawValue).\(busNumber - 1)"
        let v = clamp01(value)
        mutate(ref) { $0.sends[key] = v }
        sendContinuous(UI16Key.sendLevel(ref, to: bus, busNumber), UI16Message.setd(UI16Key.sendLevel(ref, to: bus, busNumber), v))
    }
    public func setSendPost(_ ref: ChannelRef, to bus: BusKind, _ busNumber: Int, _ post: Bool) {
        let key = "\(bus.rawValue).\(busNumber - 1)"
        mutate(ref) { $0.sendPost[key] = post }
        send(UI16Message.setd(UI16Key.sendPost(ref, to: bus, busNumber), post))
    }

    /// Generic escape hatch for the diagnostics layer: write any raw key. Lets the user
    /// operate parameters (EQ/gate/dynamics) whose exact keys the hardware reveals at runtime,
    /// without the app inventing command names.
    public func sendRawNumber(_ path: String, _ value: Double) {
        state.raw[path] = .number(value)
        sendContinuous(path, UI16Message.setd(path, value))
    }
    public func sendRawBool(_ path: String, _ value: Bool) {
        state.raw[path] = .number(value ? 1 : 0)
        send(UI16Message.setd(path, value))
    }
    public func sendRawString(_ path: String, _ value: String) {
        state.raw[path] = .string(value)
        send(UI16Message.sets(path, value))
    }

    // MARK: Inbound

    /// Apply a single inbound payload to the state. Exposed for unit testing.
    public func apply(_ payload: String) {
        if let body = UI16Message.vuBody(payload) {
            if let frame = VUDecoder.decode(base64: body) {
                state.vu = frame
                state.vuFrameCount += 1
            }
            return
        }
        if let list = UI16Shows.parseList(payload) {
            applyShowList(list)
            state.messageCount += 1
            return
        }
        guard let msg = UI16Message.parse(payload) else { return }
        state.lastMessage = payload
        state.messageCount += 1
        state.raw[msg.path] = (msg.kind == .setd) ? .number(msg.number ?? 0) : .string(msg.value)
        applyTyped(msg)
    }

    private func applyTyped(_ msg: UI16Message.Parsed) {
        let parts = msg.path.split(separator: ".").map(String.init)
        guard let first = parts.first else { return }

        // Master (`m.mix`, `m.mute`, `m.pan`, `m.dim`)
        if first == "m", parts.count == 2 {
            switch parts[1] {
            case "mix": state.master.level = msg.number ?? state.master.level
            case "mute": state.master.muted = msg.bool
            case "pan": state.master.pan = msg.number ?? state.master.pan
            case "dim": state.master.dim = msg.bool
            default: break
            }
            return
        }

        // Strip parameters (`<type>.<n>.<param...>`)
        guard let kind = ChannelKind(rawValue: first),
              parts.count >= 3,
              let zero = Int(parts[1]) else { return }
        let ref = ChannelRef(kind, zero + 1)
        let tail = Array(parts.dropFirst(2))

        mutate(ref) { s in
            switch tail.count {
            case 1:
                switch tail[0] {
                case "mix": s.level = msg.number ?? s.level
                case "mute": s.muted = msg.bool
                case "solo": s.solo = msg.bool
                case "pan": s.pan = msg.number ?? s.pan
                case "gain": s.gain = msg.number ?? s.gain
                case "phantom": s.phantom = msg.bool
                case "name": s.name = msg.value
                default: break
                }
            case 3:
                // send: `<bus>.<b>.value` / `<bus>.<b>.post`
                let key = "\(tail[0]).\(tail[1])"
                switch tail[2] {
                case "value": s.sends[key] = msg.number ?? s.sends[key]
                case "post": s.sendPost[key] = msg.bool
                default: break
                }
            default:
                break
            }
        }
    }

    // MARK: Monitoring buses (solo / headphones)

    public func setSoloVolume(_ value: Double) {
        let v = clamp01(value)
        state.raw[VolumeBus.solo] = .number(v)
        sendContinuous(VolumeBus.solo, UI16Message.setd(VolumeBus.solo, v))
    }

    public func setHeadphoneVolume(_ number: Int, _ value: Double) {
        let key = VolumeBus.headphones(number)
        let v = clamp01(value)
        state.raw[key] = .number(v)
        sendContinuous(key, UI16Message.setd(key, v))
    }

    // MARK: Shows / scenes

    /// Ask the mixer for its show list. Snapshot and cue lists are requested per show as
    /// the show names arrive. Resource lists are per-client, so this must run on every
    /// connect — the mixer does not push them.
    public func refreshShows() {
        send(UI16Shows.requestShows())
    }

    public func loadShow(_ show: String) { send(UI16Shows.loadShow(show)) }

    public func loadSnapshot(show: String, snapshot: String) {
        send(UI16Shows.loadSnapshot(show: show, snapshot: snapshot))
    }

    public func loadCue(show: String, cue: String) {
        send(UI16Shows.loadCue(show: show, cue: cue))
    }

    /// Overwrites an existing snapshot of the same name.
    public func saveSnapshot(show: String, snapshot: String) {
        send(UI16Shows.saveSnapshot(show: show, snapshot: snapshot))
    }

    /// Overwrites an existing cue of the same name.
    public func saveCue(show: String, cue: String) {
        send(UI16Shows.saveCue(show: show, cue: cue))
    }

    private func applyShowList(_ list: UI16Shows.ListReply) {
        switch list.command {
        case "SHOWLIST":
            for name in list.entries where state.shows[name] == nil {
                state.shows[name] = ShowDetail()
            }
            // drop shows the mixer no longer reports
            for name in state.shows.keys where !list.entries.contains(name) {
                state.shows[name] = nil
            }
            // the mixer only sends snapshots/cues when asked, per show
            for name in list.entries {
                send(UI16Shows.requestSnapshots(show: name))
                send(UI16Shows.requestCues(show: name))
            }
        case "SNAPSHOTLIST":
            guard let show = list.key else { return }
            var detail = state.shows[show] ?? ShowDetail()
            detail.snapshots = list.entries
            state.shows[show] = detail
        case "CUELIST":
            guard let show = list.key else { return }
            var detail = state.shows[show] ?? ShowDetail()
            detail.cues = list.entries
            state.shows[show] = detail
        default:
            break
        }
    }

    // MARK: Helpers

    /// Continuous parameter write — coalesced (see `CommandThrottle`).
    private func sendContinuous(_ key: String, _ payload: String) {
        throttle.submit(key: key, payload: payload)
    }

    /// Discrete parameter write — always sent immediately, never delayed.
    private func send(_ payload: String) {
        transmit(payload)
    }

    private func transmit(_ payload: String) {
        guard let socket else { return }
        Task { await socket.send(payload) }
    }

    private func mutate(_ ref: ChannelRef, _ change: (inout StripState) -> Void) {
        var s = state.strips[ref.address] ?? StripState()
        change(&s)
        state.strips[ref.address] = s
    }

    private func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
    private func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}
