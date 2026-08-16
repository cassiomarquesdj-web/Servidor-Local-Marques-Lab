import XCTest
@testable import UI16Controller

final class VUDecoderTests: XCTestCase {

    /// Build a VU2 body: 8-byte preamble (counts in bytes 0...6), then blocks.
    private func makeBody() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = 1   // input count
        bytes[5] = 2   // master count (L, R)
        // input block (6 bytes): pre, post, postFader, pad, pad, pad
        bytes += [120, 240, 60, 0, 0, 0]
        // master L (5 bytes): post, postFader, pad, pad, pad
        bytes += [240, 120, 0, 0, 0]
        // master R (5 bytes)
        bytes += [48, 96, 0, 0, 0]
        return Data(bytes).base64EncodedString()
    }

    func testDecodesInputAndMaster() throws {
        let frame = try XCTUnwrap(VUDecoder.decode(base64: makeBody()))

        XCTAssertEqual(frame.input.count, 1)
        XCTAssertEqual(frame.input[0].pre, 0.5, accuracy: 0.005)
        XCTAssertEqual(frame.input[0].post, 1.0, accuracy: 0.005)
        XCTAssertEqual(frame.input[0].postFader, 0.25, accuracy: 0.005)

        XCTAssertEqual(frame.master.count, 2)
        let master = try XCTUnwrap(frame.masterPostFader)
        XCTAssertEqual(master.l, 0.5, accuracy: 0.005)
        XCTAssertEqual(master.r, 0.4, accuracy: 0.005)
    }

    func testPostFaderLookupByRef() throws {
        let frame = try XCTUnwrap(VUDecoder.decode(base64: makeBody()))
        let level = try XCTUnwrap(frame.postFader(for: ChannelRef(.input, 1)))
        XCTAssertEqual(level, 0.25, accuracy: 0.005)
        XCTAssertNil(frame.postFader(for: ChannelRef(.input, 5)))
    }

    func testRejectsMalformed() {
        XCTAssertNil(VUDecoder.decode(base64: "not base64 @@@"))
        XCTAssertNil(VUDecoder.decode(base64: Data([1, 2, 3]).base64EncodedString())) // < 8 bytes
    }
}
