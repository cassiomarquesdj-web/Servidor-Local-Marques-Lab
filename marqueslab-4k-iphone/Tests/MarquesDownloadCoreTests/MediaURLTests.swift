import XCTest
@testable import MarquesDownloadCore

final class MediaURLTests: XCTestCase {
    func testNormalizeTrims() throws {
        let url = try MediaURL.normalize("  https://example.com/video  ")
        XCTAssertEqual(url.absoluteString, "https://example.com/video")
    }

    func testRejectsNonHTTPSchemes() {
        for value in ["ftp://example.com/a", "file:///etc/passwd", "javascript:alert(1)"] {
            XCTAssertThrowsError(try MediaURL.normalize(value), value)
        }
    }

    func testRejectsEmptyInput() {
        XCTAssertThrowsError(try MediaURL.normalize("   ")) { error in
            XCTAssertEqual(error as? MediaURL.Failure, .empty)
        }
    }

    func testSplitKeepsOrderAndDropsDuplicates() throws {
        let urls = try MediaURL.split("""
        https://example.com/a
        https://example.com/a

        https://example.com/b
        """)
        XCTAssertEqual(urls.map(\.absoluteString), ["https://example.com/a", "https://example.com/b"])
    }

    func testSplitRejectsGarbageAmongValidLines() {
        XCTAssertThrowsError(try MediaURL.split("https://example.com/a\nnão-é-url"))
    }

    func testAcceptsInstagramAndYouTubeURLs() throws {
        let urls = try MediaURL.split("""
        https://www.instagram.com/reel/ABC123/
        https://www.youtube.com/watch?v=dQw4w9WgXcQ
        https://youtu.be/dQw4w9WgXcQ
        """)
        XCTAssertEqual(urls.count, 3)
    }

    func testSafeFilenameStripsPathSeparators() {
        XCTAssertEqual(MediaURL.safeFilename("A/B:C*?D"), "A_B_C__D")
    }

    func testSafeFilenameNeverReturnsEmpty() {
        XCTAssertEqual(MediaURL.safeFilename("   ...   "), "Marques Lab Mídia")
    }

    func testSafeFilenameIsBounded() {
        XCTAssertLessThanOrEqual(MediaURL.safeFilename(String(repeating: "x", count: 500)).count, 120)
    }
}
