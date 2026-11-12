import XCTest
@testable import MarquesDownloadCore

final class StreamSelectionTests: XCTestCase {
    func url(_ s: String) -> URL { URL(string: s)! }

    /// Mirrors what YouTube actually offers: AV1/VP9 on top, H.264 lower down.
    func youTubeLike() -> ExtractedMedia {
        ExtractedMedia(
            title: "Compacto",
            webpage: url("https://youtube.com/watch?v=x"),
            streams: [
                MediaStream(url: url("https://cdn/av1-2160"), content: .videoOnly, height: 2160, bitrate: 9000, videoCodec: "av01.0.08M.08"),
                MediaStream(url: url("https://cdn/vp9-1080"), content: .videoOnly, height: 1080, bitrate: 2000, videoCodec: "vp9"),
                MediaStream(url: url("https://cdn/avc-1080"), content: .videoOnly, height: 1080, bitrate: 4000, videoCodec: "avc1.640028"),
                MediaStream(url: url("https://cdn/avc-720"), content: .videoOnly, height: 720, bitrate: 2000, videoCodec: "avc1.64001f"),
                MediaStream(url: url("https://cdn/opus"), content: .audioOnly, bitrate: 130, audioCodec: "opus"),
                MediaStream(url: url("https://cdn/aac"), content: .audioOnly, bitrate: 128, audioCodec: "mp4a.40.2"),
            ]
        )
    }

    func testEditableProfilePrefersH264AndAAC() throws {
        let plan = try StreamSelection.plan(for: youTubeLike(), choice: .video(.p1080))
        XCTAssertEqual(plan.video?.videoCodec, "avc1.640028")
        XCTAssertEqual(plan.audio?.audioCodec, "mp4a.40.2")
        XCTAssertTrue(plan.needsMuxing)
    }

    func testRawProfileTakesTheHighestQuality() throws {
        let plan = try StreamSelection.plan(for: youTubeLike(), choice: .video(.best, editable: false))
        XCTAssertEqual(plan.video?.height, 2160)
        XCTAssertEqual(plan.video?.videoCodec, "av01.0.08M.08")
    }

    func testQualityCapIsRespected() throws {
        let plan = try StreamSelection.plan(for: youTubeLike(), choice: .video(.p720))
        XCTAssertEqual(plan.video?.height, 720)
    }

    func testEditable4KTakesTheBestH264AndSaysSo() throws {
        // YouTube serves no H.264 above 1080p. Keeping the editable promise means
        // taking the 1080p H.264 instead of re-encoding 4K AV1 — the same choice
        // the desktop app makes — but the user has to be told.
        let plan = try StreamSelection.plan(for: youTubeLike(), choice: .video(.p2160))
        XCTAssertEqual(plan.video?.height, 1080)
        XCTAssertTrue(plan.video!.isEditableVideo)
        XCTAssertEqual(plan.downgradedTo, 1080)
        XCTAssertTrue(plan.notice!.contains("não oferece H.264"))
    }

    func testRaw4KHasNoDowngradeNotice() throws {
        let plan = try StreamSelection.plan(for: youTubeLike(), choice: .video(.p2160, editable: false))
        XCTAssertEqual(plan.video?.height, 2160)
        XCTAssertNil(plan.downgradedTo)
        XCTAssertNil(plan.notice)
    }

    func testNoNoticeWhenH264IsAlreadyTheBest() throws {
        let plan = try StreamSelection.plan(for: youTubeLike(), choice: .video(.p720))
        XCTAssertEqual(plan.video?.height, 720)
        XCTAssertNil(plan.downgradedTo, "nada foi sacrificado em 720p")
    }

    func testMuxedStreamIsPreferredOverCombining() throws {
        let media = ExtractedMedia(
            title: "Reel", webpage: url("https://instagram.com/reel/x"),
            streams: [
                MediaStream(url: url("https://cdn/progressive"), content: .muxed, height: 1080, bitrate: 3000, videoCodec: "avc1.64001f", audioCodec: "mp4a.40.2"),
                MediaStream(url: url("https://cdn/dash-v"), content: .videoOnly, height: 1080, bitrate: 3100, videoCodec: "avc1.64001f"),
            ]
        )
        let plan = try StreamSelection.plan(for: media, choice: .video(.p1080))
        XCTAssertFalse(plan.needsMuxing)
        XCTAssertEqual(plan.video?.content, .muxed)
    }

    func testAudioProfilePicksTheBestAudioOnlyStream() throws {
        let plan = try StreamSelection.plan(for: youTubeLike(), choice: .audio())
        XCTAssertNil(plan.video)
        XCTAssertEqual(plan.audio?.audioCodec, "mp4a.40.2")
    }

    func testAudioFallsBackToAMuxedStream() throws {
        let media = ExtractedMedia(
            title: "Só progressivo", webpage: url("https://example.com/a"),
            streams: [MediaStream(url: url("https://cdn/p"), content: .muxed, videoCodec: "avc1", audioCodec: "mp4a")]
        )
        let plan = try StreamSelection.plan(for: media, choice: .audio())
        XCTAssertEqual(plan.audio?.content, .muxed)
    }

    func testEmptyExtractionFails() {
        let media = ExtractedMedia(title: "Nada", webpage: url("https://example.com"), streams: [])
        XCTAssertThrowsError(try StreamSelection.plan(for: media, choice: .video())) { error in
            XCTAssertEqual(error as? StreamSelection.Failure, .noStreams)
        }
    }

    func testSilentSourceIsDetectable() {
        let media = ExtractedMedia(
            title: "Mudo", webpage: url("https://instagram.com/reel/x"),
            streams: [MediaStream(url: url("https://cdn/v"), content: .videoOnly, height: 720, videoCodec: "avc1")]
        )
        XCTAssertFalse(media.hasAudio)
    }
}
