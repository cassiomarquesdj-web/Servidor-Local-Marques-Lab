import Foundation

/// An ordered set of track references. Stores ids, not tracks, so renaming or re-indexing
/// a file never orphans a playlist entry.
public struct Playlist: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public private(set) var trackIDs: [UUID]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, trackIDs: [UUID] = [],
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var count: Int { trackIDs.count }
    public var isEmpty: Bool { trackIDs.isEmpty }

    /// Append a track. Duplicates are allowed — a set can legitimately repeat a track.
    public mutating func add(_ trackID: UUID) {
        trackIDs.append(trackID)
        updatedAt = Date()
    }

    public mutating func add(contentsOf ids: [UUID]) {
        guard !ids.isEmpty else { return }
        trackIDs.append(contentsOf: ids)
        updatedAt = Date()
    }

    /// Remove the entry at a position (not every copy of the track).
    public mutating func remove(at index: Int) {
        guard trackIDs.indices.contains(index) else { return }
        trackIDs.remove(at: index)
        updatedAt = Date()
    }

    public mutating func removeAll(of trackID: UUID) {
        let before = trackIDs.count
        trackIDs.removeAll { $0 == trackID }
        if trackIDs.count != before { updatedAt = Date() }
    }

    /// Move entries, matching SwiftUI's `onMove` semantics.
    ///
    /// Implemented here rather than using `move(fromOffsets:toOffset:)` because that method
    /// comes from SwiftUI, and this layer stays free of UI frameworks so it can be tested
    /// without a simulator.
    public mutating func move(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().filter { trackIDs.indices.contains($0) }
        guard !moving.isEmpty else { return }
        let items = moving.map { trackIDs[$0] }
        // How many removed entries sat before the insertion point — the destination is
        // expressed against the pre-removal array.
        let shift = moving.filter { $0 < destination }.count
        for index in moving.reversed() { trackIDs.remove(at: index) }
        let insertAt = min(max(destination - shift, 0), trackIDs.count)
        trackIDs.insert(contentsOf: items, at: insertAt)
        updatedAt = Date()
    }

    /// Move a single entry by index, for explicit up/down buttons.
    public mutating func move(from index: Int, to newIndex: Int) {
        guard trackIDs.indices.contains(index),
              newIndex >= 0, newIndex < trackIDs.count, index != newIndex else { return }
        let item = trackIDs.remove(at: index)
        trackIDs.insert(item, at: newIndex)
        updatedAt = Date()
    }

    /// Drop references to tracks that no longer exist in the library.
    public mutating func prune(existing: Set<UUID>) {
        let before = trackIDs.count
        trackIDs.removeAll { !existing.contains($0) }
        if trackIDs.count != before { updatedAt = Date() }
    }
}

/// Collection of playlists with the operations the UI needs.
public struct PlaylistStore: Equatable, Codable, Sendable {
    public private(set) var playlists: [Playlist] = []

    public init(playlists: [Playlist] = []) { self.playlists = playlists }

    public var count: Int { playlists.count }

    public func playlist(id: UUID) -> Playlist? { playlists.first { $0.id == id } }

    @discardableResult
    public mutating func create(name: String) -> Playlist {
        let playlist = Playlist(name: uniqueName(from: name))
        playlists.append(playlist)
        return playlist
    }

    public mutating func rename(id: UUID, to newName: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlists[i].name = uniqueName(from: trimmed, excluding: id)
        playlists[i].updatedAt = Date()
    }

    public mutating func delete(id: UUID) {
        playlists.removeAll { $0.id == id }
    }

    public mutating func update(id: UUID, _ change: (inout Playlist) -> Void) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        change(&playlists[i])
    }

    public mutating func addTracks(_ ids: [UUID], to playlistID: UUID) {
        update(id: playlistID) { $0.add(contentsOf: ids) }
    }

    /// Remove library-deleted tracks from every playlist.
    public mutating func prune(existing: Set<UUID>) {
        for i in playlists.indices { playlists[i].prune(existing: existing) }
    }

    /// Keep names distinct so the operator can tell two playlists apart at a glance.
    private func uniqueName(from name: String, excluding: UUID? = nil) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Playlist" : trimmed
        let taken = Set(playlists.filter { $0.id != excluding }.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}
