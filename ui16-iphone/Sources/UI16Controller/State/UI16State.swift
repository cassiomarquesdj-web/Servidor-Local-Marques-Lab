import Foundation

/// A raw value from the mixer state (numeric for `SETD`, string for `SETS`).
public enum RawValue: Equatable, Sendable {
    case number(Double)
    case string(String)

    public var double: Double? { if case .number(let v) = self { return v }; return Double(text) }
    public var text: String {
        switch self {
        case .number(let v): return UI16Message.formatNumber(v)
        case .string(let s): return s
        }
    }
    public var bool: Bool { (double ?? 0) != 0 || text.lowercased() == "true" }
}

/// State of a single mixer strip (input/line/player/fx/sub/aux) on the master bus.
public struct StripState: Equatable, Sendable {
    public var name = ""
    public var level = 0.0
    public var muted = false
    public var solo = false
    public var pan = 0.5
    public var gain = 0.0
    public var phantom = false
    /// Send level per destination address key (`aux.0`, `fx.1`, …) -> `0...1`.
    public var sends: [String: Double] = [:]
    /// Whether each send is post-fader, keyed the same way as `sends`.
    public var sendPost: [String: Bool] = [:]
    public init() {}
}

/// State of the master output.
public struct MasterState: Equatable, Sendable {
    public var level = 0.0
    public var muted = false
    public var pan = 0.5
    public var dim = false
    public init() {}
}

/// The full observable mixer state.
public struct UI16State: Equatable, Sendable {
    public var connected = false
    public var master = MasterState()

    /// Strips keyed by wire address (`i.0`, `a.2`, …).
    public var strips: [String: StripState] = [:]

    /// Complete raw state: every `SETD`/`SETS` key the mixer has sent. This is the
    /// diagnostics layer — it preserves parameters that have no dedicated control yet.
    public var raw: [String: RawValue] = [:]

    /// Latest decoded VU meter frame.
    public var vu = VUFrame()

    /// Shows (scenes) with their snapshots and cues, keyed by show name.
    public var shows: [String: ShowDetail] = [:]

    public var lastMessage = ""
    public var messageCount = 0
    public var vuFrameCount = 0

    public init() {
        for ref in UI16Model.allStrips {
            strips[ref.address] = StripState()
        }
    }

    public func strip(_ ref: ChannelRef) -> StripState {
        strips[ref.address] ?? StripState()
    }

    /// Display label for a strip: mixer-provided name, else the default.
    public func label(_ ref: ChannelRef) -> String {
        let n = strip(ref).name
        return n.isEmpty ? ref.defaultLabel : n
    }

    /// Name of the currently loaded show, snapshot and cue (reported by the mixer).
    public var currentShow: String { raw[UI16Shows.currentShowKey]?.text ?? "" }
    public var currentSnapshot: String { raw[UI16Shows.currentSnapshotKey]?.text ?? "" }
    public var currentCue: String { raw[UI16Shows.currentCueKey]?.text ?? "" }

    /// Show names in a stable order.
    public var showNames: [String] { shows.keys.sorted() }

    /// All raw keys that begin with a given prefix, sorted — used to render processing
    /// (EQ/gate/dynamics) and diagnostics without hardcoding parameter names.
    public func rawKeys(withPrefix prefix: String) -> [String] {
        raw.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }
}
