import XCTest
@testable import ParedaoCore

final class PlaylistTests: XCTestCase {

    func testCreateAndRename() {
        var store = PlaylistStore()
        let p = store.create(name: "Abertura")
        XCTAssertEqual(store.count, 1)
        store.rename(id: p.id, to: "Abertura 2026")
        XCTAssertEqual(store.playlist(id: p.id)?.name, "Abertura 2026")
    }

    func testDuplicateNamesAreDisambiguated() {
        // Two playlists with the same name are indistinguishable in a list mid-show.
        var store = PlaylistStore()
        _ = store.create(name: "Set")
        let second = store.create(name: "Set")
        XCTAssertEqual(second.name, "Set 2")
        let third = store.create(name: "set")
        XCTAssertEqual(third.name, "set 3")
    }

    func testEmptyNameFallsBackAndRenameIgnoresBlank() {
        var store = PlaylistStore()
        let p = store.create(name: "   ")
        XCTAssertEqual(p.name, "Playlist")
        store.rename(id: p.id, to: "  ")
        XCTAssertEqual(store.playlist(id: p.id)?.name, "Playlist", "nome em branco é ignorado")
    }

    func testAddRemoveTracks() {
        var store = PlaylistStore()
        let p = store.create(name: "Set")
        let a = UUID(), b = UUID()
        store.addTracks([a, b], to: p.id)
        XCTAssertEqual(store.playlist(id: p.id)?.trackIDs, [a, b])
        store.update(id: p.id) { $0.remove(at: 0) }
        XCTAssertEqual(store.playlist(id: p.id)?.trackIDs, [b])
    }

    func testDuplicateTrackIsAllowed() {
        // Playing the same anthem twice in a set is legitimate.
        var playlist = Playlist(name: "Set")
        let a = UUID()
        playlist.add(a)
        playlist.add(a)
        XCTAssertEqual(playlist.count, 2)
    }

    func testRemoveAtRemovesOnlyThatEntry() {
        var playlist = Playlist(name: "Set")
        let a = UUID(), b = UUID()
        playlist.add(contentsOf: [a, b, a])
        playlist.remove(at: 0)
        XCTAssertEqual(playlist.trackIDs, [b, a])
    }

    func testRemoveAllOfTrack() {
        var playlist = Playlist(name: "Set")
        let a = UUID(), b = UUID()
        playlist.add(contentsOf: [a, b, a])
        playlist.removeAll(of: a)
        XCTAssertEqual(playlist.trackIDs, [b])
    }

    // MARK: Reordering

    func testMoveSingleEntryDown() {
        var playlist = Playlist(name: "Set")
        let ids = (0..<4).map { _ in UUID() }
        playlist.add(contentsOf: ids)
        playlist.move(from: 0, to: 2)
        XCTAssertEqual(playlist.trackIDs, [ids[1], ids[2], ids[0], ids[3]])
    }

    func testMoveSingleEntryUp() {
        var playlist = Playlist(name: "Set")
        let ids = (0..<4).map { _ in UUID() }
        playlist.add(contentsOf: ids)
        playlist.move(from: 3, to: 1)
        XCTAssertEqual(playlist.trackIDs, [ids[0], ids[3], ids[1], ids[2]])
    }

    func testMoveWithIndexSetMatchesSwiftUISemantics() {
        var playlist = Playlist(name: "Set")
        let ids = (0..<4).map { _ in UUID() }
        playlist.add(contentsOf: ids)
        // Drag item 0 to the end: SwiftUI passes destination == count.
        playlist.move(from: IndexSet(integer: 0), to: 4)
        XCTAssertEqual(playlist.trackIDs, [ids[1], ids[2], ids[3], ids[0]])
    }

    func testMoveMultipleEntries() {
        var playlist = Playlist(name: "Set")
        let ids = (0..<5).map { _ in UUID() }
        playlist.add(contentsOf: ids)
        playlist.move(from: IndexSet([0, 1]), to: 4)
        XCTAssertEqual(playlist.trackIDs, [ids[2], ids[3], ids[0], ids[1], ids[4]])
    }

    func testMoveOutOfRangeIsIgnored() {
        var playlist = Playlist(name: "Set")
        let ids = (0..<3).map { _ in UUID() }
        playlist.add(contentsOf: ids)
        playlist.move(from: 9, to: 0)
        XCTAssertEqual(playlist.trackIDs, ids)
    }

    // MARK: Pruning

    func testPruneDropsMissingTracks() {
        var store = PlaylistStore()
        let p = store.create(name: "Set")
        let alive = UUID(), dead = UUID()
        store.addTracks([alive, dead], to: p.id)
        store.prune(existing: [alive])
        XCTAssertEqual(store.playlist(id: p.id)?.trackIDs, [alive])
    }

    func testDelete() {
        var store = PlaylistStore()
        let p = store.create(name: "Set")
        store.delete(id: p.id)
        XCTAssertEqual(store.count, 0)
    }

    func testUpdatedAtChangesOnEdit() {
        var playlist = Playlist(name: "Set", updatedAt: Date(timeIntervalSince1970: 0))
        playlist.add(UUID())
        XCTAssertGreaterThan(playlist.updatedAt.timeIntervalSince1970, 0)
    }
}
