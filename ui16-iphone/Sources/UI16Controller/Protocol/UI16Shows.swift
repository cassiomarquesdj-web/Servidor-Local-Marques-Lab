import Foundation

/// Shows, snapshots and cues (the Ui equivalent of scenes/presets).
///
/// These are **not** part of the `SETD`/`SETS` state. They are per-client resource lists,
/// sent only when requested, using dedicated commands. Confirmed against
/// fmalcher/soundcraft-ui (`show-controller.ts`, `resource-lists.ts`).
///
/// Request / reply:
/// - `SHOWLIST`               -> `SHOWLIST^<show>^<show>…`
/// - `SNAPSHOTLIST^<show>`    -> `SNAPSHOTLIST^<show>^<snap>^<snap>…`
/// - `CUELIST^<show>`         -> `CUELIST^<show>^<cue>^<cue>…`
///
/// An empty list arrives with a trailing separator (`CUELIST^Default^`), which must not
/// be read as one empty-named entry.
public enum UI16Shows {

    /// Reply commands and whether they are keyed by a parent show.
    public static let listCommands: [String: Bool] = [
        "SHOWLIST": false,
        "SNAPSHOTLIST": true,
        "CUELIST": true,
        "PLISTS": false,
        "PLIST_TRACKS": true,
    ]

    /// A parsed resource-list reply.
    public struct ListReply: Equatable, Sendable {
        public let command: String
        /// Parent show/playlist name for keyed lists; `nil` for flat lists.
        public let key: String?
        public let entries: [String]
    }

    /// Parse a resource-list reply, or return `nil` if the payload isn't one.
    public static func parseList(_ payload: String) -> ListReply? {
        guard let sep = payload.firstIndex(of: "^") else { return nil }
        let command = String(payload[payload.startIndex..<sep])
        guard let keyed = listCommands[command] else { return nil }

        var parts = payload.split(separator: "^", omittingEmptySubsequences: false).map(String.init)
        parts.removeFirst()   // drop the command

        var key: String? = nil
        if keyed {
            guard !parts.isEmpty else { return nil }
            key = parts.removeFirst()
        }
        // trailing empty entry marks an empty list
        return ListReply(command: command, key: key, entries: parts.filter { !$0.isEmpty })
    }

    // MARK: Requests

    public static func requestShows() -> String { "SHOWLIST" }
    public static func requestSnapshots(show: String) -> String { "SNAPSHOTLIST^\(show)" }
    public static func requestCues(show: String) -> String { "CUELIST^\(show)" }

    // MARK: Recall

    public static func loadShow(_ show: String) -> String { "LOADSHOW^\(show)" }
    public static func loadSnapshot(show: String, snapshot: String) -> String {
        "LOADSNAPSHOT^\(show)^\(snapshot)"
    }
    public static func loadCue(show: String, cue: String) -> String { "LOADCUE^\(show)^\(cue)" }

    // MARK: Store (overwrites an existing entry of the same name)

    public static func saveSnapshot(show: String, snapshot: String) -> String {
        "SAVESNAPSHOT^\(show)^\(snapshot)"
    }
    public static func saveCue(show: String, cue: String) -> String { "SAVECUE^\(show)^\(cue)" }

    // MARK: Currently loaded (these DO arrive as ordinary state keys)

    public static let currentShowKey = "var.currentShow"
    public static let currentSnapshotKey = "var.currentSnapshot"
    public static let currentCueKey = "var.currentCue"
}

/// Snapshots and cues belonging to one show. They are parallel lists, not nested.
public struct ShowDetail: Equatable, Sendable {
    public var snapshots: [String] = []
    public var cues: [String] = []
    public init() {}
}
