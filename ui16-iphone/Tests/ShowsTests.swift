import XCTest
@testable import UI16Controller

final class ShowsTests: XCTestCase {

    func testParsesFlatShowList() {
        let r = UI16Shows.parseList("SHOWLIST^Default^Igreja^Show Rua")
        XCTAssertEqual(r?.command, "SHOWLIST")
        XCTAssertNil(r?.key)
        XCTAssertEqual(r?.entries, ["Default", "Igreja", "Show Rua"])
    }

    func testParsesKeyedSnapshotList() {
        let r = UI16Shows.parseList("SNAPSHOTLIST^Igreja^Abertura^Louvor")
        XCTAssertEqual(r?.command, "SNAPSHOTLIST")
        XCTAssertEqual(r?.key, "Igreja")
        XCTAssertEqual(r?.entries, ["Abertura", "Louvor"])
    }

    func testEmptyListHasNoEntries() {
        // An empty list arrives with a trailing separator and must not yield a blank entry.
        let r = UI16Shows.parseList("CUELIST^Default^")
        XCTAssertEqual(r?.key, "Default")
        XCTAssertEqual(r?.entries, [])
    }

    func testIgnoresUnrelatedPayloads() {
        XCTAssertNil(UI16Shows.parseList("SETD^i.0.mix^0.5"))
        XCTAssertNil(UI16Shows.parseList("ALIVE"))
        XCTAssertNil(UI16Shows.parseList("VU2^AAAA"))
    }

    func testBuildsRecallCommands() {
        XCTAssertEqual(UI16Shows.loadShow("Igreja"), "LOADSHOW^Igreja")
        XCTAssertEqual(UI16Shows.loadSnapshot(show: "Igreja", snapshot: "Louvor"),
                       "LOADSNAPSHOT^Igreja^Louvor")
        XCTAssertEqual(UI16Shows.loadCue(show: "Igreja", cue: "Cue 1"),
                       "LOADCUE^Igreja^Cue 1")
        XCTAssertEqual(UI16Shows.saveSnapshot(show: "Igreja", snapshot: "Louvor"),
                       "SAVESNAPSHOT^Igreja^Louvor")
        XCTAssertEqual(UI16Shows.requestSnapshots(show: "Igreja"), "SNAPSHOTLIST^Igreja")
    }
}

@MainActor
final class StoreShowsTests: XCTestCase {

    func testStoresShowsSnapshotsAndCues() {
        let store = UI16Store()
        store.apply("SHOWLIST^Default^Igreja")
        XCTAssertEqual(store.state.showNames, ["Default", "Igreja"])

        store.apply("SNAPSHOTLIST^Igreja^Abertura^Louvor")
        store.apply("CUELIST^Igreja^Cue 1")
        XCTAssertEqual(store.state.shows["Igreja"]?.snapshots, ["Abertura", "Louvor"])
        XCTAssertEqual(store.state.shows["Igreja"]?.cues, ["Cue 1"])
    }

    func testShowListRemovesStaleShows() {
        let store = UI16Store()
        store.apply("SHOWLIST^Default^Antigo")
        XCTAssertEqual(store.state.showNames, ["Antigo", "Default"])
        // The mixer no longer reports "Antigo" — it must disappear.
        store.apply("SHOWLIST^Default")
        XCTAssertEqual(store.state.showNames, ["Default"])
    }

    func testCurrentShowComesFromState() {
        let store = UI16Store()
        store.apply("SETS^var.currentShow^Igreja")
        store.apply("SETS^var.currentSnapshot^Louvor")
        XCTAssertEqual(store.state.currentShow, "Igreja")
        XCTAssertEqual(store.state.currentSnapshot, "Louvor")
    }
}
