import Foundation

/// The music index: metadata only, never audio.
///
/// Built for thousands of tracks — search runs against a precomputed, diacritic-folded
/// `searchKey` on each track, so a query is a single linear pass over small structs rather
/// than repeated string normalization. Audio files stay on disk and are opened only when
/// a track actually plays.
public struct MusicLibrary: Equatable, Sendable, Codable {

    public private(set) var tracks: [Track] = []
    /// Track ids marked as favourite.
    public private(set) var favorites: Set<UUID> = []
    /// Recently played track ids, most recent first.
    public private(set) var history: [UUID] = []
    /// Bookmarked root folders the user granted access to.
    public private(set) var roots: [LibraryRoot] = []

    public var maxHistory: Int = 200

    public init() {}

    // MARK: Indexing

    /// Add or replace tracks, de-duplicating by absolute path so a re-scan of the same
    /// folder updates metadata instead of creating duplicates.
    public mutating func upsert(_ incoming: [Track]) {
        var byPath: [String: Int] = [:]
        for (i, t) in tracks.enumerated() where !t.absolutePath.isEmpty {
            byPath[t.absolutePath] = i
        }
        for var track in incoming {
            track.refreshSearchKey()
            if !track.absolutePath.isEmpty, let existing = byPath[track.absolutePath] {
                // keep the original id so favourites/playlists/history stay valid
                let keptId = tracks[existing].id
                var updated = track
                updated = Track(
                    id: keptId,
                    fileName: track.fileName, title: track.title, artist: track.artist,
                    album: track.album, duration: track.duration,
                    fileExtension: track.fileExtension, folder: track.folder,
                    bookmark: track.bookmark, relativePath: track.relativePath,
                    absolutePath: track.absolutePath, hasArtwork: track.hasArtwork,
                    addedAt: tracks[existing].addedAt
                )
                tracks[existing] = updated
            } else {
                if !track.absolutePath.isEmpty { byPath[track.absolutePath] = tracks.count }
                tracks.append(track)
            }
        }
    }

    public mutating func removeTracks(where predicate: (Track) -> Bool) {
        let doomed = Set(tracks.filter(predicate).map(\.id))
        tracks.removeAll { doomed.contains($0.id) }
        favorites.subtract(doomed)
        history.removeAll { doomed.contains($0) }
    }

    public func track(id: UUID) -> Track? { tracks.first { $0.id == id } }
    public func tracks(ids: [UUID]) -> [Track] {
        let map = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { map[$0] }
    }

    // MARK: Roots (bookmarked folders)

    public mutating func addRoot(_ root: LibraryRoot) {
        if let i = roots.firstIndex(where: { $0.path == root.path }) {
            roots[i] = root
        } else {
            roots.append(root)
        }
    }

    public mutating func removeRoot(id: UUID) {
        guard let root = roots.first(where: { $0.id == id }) else { return }
        roots.removeAll { $0.id == id }
        removeTracks { $0.absolutePath.hasPrefix(root.path) }
    }

    // MARK: Search

    /// Instant search across title, artist, album, file name and folder.
    ///
    /// All terms must match (AND), so "mc kevin bh" narrows instead of widening.
    public func search(_ query: String, scope: SearchScope = .all) -> [Track] {
        let terms = MusicLibrary.normalize(query)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        let base: [Track]
        switch scope {
        case .all: base = tracks
        case .favorites: base = tracks.filter { favorites.contains($0.id) }
        case .folder(let name):
            let f = MusicLibrary.normalize(name)
            base = tracks.filter { MusicLibrary.normalize($0.folder) == f }
        }

        guard !terms.isEmpty else { return base }
        return base.filter { track in
            terms.allSatisfy { track.searchKey.contains($0) }
        }
    }

    public enum SearchScope: Equatable, Sendable {
        case all
        case favorites
        case folder(String)
    }

    public static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    // MARK: Browsing

    /// Distinct folder names, sorted, with how many tracks each holds.
    public var folders: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for t in tracks where !t.folder.isEmpty {
            counts[t.folder, default: 0] += 1
        }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func tracks(inFolder folder: String) -> [Track] {
        tracks.filter { $0.folder == folder }
    }

    public var artists: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for t in tracks {
            let a = t.artist.isEmpty ? "—" : t.artist
            counts[a, default: 0] += 1
        }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Sorting

    public enum SortOrder: String, CaseIterable, Codable, Sendable {
        case title, artist, folder, recent, duration

        public var label: String {
            switch self {
            case .title: return "TÍTULO"
            case .artist: return "ARTISTA"
            case .folder: return "PASTA"
            case .recent: return "RECENTE"
            case .duration: return "DURAÇÃO"
            }
        }
    }

    public static func sort(_ list: [Track], by order: SortOrder) -> [Track] {
        switch order {
        case .title:
            return list.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .artist:
            return list.sorted {
                let a = $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist)
                if a != .orderedSame { return a == .orderedAscending }
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        case .folder:
            return list.sorted {
                let f = $0.folder.localizedCaseInsensitiveCompare($1.folder)
                if f != .orderedSame { return f == .orderedAscending }
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        case .recent:
            return list.sorted { $0.addedAt > $1.addedAt }
        case .duration:
            return list.sorted { $0.duration < $1.duration }
        }
    }

    // MARK: Favourites and history

    public func isFavorite(_ id: UUID) -> Bool { favorites.contains(id) }

    public mutating func toggleFavorite(_ id: UUID) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
    }

    public var favoriteTracks: [Track] { tracks.filter { favorites.contains($0.id) } }

    /// Record a play. The same track moves to the front instead of piling up.
    public mutating func recordPlay(_ id: UUID) {
        history.removeAll { $0 == id }
        history.insert(id, at: 0)
        if history.count > maxHistory { history.removeLast(history.count - maxHistory) }
    }

    public var historyTracks: [Track] { tracks(ids: history) }

    public mutating func clearHistory() { history.removeAll() }
}

/// A folder the user granted access to through the Files app.
public struct LibraryRoot: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var path: String
    /// Security-scoped bookmark, so access survives relaunches without copying files.
    public var bookmark: Data?
    public var trackCount: Int
    public var addedAt: Date

    public init(id: UUID = UUID(), name: String, path: String,
                bookmark: Data? = nil, trackCount: Int = 0, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.trackCount = trackCount
        self.addedAt = addedAt
    }
}
