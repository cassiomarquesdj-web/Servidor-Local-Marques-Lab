import XCTest
@testable import MarquesDownloadCore

private struct Raw: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

final class FriendlyErrorTests: XCTestCase {
    func testExplainsA403() {
        let message = FriendlyError.describe(Raw(text: "HTTP 403 Forbidden"))
        XCTAssertTrue(message.contains("mudou a forma de servir"))
        XCTAssertTrue(message.contains("Detalhe técnico:"))
    }

    func testExplainsCommonFailures() {
        let cases = [
            ("Private video", "privada"),
            ("login required", "sessão autenticada"),
            ("rate limit reached", "limite de requisições"),
            ("The request timed out", "parou de responder"),
        ]
        for (raw, expected) in cases {
            XCTAssertTrue(FriendlyError.describe(Raw(text: raw)).contains(expected), raw)
        }
    }

    func testUnknownMessagesPassThrough() {
        XCTAssertEqual(FriendlyError.describe(Raw(text: "algo novo")), "algo novo")
    }
}
