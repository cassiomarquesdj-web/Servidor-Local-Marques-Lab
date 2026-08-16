import XCTest
@testable import UI16Controller

final class ConnectionTests: XCTestCase {

    func testPlainHostUsesFallbackPort() {
        let (h, p) = UI16Connection.splitHostPort("10.10.2.1", fallback: 80)
        XCTAssertEqual(h, "10.10.2.1")
        XCTAssertEqual(p, 80)
    }

    func testEmbeddedPortWins() {
        let (h, p) = UI16Connection.splitHostPort("127.0.0.1:8080", fallback: 80)
        XCTAssertEqual(h, "127.0.0.1")
        XCTAssertEqual(p, 8080)
    }

    func testTrimsWhitespace() {
        let (h, p) = UI16Connection.splitHostPort("  10.10.2.1  ", fallback: 80)
        XCTAssertEqual(h, "10.10.2.1")
        XCTAssertEqual(p, 80)
    }

    func testInvalidPortFallsBack() {
        let (h, p) = UI16Connection.splitHostPort("10.10.2.1:abc", fallback: 80)
        XCTAssertEqual(h, "10.10.2.1:abc")
        XCTAssertEqual(p, 80)
    }

    func testIPv6LiteralIsNotSplit() {
        let (h, p) = UI16Connection.splitHostPort("[fe80::1]", fallback: 80)
        XCTAssertEqual(h, "[fe80::1]")
        XCTAssertEqual(p, 80)
    }
}
