import XCTest
@testable import UI16Controller

@MainActor
final class StoreTests: XCTestCase {

    func testAppliesMaster() {
        let store = UI16Store()
        store.apply("SETD^m.mix^0.5")
        store.apply("SETD^m.mute^1")
        store.apply("SETD^m.pan^0.25")
        XCTAssertEqual(store.state.master.level, 0.5)
        XCTAssertTrue(store.state.master.muted)
        XCTAssertEqual(store.state.master.pan, 0.25)
    }

    func testAppliesStripLevelMuteSolo() {
        let store = UI16Store()
        store.apply("SETD^i.0.mix^0.8")
        store.apply("SETD^i.0.mute^1")
        store.apply("SETD^i.2.solo^1")
        XCTAssertEqual(store.state.strip(ChannelRef(.input, 1)).level, 0.8)
        XCTAssertTrue(store.state.strip(ChannelRef(.input, 1)).muted)
        XCTAssertTrue(store.state.strip(ChannelRef(.input, 3)).solo)
    }

    func testAppliesNameViaSetS() {
        let store = UI16Store()
        store.apply("SETS^i.0.name^Kick In")
        XCTAssertEqual(store.state.strip(ChannelRef(.input, 1)).name, "Kick In")
        XCTAssertEqual(store.state.label(ChannelRef(.input, 1)), "Kick In")
        // Unnamed strip falls back to default label.
        XCTAssertEqual(store.state.label(ChannelRef(.input, 2)), "IN 2")
    }

    func testAppliesAuxSend() {
        let store = UI16Store()
        store.apply("SETD^i.0.aux.1.value^0.6")
        store.apply("SETD^i.0.aux.1.post^1")
        XCTAssertEqual(store.state.strip(ChannelRef(.input, 1)).sends["aux.1"], 0.6)
        XCTAssertEqual(store.state.strip(ChannelRef(.input, 1)).sendPost["aux.1"], true)
    }

    func testRawLayerPreservesEverything() {
        let store = UI16Store()
        // A processing parameter with no dedicated control must still be preserved.
        store.apply("SETD^i.0.eq.high.gain^0.3")
        store.apply("SETD^i.0.gate.on^1")
        XCTAssertEqual(store.state.raw["i.0.eq.high.gain"]?.double, 0.3)
        XCTAssertEqual(store.state.raw["i.0.gate.on"]?.bool, true)
        XCTAssertEqual(store.state.rawKeys(withPrefix: "i.0.eq"), ["i.0.eq.high.gain"])
        XCTAssertEqual(store.state.messageCount, 2)
    }

    func testAppliesVUFrame() {
        let store = UI16Store()
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = 1
        bytes += [120, 240, 60, 0, 0, 0]
        let body = Data(bytes).base64EncodedString()
        store.apply("VU2^\(body)")
        XCTAssertEqual(store.state.vuFrameCount, 1)
        XCTAssertEqual(store.state.vu.postFader(for: ChannelRef(.input, 1)) ?? 0, 0.25, accuracy: 0.005)
    }
}
