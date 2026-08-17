import XCTest
@testable import ParedaoCore

final class MusicLibraryTests: XCTestCase {

    private func sample() -> MusicLibrary {
        var lib = MusicLibrary()
        lib.upsert([
            Track(fileName: "01 Coracao", title: "Coração Partido", artist: "MC João",
                  album: "Baile", duration: 180, fileExtension: "mp3", folder: "Funk",
                  absolutePath: "/m/Funk/01.mp3"),
            Track(fileName: "02 Sertao", title: "Sertão", artist: "Zé da Viola",
                  album: "Raiz", duration: 240, fileExtension: "wav", folder: "Sertanejo",
                  absolutePath: "/m/Sertanejo/02.wav"),
            Track(fileName: "03 Paredao", title: "Paredão Ligado", artist: "MC João",
                  album: "Baile", duration: 200, fileExtension: "flac", folder: "Funk",
                  absolutePath: "/m/Funk/03.flac"),
        ])
        return lib
    }

    // MARK: Search

    func testSearchByTitle() {
        let lib = sample()
        XCTAssertEqual(lib.search("paredao").map(\.title), ["Paredão Ligado"])
    }

    func testSearchIgnoresAccents() {
        // Typing without accents is normal on a phone mid-show; it must still match.
        let lib = sample()
        XCTAssertEqual(lib.search("coracao").count, 1)
        XCTAssertEqual(lib.search("sertao").count, 1)
        XCTAssertEqual(lib.search("SERTÃO").count, 1)
    }

    func testSearchByArtist() {
        let lib = sample()
        XCTAssertEqual(lib.search("mc joao").count, 2)
    }

    func testSearchByFolder() {
        let lib = sample()
        XCTAssertEqual(lib.search("funk").count, 2)
    }

    func testMultipleTermsNarrowResults() {
        let lib = sample()
        XCTAssertEqual(lib.search("mc joao paredao").count, 1)
        XCTAssertEqual(lib.search("mc joao inexistente").count, 0)
    }

    func testEmptyQueryReturnsEverything() {
        let lib = sample()
        XCTAssertEqual(lib.search("").count, 3)
        XCTAssertEqual(lib.search("   ").count, 3)
    }

    func testSearchScopedToFolder() {
        let lib = sample()
        XCTAssertEqual(lib.search("", scope: .folder("Funk")).count, 2)
    }

    func testSearchScopedToFavorites() {
        var lib = sample()
        lib.toggleFavorite(lib.tracks[0].id)
        XCTAssertEqual(lib.search("", scope: .favorites).count, 1)
    }

    // MARK: Indexing

    func testUpsertDeduplicatesByPathAndKeepsIdentity() {
        var lib = sample()
        let originalID = lib.tracks[0].id
        lib.toggleFavorite(originalID)

        // Re-scanning the same folder must update metadata, not duplicate the track,
        // and must not orphan favourites or playlist references.
        lib.upsert([
            Track(fileName: "01 Coracao", title: "Coração Partido (Remix)", artist: "MC João",
                  duration: 190, folder: "Funk", absolutePath: "/m/Funk/01.mp3")
        ])

        XCTAssertEqual(lib.tracks.count, 3, "não deve duplicar")
        XCTAssertEqual(lib.tracks[0].id, originalID, "id preservado")
        XCTAssertEqual(lib.tracks[0].title, "Coração Partido (Remix)", "metadados atualizados")
        XCTAssertTrue(lib.isFavorite(originalID), "favorito preservado")
    }

    func testSearchKeyUpdatesAfterUpsert() {
        var lib = sample()
        lib.upsert([
            Track(fileName: "01 Coracao", title: "Nome Novo", artist: "Outro",
                  folder: "Funk", absolutePath: "/m/Funk/01.mp3")
        ])
        XCTAssertEqual(lib.search("nome novo").count, 1)
    }

    func testRemoveTracksClearsFavoritesAndHistory() {
        var lib = sample()
        let id = lib.tracks[0].id
        lib.toggleFavorite(id)
        lib.recordPlay(id)
        lib.removeTracks { $0.id == id }
        XCTAssertEqual(lib.tracks.count, 2)
        XCTAssertFalse(lib.isFavorite(id))
        XCTAssertTrue(lib.history.isEmpty)
    }

    // MARK: Browsing

    func testFoldersAreCounted() {
        let lib = sample()
        let folders = lib.folders
        XCTAssertEqual(folders.count, 2)
        XCTAssertEqual(folders.first(where: { $0.name == "Funk" })?.count, 2)
    }

    func testArtistsAreCounted() {
        let lib = sample()
        XCTAssertEqual(lib.artists.first(where: { $0.name == "MC João" })?.count, 2)
    }

    // MARK: Sorting

    func testSortByTitle() {
        let lib = sample()
        let sorted = MusicLibrary.sort(lib.tracks, by: .title)
        XCTAssertEqual(sorted.map(\.title), ["Coração Partido", "Paredão Ligado", "Sertão"])
    }

    func testSortByArtistThenTitle() {
        let lib = sample()
        let sorted = MusicLibrary.sort(lib.tracks, by: .artist)
        XCTAssertEqual(sorted.map(\.artist), ["MC João", "MC João", "Zé da Viola"])
        XCTAssertEqual(sorted[0].title, "Coração Partido")
    }

    func testSortByDuration() {
        let lib = sample()
        XCTAssertEqual(MusicLibrary.sort(lib.tracks, by: .duration).map(\.duration), [180, 200, 240])
    }

    // MARK: Favourites and history

    func testToggleFavorite() {
        var lib = sample()
        let id = lib.tracks[0].id
        lib.toggleFavorite(id)
        XCTAssertTrue(lib.isFavorite(id))
        lib.toggleFavorite(id)
        XCTAssertFalse(lib.isFavorite(id))
    }

    func testHistoryMovesRepeatToFrontWithoutDuplicating() {
        var lib = sample()
        let a = lib.tracks[0].id, b = lib.tracks[1].id
        lib.recordPlay(a)
        lib.recordPlay(b)
        lib.recordPlay(a)
        XCTAssertEqual(lib.history, [a, b], "sem duplicata, mais recente primeiro")
    }

    func testHistoryIsCapped() {
        var lib = MusicLibrary()
        lib.maxHistory = 3
        let tracks = (1...5).map { Track(fileName: "t\($0)", absolutePath: "/p/\($0)") }
        lib.upsert(tracks)
        for t in lib.tracks { lib.recordPlay(t.id) }
        XCTAssertEqual(lib.history.count, 3)
    }

    // MARK: Roots

    func testRemovingRootRemovesItsTracks() {
        var lib = sample()
        let root = LibraryRoot(name: "Funk", path: "/m/Funk")
        lib.addRoot(root)
        lib.removeRoot(id: root.id)
        XCTAssertEqual(lib.tracks.count, 1, "só sobra o que estava fora da pasta")
        XCTAssertEqual(lib.tracks.first?.folder, "Sertanejo")
    }

    // MARK: Scale

    func testSearchStaysFastWithManyTracks() {
        var lib = MusicLibrary()
        let many = (1...5000).map {
            Track(fileName: "file\($0)", title: "Música \($0)", artist: "Artista \($0 % 50)",
                  folder: "Pasta \($0 % 20)", absolutePath: "/m/\($0).mp3")
        }
        lib.upsert(many)
        XCTAssertEqual(lib.tracks.count, 5000)

        let started = Date()
        let hits = lib.search("artista 7")
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertFalse(hits.isEmpty)
        XCTAssertLessThan(elapsed, 0.5, "busca precisa continuar instantânea com milhares de músicas")
    }

    func testSupportedFormats() {
        XCTAssertTrue(Track.isSupported(URL(fileURLWithPath: "/a/b.mp3")))
        XCTAssertTrue(Track.isSupported(URL(fileURLWithPath: "/a/b.FLAC")))
        XCTAssertTrue(Track.isSupported(URL(fileURLWithPath: "/a/b.m4a")))
        XCTAssertTrue(Track.isSupported(URL(fileURLWithPath: "/a/b.aiff")))
        XCTAssertTrue(Track.isSupported(URL(fileURLWithPath: "/a/b.wav")))
        XCTAssertFalse(Track.isSupported(URL(fileURLWithPath: "/a/b.txt")))
        XCTAssertFalse(Track.isSupported(URL(fileURLWithPath: "/a/b.jpg")))
    }

    func testDurationFormatting() {
        XCTAssertEqual(Track.timeText(0), "0:00")
        XCTAssertEqual(Track.timeText(65), "1:05")
        XCTAssertEqual(Track.timeText(3661), "1:01:01")
        XCTAssertEqual(Track.timeText(-5), "0:00")
    }
}
