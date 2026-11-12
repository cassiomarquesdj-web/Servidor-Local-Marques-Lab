import XCTest
@testable import MarquesDownloadCore

final class InstagramExtractorTests: XCTestCase {
    func url(_ s: String) -> URL { URL(string: s)! }

    func testRecognisesPostReelAndTV() {
        let extractor = InstagramExtractor()
        for link in [
            "https://www.instagram.com/p/DcbaIFcyXd9/",
            "https://instagram.com/reel/Chunk8-jurw/",
            "https://www.instagram.com/reels/ABC123/",
            "https://www.instagram.com/tv/BkfuX9UB-eK/",
        ] {
            XCTAssertTrue(extractor.canHandle(url(link)), link)
        }
        XCTAssertFalse(extractor.canHandle(url("https://www.instagram.com/marques_lab/")),
                       "um perfil não é uma publicação")
        XCTAssertFalse(extractor.canHandle(url("https://youtube.com/watch?v=a")))
    }

    func testShortcodeSurvivesQueryAndTrailingSlash() {
        XCTAssertEqual(
            InstagramExtractor.shortcode(from: url("https://www.instagram.com/reel/Chunk8-jurw/?igsh=abc")),
            "Chunk8-jurw"
        )
    }

    /// The shape the web API returns: progressive MP4s, already H.264 + AAC.
    func testParsesTheItemsPayload() throws {
        let json = """
        {"items":[{
          "caption":{"text":"SET GUANABARA 4K\\nsegunda linha"},
          "user":{"username":"marques_lab"},
          "video_duration":23.45,
          "has_audio":true,
          "video_versions":[
            {"url":"https://cdn/720.mp4","width":720,"height":1280,"bandwidth":1966000},
            {"url":"https://cdn/480.mp4","width":480,"height":854,"bandwidth":900000}
          ]
        }]}
        """
        let media = try InstagramExtractor.parse(Data(json.utf8), webpage: url("https://instagram.com/p/x/"))

        XCTAssertEqual(media.title, "SET GUANABARA 4K")
        XCTAssertEqual(media.uploader, "marques_lab")
        XCTAssertEqual(media.duration, 23.45)
        XCTAssertEqual(media.streams.count, 2)
        XCTAssertTrue(media.hasAudio)
        XCTAssertTrue(media.streams.allSatisfy { $0.content == .muxed })
        XCTAssertTrue(media.streams[0].isEditableVideo, "Instagram entrega H.264")
        XCTAssertTrue(media.streams[0].isEditableAudio)
    }

    func testSilentClipIsReportedWithoutAudio() throws {
        let json = """
        {"items":[{"has_audio":false,"user":{"username":"instagram"},
          "video_versions":[{"url":"https://cdn/a.mp4","height":1280}]}]}
        """
        let media = try InstagramExtractor.parse(Data(json.utf8), webpage: url("https://instagram.com/p/x/"))
        XCTAssertNil(media.streams[0].audioCodec, "a mídia é muda na origem")
    }

    func testParsesTheGraphQLShape() throws {
        let json = """
        {"graphql":{"shortcode_media":{
          "video_url":"https://cdn/video.mp4",
          "dimensions":{"height":1080,"width":1920},
          "owner":{"username":"canal"},
          "edge_media_to_caption":{"edges":[{"node":{"text":"Legenda"}}]}
        }}}
        """
        let media = try InstagramExtractor.parse(Data(json.utf8), webpage: url("https://instagram.com/p/x/"))
        XCTAssertEqual(media.title, "Legenda")
        XCTAssertEqual(media.uploader, "canal")
        XCTAssertEqual(media.streams.first?.height, 1080)
    }

    /// Instagram often answers the post URL with HTML that embeds the JSON.
    func testFindsTheJSONEmbeddedInHTML() throws {
        let html = """
        <!doctype html><html><body><script>window.__d=1;</script>
        <script type="application/json">{"require":[["x",{"items":[
          {"user":{"username":"ml"},"has_audio":true,
           "video_versions":[{"url":"https://cdn/from-html.mp4","height":1280}]}
        ]}]]}</script></body></html>
        """
        let media = try InstagramExtractor.parse(Data(html.utf8), webpage: url("https://instagram.com/p/x/"))
        XCTAssertEqual(media.streams.first?.url.absoluteString, "https://cdn/from-html.mp4")
    }

    func testPhotoOnlyPostYieldsNoStreams() {
        let json = """
        {"items":[{"user":{"username":"ml"},"image_versions2":{"candidates":[{"url":"https://cdn/i.jpg"}]}}]}
        """
        XCTAssertThrowsError(try InstagramExtractor.parse(Data(json.utf8), webpage: url("https://instagram.com/p/x/")))
    }

    func testPageWithoutMediaExplainsTheSessionRequirement() async {
        // What Instagram actually serves today: 200 OK with no media address.
        let fetcher = FakeFetcher(json: "{}", status: 200)
        do {
            _ = try await InstagramExtractor().extract(url("https://instagram.com/p/abc/"), using: fetcher)
            XCTFail("deveria falhar")
        } catch {
            let reason = (error as! ExtractorError).reason
            XCTAssertTrue(reason.contains("sessão autenticada"), reason)
            XCTAssertFalse(reason.contains("HTTP"), "não inventar um status que não houve")
        }
    }

    func testStatusFromAnEarlierAttemptIsNotReported() async {
        // The first endpoint 404s and the second serves a page with no media:
        // reporting the stale 404 points the diagnosis at the wrong thing.
        let fetcher = FakeFetcher(replies: [
            .init(status: 404, body: Data("<html>não</html>".utf8), headers: [:]),
            .init(status: 200, body: Data("<html>sem mídia</html>".utf8), headers: [:]),
        ])
        do {
            _ = try await InstagramExtractor().extract(url("https://instagram.com/p/abc/"), using: fetcher)
            XCTFail("deveria falhar")
        } catch {
            XCTAssertFalse((error as! ExtractorError).reason.contains("404"))
        }
    }

    func testRemovedPostReportsTheStatus() async {
        let fetcher = FakeFetcher(json: "não", status: 404)
        do {
            _ = try await InstagramExtractor().extract(url("https://instagram.com/p/abc/"), using: fetcher)
            XCTFail("deveria falhar")
        } catch {
            XCTAssertTrue((error as! ExtractorError).reason.contains("HTTP 404"))
        }
    }

    func testRequestCarriesTheWebAppID() async {
        let fetcher = FakeFetcher(json: "{}")
        _ = try? await InstagramExtractor().extract(url("https://instagram.com/p/abc/"), using: fetcher)
        XCTAssertEqual(fetcher.requests.first?.value(forHTTPHeaderField: "X-IG-App-ID"),
                       InstagramExtractor.appID)
    }
}
