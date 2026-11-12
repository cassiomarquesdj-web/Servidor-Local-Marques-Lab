import XCTest
@testable import MarquesDownloadCore

final class FormattingTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(Formatting.bytes(nil), "—")
        XCTAssertEqual(Formatting.bytes(0), "—")
        XCTAssertEqual(Formatting.bytes(512), "512 B")
        XCTAssertTrue(Formatting.bytes(1536).hasPrefix("1,5") || Formatting.bytes(1536).hasPrefix("1.5"))
        XCTAssertTrue(Formatting.bytes(5 * 1024 * 1024).contains("MiB"))
    }

    func testDuration() {
        XCTAssertEqual(Formatting.duration(nil), "—")
        XCTAssertEqual(Formatting.duration(65), "1:05")
        XCTAssertEqual(Formatting.duration(3725), "1:02:05")
    }

    func testSpeed() {
        XCTAssertEqual(Formatting.speed(nil), "—")
        XCTAssertTrue(Formatting.speed(2 * 1024 * 1024).contains("MiB/s"))
    }
}
