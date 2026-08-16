import Foundation

/// Channel/bus families in the Soundcraft Ui address space.
///
/// Confirmed against the reference implementation (fmalcher/soundcraft-ui, `types.ts`
/// and `channel-sync-mapping.ts`). The address prefix is the raw letter used on the wire.
public enum ChannelKind: String, CaseIterable, Sendable, Codable, Hashable {
    case input = "i"     // mono mic/line input
    case line = "l"      // stereo line input
    case player = "p"    // media / USB player
    case fx = "f"        // FX return / bus
    case sub = "s"       // sub group
    case aux = "a"       // aux bus
    case vca = "v"       // VCA (Ui24R only)

    public var displayName: String {
        switch self {
        case .input: return "Input"
        case .line: return "Line"
        case .player: return "Player"
        case .fx: return "FX"
        case .sub: return "Sub"
        case .aux: return "Aux"
        case .vca: return "VCA"
        }
    }
}

/// A concrete addressable strip on the mixer, e.g. `i.0` or `a.2`.
///
/// `number` is 1-based (channel 1 = first). The wire address is 0-based (`i.0`).
public struct ChannelRef: Hashable, Sendable, Codable, Identifiable {
    public let kind: ChannelKind
    public let number: Int   // 1-based

    public init(_ kind: ChannelKind, _ number: Int) {
        self.kind = kind
        self.number = number
    }

    public var id: String { address }

    /// Zero-based wire address of the strip, e.g. `i.0`, `a.2`.
    public var address: String { "\(kind.rawValue).\(number - 1)" }

    /// A default display label, e.g. "IN 1", "LINE 2", "PLAYER 1".
    public var defaultLabel: String {
        switch kind {
        case .input: return "IN \(number)"
        case .line: return "LINE \(number)"
        case .player: return "PLAYER \(number)"
        case .fx: return "FX \(number)"
        case .sub: return "SUB \(number)"
        case .aux: return "AUX \(number)"
        case .vca: return "VCA \(number)"
        }
    }
}

/// Bus destinations that a channel can send to.
public enum BusKind: String, Sendable, Codable, Hashable {
    case aux
    case fx
    case mtx   // matrix (Ui24R)
}

/// The Soundcraft Ui16 device model: exact strip inventory and address layout.
///
/// Confirmed from `channel-sync-mapping.ts` (ui16 mapping): the Ui16 exposes
/// 12 mono inputs, 2 stereo line inputs, 2 players, 4 FX, 4 subs and 6 aux buses.
/// The marketing name "Ui16" = 16 input *sources* (12 mono + 2 line + 2 player),
/// **not** 16 mono channels — the previous implementation's `i.0...i.15` was wrong.
public enum UI16Model {
    public static let inputCount = 12
    public static let lineCount = 2
    public static let playerCount = 2
    public static let fxCount = 4
    public static let subCount = 4
    public static let auxCount = 6

    /// All 16 input *sources* in surface order: 12 inputs, 2 lines, 2 players.
    public static let inputSources: [ChannelRef] =
        (1...inputCount).map { ChannelRef(.input, $0) }
        + (1...lineCount).map { ChannelRef(.line, $0) }
        + (1...playerCount).map { ChannelRef(.player, $0) }

    public static let fxReturns: [ChannelRef] = (1...fxCount).map { ChannelRef(.fx, $0) }
    public static let subGroups: [ChannelRef] = (1...subCount).map { ChannelRef(.sub, $0) }
    public static let auxBuses: [ChannelRef] = (1...auxCount).map { ChannelRef(.aux, $0) }

    /// Every strip that has a fader on the master bus (used to seed state).
    public static let allStrips: [ChannelRef] =
        inputSources + fxReturns + subGroups + auxBuses
}

/// Master output address helpers. Master is addressed as `m.*` (no index) — confirmed
/// from `state-selectors.ts` (`m.mix`, `m.pan`, `m.dim`). The previous `m.0.*` was wrong.
public enum MasterAddress {
    public static let mix = "m.mix"
    public static let mute = "m.mute"
    public static let pan = "m.pan"
    public static let dim = "m.dim"
    public static let delayL = "m.delayL"
    public static let delayR = "m.delayR"
}

/// Builds the exact wire keys for parameters, so the app never hand-concatenates addresses.
public enum UI16Key {
    // MARK: Master-bus channel parameters (`<type>.<n>.<param>`)
    public static func mix(_ ch: ChannelRef) -> String { "\(ch.address).mix" }
    public static func mute(_ ch: ChannelRef) -> String { "\(ch.address).mute" }
    public static func solo(_ ch: ChannelRef) -> String { "\(ch.address).solo" }
    public static func pan(_ ch: ChannelRef) -> String { "\(ch.address).pan" }
    public static func gain(_ ch: ChannelRef) -> String { "\(ch.address).gain" }
    public static func phantom(_ ch: ChannelRef) -> String { "\(ch.address).phantom" }
    public static func name(_ ch: ChannelRef) -> String { "\(ch.address).name" }
    public static func stereoIndex(_ ch: ChannelRef) -> String { "\(ch.address).stereoIndex" }

    // MARK: Sends (`<type>.<n>.<bus>.<b>.value` / `.post`) — confirmed from send-channel.ts
    public static func sendLevel(_ ch: ChannelRef, to bus: BusKind, _ busNumber: Int) -> String {
        "\(ch.address).\(bus.rawValue).\(busNumber - 1).value"
    }
    public static func sendPost(_ ch: ChannelRef, to bus: BusKind, _ busNumber: Int) -> String {
        "\(ch.address).\(bus.rawValue).\(busNumber - 1).post"
    }

    // MARK: FX bus parameters
    public static func fxType(_ fxNumber: Int) -> String { "f.\(fxNumber - 1).fxtype" }
    public static func fxBpm(_ fxNumber: Int) -> String { "f.\(fxNumber - 1).bpm" }

    // MARK: Channel-processing prefixes (read/diagnostic; write keys pending hardware confirmation)
    // The mixer echoes all of its processing state on connect. These prefixes let the app
    // group whatever `eq/gate/dyn/hpf` keys the hardware actually reports. See docs/protocol.md.
    public static func processingPrefix(_ ch: ChannelRef) -> String { "\(ch.address)." }
}
