import Foundation

/// Everything the Paredão mode persists between launches.
public struct ParedaoSnapshot: Codable, Equatable, Sendable {
    public var library = MusicLibrary()
    public var playlists = PlaylistStore()
    public var eq = EQSettings()
    public var repeatMode: RepeatMode = .off
    public var isShuffled = false
    public var volume: Double = 1
    public var lastTrackID: UUID?
    public var sortOrder: MusicLibrary.SortOrder = .title

    public init() {}
}

/// Disk persistence for the Paredão state.
///
/// Writes atomically to a temporary file and then replaces the target, so a crash or a
/// battery death mid-write can never leave a truncated index behind — the operator would
/// otherwise lose their whole library.
public struct ParedaoStorage {

    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    /// Default location inside Application Support.
    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Paredao", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("library.json")
    }

    public func load() throws -> ParedaoSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ParedaoSnapshot()
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return ParedaoSnapshot() }
        return try JSONDecoder().decode(ParedaoSnapshot.self, from: data)
    }

    /// Load, falling back to an empty snapshot if the file is corrupt rather than
    /// refusing to start. A damaged index must not brick the app before a show.
    public func loadOrEmpty() -> ParedaoSnapshot {
        (try? load()) ?? ParedaoSnapshot()
    }

    public func save(_ snapshot: ParedaoSnapshot) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
    }
}
