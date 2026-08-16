import XCTest
@testable import UI16Controller

final class UI16ProtocolTests: XCTestCase {
    func testParsesSetD() {
        let message = UI16Protocol.parse("SETD^m.0.mix^0.75")
        XCTAssertEqual(message?.key, "m.0.mix")
        XCTAssertEqual(message?.value, "0.75")
    }

    func testBuildsNumericCommand() {
        XCTAssertEqual(UI16Protocol.set("i.0.mix", 0.5), "SETD^i.0.mix^0.5")
    }

    func testBuildsBooleanCommand() {
        XCTAssertEqual(UI16Protocol.set("i.0.mute", true), "SETD^i.0.mute^1")
        XCTAssertEqual(UI16Protocol.set("i.0.mute", false), "SETD^i.0.mute^0")
    }

    func testIgnoresNonSetD() {
        XCTAssertNil(UI16Protocol.parse("ALIVE"))
    }
}
