import XCTest
@testable import MarquesDownloadCore

final class YouTubeExtractorTests: XCTestCase {
    func url(_ s: String) -> URL { URL(string: s)! }

    func testRecognisesEveryURLShape() {
        let cases = [
            "https://www.youtube.com/watch?v=MHU_q4PyRew": "MHU_q4PyRew",
            "https://youtu.be/MHU_q4PyRew": "MHU_q4PyRew",
            "https://www.youtube.com/shorts/abc123XYZ": "abc123XYZ",
            "https://www.youtube.com/embed/abc123XYZ": "abc123XYZ",
            "https://m.youtube.com/watch?v=abc123XYZ&t=30s": "abc123XYZ",
        ]
        for (link, expected) in cases {
            XCTAssertEqual(YouTubeExtractor.videoID(from: url(link)), expected, link)
        }
    }

    func testClaimsOnlyYouTubeHosts() {
        let extractor = YouTubeExtractor()
        XCTAssertTrue(extractor.canHandle(url("https://youtube.com/watch?v=a")))
        XCTAssertTrue(extractor.canHandle(url("https://youtu.be/a")))
        XCTAssertFalse(extractor.canHandle(url("https://vimeo.com/123")))
    }

    func testParsesStreamsAndSplitsCodecs() throws {
        let json: [String: Any] = [
            "videoDetails": ["title": "Compacto", "author": "Canal", "lengthSeconds": "911"],
            "streamingData": [
                "formats": [[
                    "url": "https://cdn/muxed", "mimeType": "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"",
                    "height": 360, "bitrate": 620_000,
                ]],
                "adaptiveFormats": [
                    ["url": "https://cdn/v1080", "mimeType": "video/mp4; codecs=\"avc1.640028\"", "height": 1080, "bitrate": 4_000_000],
                    ["url": "https://cdn/a", "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 128_000],
                    ["signatureCipher": "s=abc", "mimeType": "video/mp4; codecs=\"avc1\"", "height": 2160],
                ],
            ],
        ]
        let media = try YouTubeExtractor.parse(json, videoID: "x", webpage: url("https://youtu.be/x"))

        XCTAssertEqual(media.title, "Compacto")
        XCTAssertEqual(media.uploader, "Canal")
        XCTAssertEqual(media.duration, 911)
        XCTAssertEqual(media.streams.count, 3, "o formato cifrado é descartado")
        XCTAssertEqual(media.streams[0].content, .muxed)
        XCTAssertEqual(media.streams[0].audioCodec, "mp4a.40.2")
        XCTAssertEqual(media.streams[1].content, .videoOnly)
        XCTAssertEqual(media.streams[1].bitrate, 4000)
        XCTAssertEqual(media.streams[2].content, .audioOnly)
    }

    func testCipheredOnlyResponseIsRejected() throws {
        let json: [String: Any] = [
            "videoDetails": ["title": "x"],
            "streamingData": ["adaptiveFormats": [["signatureCipher": "s=1", "mimeType": "video/mp4"]]],
        ]
        let media = try YouTubeExtractor.parse(json, videoID: "x", webpage: url("https://youtu.be/x"))
        XCTAssertTrue(media.streams.isEmpty)
    }

    func testPlayabilityFailureBecomesAReadableError() {
        let json: [String: Any] = [
            "playabilityStatus": ["status": "LOGIN_REQUIRED", "reason": "Sign in to confirm your age"]
        ]
        XCTAssertThrowsError(try YouTubeExtractor.parse(json, videoID: "x", webpage: url("https://youtu.be/x"))) { error in
            XCTAssertTrue((error as! ExtractorError).reason.contains("Sign in to confirm"))
        }
    }

    func testRequestCarriesTheClientIdentity() async throws {
        let fetcher = FakeFetcher(json: """
        {"videoDetails":{"title":"T"},"streamingData":{"formats":[
          {"url":"https://cdn/a","mimeType":"video/mp4; codecs=\\"avc1, mp4a\\"","height":720}]}}
        """)
        _ = try await YouTubeExtractor().extract(url("https://youtu.be/abc"), using: fetcher)

        let request = try XCTUnwrap(fetcher.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-YouTube-Client-Name"))
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["videoId"] as? String, "abc")
    }

    func testAllClientsFailingProducesActionableAdvice() async {
        let fetcher = FakeFetcher(json: "{}", status: 500)
        do {
            _ = try await YouTubeExtractor().extract(url("https://youtu.be/abc"), using: fetcher)
            XCTFail("deveria falhar")
        } catch {
            XCTAssertTrue((error as! ExtractorError).reason.contains("atualize o aplicativo"))
        }
    }
}
