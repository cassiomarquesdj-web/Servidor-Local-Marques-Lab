import XCTest
@testable import UI16Controller

final class MessageTests: XCTestCase {

    func testParsesSetD() {
        let m = UI16Message.parse("SETD^i.0.mix^0.75")
        XCTAssertEqual(m?.kind, .setd)
        XCTAssertEqual(m?.path, "i.0.mix")
        XCTAssertEqual(m?.value, "0.75")
        XCTAssertEqual(m?.number, 0.75)
    }

    func testParsesSetS() {
        let m = UI16Message.parse("SETS^i.0.name^Kick In")
        XCTAssertEqual(m?.kind, .sets)
        XCTAssertEqual(m?.path, "i.0.name")
        XCTAssertEqual(m?.value, "Kick In")
    }

    func testParsesBoolValues() {
        XCTAssertEqual(UI16Message.parse("SETD^i.0.mute^1")?.bool, true)
        XCTAssertEqual(UI16Message.parse("SETD^i.0.mute^0")?.bool, false)
    }

    func testValueCanContainSeparator() {
        let m = UI16Message.parse("SETS^show.name^Gig^2026")
        XCTAssertEqual(m?.path, "show.name")
        XCTAssertEqual(m?.value, "Gig^2026")
    }

    func testIgnoresNonState() {
        XCTAssertNil(UI16Message.parse("ALIVE"))
        XCTAssertNil(UI16Message.parse("VU2^AAAA"))
        XCTAssertNil(UI16Message.parse("SETD^^1"))   // empty path
    }

    func testEncodesCommands() {
        XCTAssertEqual(UI16Message.setd("i.0.mix", 0.5), "SETD^i.0.mix^0.5")
        XCTAssertEqual(UI16Message.setd("i.0.mute", true), "SETD^i.0.mute^1")
        XCTAssertEqual(UI16Message.setd("i.0.mute", false), "SETD^i.0.mute^0")
        XCTAssertEqual(UI16Message.setd("m.mix", 1.0), "SETD^m.mix^1")
        XCTAssertEqual(UI16Message.sets("i.0.name", "Vox"), "SETS^i.0.name^Vox")
    }

    func testNumberFormattingHasNoLocaleOrTrailingZeros() {
        XCTAssertEqual(UI16Message.formatNumber(0.5), "0.5")
        XCTAssertEqual(UI16Message.formatNumber(1.0), "1")
        XCTAssertEqual(UI16Message.formatNumber(0.0), "0")
        XCTAssertEqual(UI16Message.formatNumber(0.250), "0.25")
    }

    func testFraming() {
        XCTAssertEqual(UI16Message.frame("ALIVE"), "3:::ALIVE")
        XCTAssertEqual(UI16Message.unframe("3:::SETD^a^1"), ["SETD^a^1"])
        XCTAssertEqual(UI16Message.unframe("3:::SETD^a^1\nSETD^b^2"), ["SETD^a^1", "SETD^b^2"])
        XCTAssertEqual(UI16Message.unframe("SETD^a^1"), ["SETD^a^1"])   // no prefix
    }

    func testVUDetection() {
        XCTAssertTrue(UI16Message.isVU("VU2^AAAA"))
        XCTAssertEqual(UI16Message.vuBody("VU2^AAAA"), "AAAA")
        XCTAssertNil(UI16Message.vuBody("SETD^a^1"))
    }
}
