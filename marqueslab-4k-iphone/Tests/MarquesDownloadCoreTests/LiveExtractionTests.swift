import XCTest
@testable import MarquesDownloadCore

/// Hits the real services. Fixtures prove the parsers; only this proves the
/// endpoints still exist and still answer the way the parsers expect.
/// Off by default so CI stays offline and deterministic:
///
///     MARQUESLAB_LIVE=1 swift test --filter LiveExtractionTests
final class LiveExtractionTests: XCTestCase {
    struct LiveFetcher: HTTPFetching {
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, response as! HTTPURLResponse)
        }
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MARQUESLAB_LIVE"] == "1",
            "teste ao vivo: defina MARQUESLAB_LIVE=1"
        )
    }

    func testYouTubeStillResolves() async throws {
        let url = URL(string: "https://www.youtube.com/watch?v=MHU_q4PyRew")!
        let media = try await YouTubeExtractor().extract(url, using: LiveFetcher())

        XCTAssertFalse(media.title.isEmpty)
        XCTAssertFalse(media.streams.isEmpty, "nenhum stream utilizável")
        print("YOUTUBE: \(media.title) — \(media.streams.count) streams, até \(media.maximumHeight ?? 0)p")

        let plan = try StreamSelection.plan(for: media, choice: .video(.p1080))
        print("PLANO: vídeo=\(plan.video?.videoCodec ?? "-")@\(plan.video?.height ?? 0)p "
              + "áudio=\(plan.audio?.audioCodec ?? "-") muxar=\(plan.needsMuxing)")
        XCTAssertNotNil(plan.video)
        XCTAssertTrue(plan.video!.isEditableVideo, "o perfil editável precisa achar H.264")
    }

    func testInstagramPublicPostStillResolves() async throws {
        let url = URL(string: "https://www.instagram.com/p/DcbaIFcyXd9/")!
        let media = try await InstagramExtractor().extract(url, using: LiveFetcher())

        XCTAssertFalse(media.streams.isEmpty)
        print("INSTAGRAM: \(media.title) — \(media.streams.count) streams, "
              + "áudio=\(media.hasAudio), até \(media.maximumHeight ?? 0)p")
        XCTAssertTrue(media.streams[0].isEditableVideo)
    }
}
