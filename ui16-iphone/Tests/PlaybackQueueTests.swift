import XCTest
@testable import ParedaoCore

private func makeTracks(_ n: Int) -> [Track] {
    (1...n).map { Track(fileName: "t\($0)", title: "Track \($0)", artist: "A\($0)") }
}

final class PlaybackQueueTests: XCTestCase {

    // MARK: Basics

    func testEmptyQueueStops() {
        var q = PlaybackQueue()
        XCTAssertNil(q.current)
        XCTAssertEqual(q.next(auto: true), .stop)
        XCTAssertEqual(q.previous(), .stop)
    }

    func testLoadStartsAtRequestedTrack() {
        var q = PlaybackQueue()
        q.load(makeTracks(5), startAt: 2)
        XCTAssertEqual(q.current?.title, "Track 3")
    }

    func testLoadClampsOutOfRangeStart() {
        var q = PlaybackQueue()
        q.load(makeTracks(3), startAt: 99)
        XCTAssertEqual(q.current?.title, "Track 3")
    }

    // MARK: Repeat off

    func testRepeatOffStopsAtEnd() {
        var q = PlaybackQueue(tracks: makeTracks(3))
        q.repeatMode = .off
        XCTAssertEqual(q.next(auto: true), .play(1))
        XCTAssertEqual(q.next(auto: true), .play(2))
        XCTAssertEqual(q.next(auto: true), .stop)
    }

    // MARK: Repeat all

    func testRepeatAllWrapsAround() {
        var q = PlaybackQueue(tracks: makeTracks(3))
        q.repeatMode = .all
        _ = q.next(auto: true)
        _ = q.next(auto: true)
        XCTAssertEqual(q.next(auto: true), .play(0), "deve voltar ao início")
    }

    func testRepeatAllPreviousWrapsBackwards() {
        var q = PlaybackQueue(tracks: makeTracks(3))
        q.repeatMode = .all
        XCTAssertEqual(q.previous(), .play(2))
    }

    // MARK: Repeat one

    func testRepeatOneRestartsOnNaturalEnd() {
        var q = PlaybackQueue(tracks: makeTracks(3))
        q.repeatMode = .one
        XCTAssertEqual(q.next(auto: true), .restart)
        XCTAssertEqual(q.current?.title, "Track 1", "não deve avançar sozinho")
    }

    func testRepeatOneStillSkipsWhenOperatorPressesNext() {
        // The next button must always skip — otherwise it looks broken to the operator.
        var q = PlaybackQueue(tracks: makeTracks(3))
        q.repeatMode = .one
        XCTAssertEqual(q.next(auto: false), .play(1))
        XCTAssertEqual(q.current?.title, "Track 2")
    }

    func testRepeatOneManualNextOnLastTrackWraps() {
        var q = PlaybackQueue(tracks: makeTracks(2), startAt: 1)
        q.repeatMode = .one
        XCTAssertEqual(q.next(auto: false), .play(0))
    }

    // MARK: Previous

    func testPreviousAtStartRestarts() {
        var q = PlaybackQueue(tracks: makeTracks(3))
        XCTAssertEqual(q.previous(), .restart)
    }

    func testPreviousStepsBack() {
        var q = PlaybackQueue(tracks: makeTracks(3), startAt: 2)
        XCTAssertEqual(q.previous(), .play(1))
    }

    // MARK: Shuffle

    func testShuffleKeepsCurrentTrackPlaying() {
        // Toggling shuffle mid-song must not change what the room is hearing.
        var q = PlaybackQueue(tracks: makeTracks(10), startAt: 4)
        q.shuffleSeed = 42
        let before = q.current
        q.setShuffled(true)
        XCTAssertEqual(q.current, before)
        XCTAssertTrue(q.isShuffled)
    }

    func testUnshuffleRestoresOriginalOrderAndKeepsCurrent() {
        var q = PlaybackQueue(tracks: makeTracks(10), startAt: 3)
        q.shuffleSeed = 7
        let before = q.current
        q.setShuffled(true)
        q.setShuffled(false)
        XCTAssertEqual(q.current, before)
        XCTAssertEqual(q.order, Array(0..<10), "ordem original deve voltar")
    }

    func testShuffleCoversEveryTrackExactlyOnce() {
        var q = PlaybackQueue(tracks: makeTracks(8))
        q.shuffleSeed = 99
        q.setShuffled(true)
        XCTAssertEqual(Set(q.order), Set(0..<8))
        XCTAssertEqual(q.order.count, 8, "nenhuma música repetida ou perdida")
    }

    func testShuffleIsDeterministicWithSeed() {
        var a = PlaybackQueue(tracks: makeTracks(10)); a.shuffleSeed = 5
        var b = PlaybackQueue(tracks: makeTracks(10)); b.shuffleSeed = 5
        a.setShuffled(true); b.setShuffled(true)
        XCTAssertEqual(a.order, b.order)
    }

    func testShuffleWithRepeatAllReshufflesNextLap() {
        var q = PlaybackQueue(tracks: makeTracks(5))
        q.shuffleSeed = 3
        q.setShuffled(true)
        q.repeatMode = .all
        let firstLap = q.order
        for _ in 0..<5 { _ = q.next(auto: true) }
        XCTAssertEqual(Set(q.order), Set(0..<5), "nova volta ainda cobre tudo")
        XCTAssertEqual(q.order.count, firstLap.count)
    }

    // MARK: Editing

    func testPlayNextInsertsRightAfterCurrent() {
        var q = PlaybackQueue(tracks: makeTracks(3))
        let extra = Track(fileName: "x", title: "Furada")
        q.playNext(extra)
        XCTAssertEqual(q.next(auto: false), .play(3))
        XCTAssertEqual(q.current?.title, "Furada")
    }

    func testAppendAddsToEnd() {
        var q = PlaybackQueue(tracks: makeTracks(2))
        q.append(Track(fileName: "z", title: "Última"))
        XCTAssertEqual(q.count, 3)
        _ = q.next(auto: false)
        _ = q.next(auto: false)
        XCTAssertEqual(q.current?.title, "Última")
    }

    func testRemoveKeepsQueueConsistent() {
        var q = PlaybackQueue(tracks: makeTracks(4), startAt: 2)
        q.remove(atOrderPosition: 0)
        XCTAssertEqual(q.count, 3)
        XCTAssertEqual(q.current?.title, "Track 3", "a música tocando não deve mudar")
        XCTAssertEqual(Set(q.order), Set(0..<3), "índices remapeados corretamente")
    }

    func testRemoveCurrentDoesNotCrash() {
        var q = PlaybackQueue(tracks: makeTracks(3), startAt: 1)
        q.remove(atOrderPosition: 1)
        XCTAssertEqual(q.count, 2)
        XCTAssertNotNil(q.current)
    }

    func testJumpToTrackIndex() {
        var q = PlaybackQueue(tracks: makeTracks(5))
        q.jump(toTrackIndex: 3)
        XCTAssertEqual(q.current?.title, "Track 4")
    }

    func testUpcomingListsWhatComesNext() {
        let q = PlaybackQueue(tracks: makeTracks(5))
        XCTAssertEqual(q.upcoming(limit: 2).map(\.title), ["Track 2", "Track 3"])
    }

    func testRepeatModeCycles() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
    }
}
