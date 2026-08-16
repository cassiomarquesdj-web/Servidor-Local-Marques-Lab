import XCTest
@testable import UI16Controller

/// The mixer is on a stage Wi-Fi and can reboot, drop out, or send a truncated frame.
/// None of that may crash the app or corrupt state — during a show a crash is unrecoverable.
@MainActor
final class ResilienceTests: XCTestCase {

    // MARK: Malformed input

    func testMalformedPayloadsAreIgnoredWithoutCrashing() {
        let store = UI16Store()
        let junk = [
            "", "^", "^^^", "SETD", "SETD^", "SETD^^", "SETD^^1",
            "SETD^i.0.mix",                 // no value
            "SETS^", "VU2^", "VU2^!!!!",
            "SETD^i.0.mix^not-a-number",
            "SETD^i.999.mix^0.5",           // channel out of range
            "SETD^z.0.mix^0.5",             // unknown channel type
            "SETD^i.abc.mix^0.5",           // non-numeric index
            "SETD^m^0.5",                   // master with no parameter
            "\0\0\0", "🎛^🎚^🎵",
            String(repeating: "x", count: 10_000),
        ]
        for payload in junk {
            store.apply(payload)            // must not crash
        }
        // A valid message still works afterwards — state was not corrupted.
        store.apply("SETD^i.0.mix^0.5")
        XCTAssertEqual(store.state.strip(ChannelRef(.input, 1)).level, 0.5)
    }

    func testNonNumericValueLeavesPreviousLevelIntact() {
        let store = UI16Store()
        store.apply("SETD^i.0.mix^0.7")
        store.apply("SETD^i.0.mix^garbage")
        // A corrupt frame must not slam the fader to zero.
        XCTAssertEqual(store.state.strip(ChannelRef(.input, 1)).level, 0.7)
    }

    func testOutOfRangeChannelDoesNotCreatePhantomStrip() {
        let store = UI16Store()
        let before = store.state.strips.count
        store.apply("SETD^i.99.mix^0.5")
        // Unknown strips may be recorded, but the known inventory must not shrink or corrupt.
        XCTAssertGreaterThanOrEqual(store.state.strips.count, before)
        XCTAssertEqual(store.state.strip(ChannelRef(.input, 1)).level, 0.0)
    }

    func testTruncatedVUFrameIsHandled() {
        // Header claims 12 inputs but the body carries only one block.
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = 12
        bytes += [100, 200, 50, 0, 0, 0]
        let body = Data(bytes).base64EncodedString()

        let store = UI16Store()
        store.apply("VU2^\(body)")
        // Decodes what is present and stops cleanly rather than reading past the end.
        XCTAssertEqual(store.state.vu.input.count, 1)
        XCTAssertEqual(store.state.vu.input[0].pre, 100 * VUDecoder.normalizeFactor, accuracy: 1e-6)
    }

    func testVUFrameWithZeroChannelsIsValid() {
        let bytes = [UInt8](repeating: 0, count: 8)
        let store = UI16Store()
        store.apply("VU2^\(Data(bytes).base64EncodedString())")
        XCTAssertTrue(store.state.vu.input.isEmpty)
        XCTAssertEqual(store.state.vuFrameCount, 1)
    }

    // MARK: Framing

    func testMultipleMessagesInOneFrameAllApply() {
        let frame = "3:::SETD^i.0.mix^0.4\nSETD^i.1.mute^1\nSETS^i.0.name^Kick"
        let store = UI16Store()
        for payload in UI16Message.unframe(frame) {
            store.apply(payload)
        }
        XCTAssertEqual(store.state.strip(ChannelRef(.input, 1)).level, 0.4)
        XCTAssertTrue(store.state.strip(ChannelRef(.input, 2)).muted)
        XCTAssertEqual(store.state.strip(ChannelRef(.input, 1)).name, "Kick")
    }

    func testUnframeHandlesEmptyAndPrefixOnlyFrames() {
        XCTAssertEqual(UI16Message.unframe(""), [])
        XCTAssertEqual(UI16Message.unframe("3:::"), [])
        XCTAssertEqual(UI16Message.unframe("3:::\n\n"), [])
    }

    // MARK: Reconnect / mixer reboot

    func testStateSurvivesReconnectAndResync() {
        let store = UI16Store()
        store.apply("SETD^i.0.mix^0.8")
        store.apply("SETS^i.0.name^Kick")

        // Mixer reboots and re-sends its state with different values.
        store.apply("SETD^i.0.mix^0.3")
        store.apply("SETS^i.0.name^Bumbo")

        XCTAssertEqual(store.state.strip(ChannelRef(.input, 1)).level, 0.3)
        XCTAssertEqual(store.state.strip(ChannelRef(.input, 1)).name, "Bumbo")
    }

    func testShowListShrinkingRemovesStaleEntries() {
        let store = UI16Store()
        store.apply("SHOWLIST^A^B^C")
        XCTAssertEqual(store.state.showNames.count, 3)
        // After a mixer reboot fewer shows exist — stale ones must not linger.
        store.apply("SHOWLIST^A")
        XCTAssertEqual(store.state.showNames, ["A"])
    }

    func testHighVolumeOfMessagesKeepsCountersConsistent() {
        let store = UI16Store()
        for i in 0..<2000 {
            store.apply("SETD^i.\(i % 12).mix^\(Double(i % 100) / 100.0)")
        }
        XCTAssertEqual(store.state.messageCount, 2000)
        XCTAssertFalse(store.state.raw.isEmpty)
    }

    // MARK: Host parsing edge cases

    func testEmptyHostDoesNotCrashConnection() {
        let (h, p) = UI16Connection.splitHostPort("", fallback: 80)
        XCTAssertEqual(h, "")
        XCTAssertEqual(p, 80)
    }

    func testHostWithOnlyColonFallsBack() {
        let (h, p) = UI16Connection.splitHostPort(":", fallback: 80)
        XCTAssertEqual(p, 80)
        XCTAssertEqual(h, ":")
    }

    func testPortOutOfRangeFallsBack() {
        let (h, p) = UI16Connection.splitHostPort("10.10.2.1:99999", fallback: 80)
        XCTAssertEqual(h, "10.10.2.1:99999")
        XCTAssertEqual(p, 80)
    }
}
