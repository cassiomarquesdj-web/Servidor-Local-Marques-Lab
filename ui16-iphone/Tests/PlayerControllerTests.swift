import XCTest
@testable import ParedaoCore
@testable import UI16Controller

/// Stand-in for the real AVAudioEngine output, so playback logic is testable without an
/// audio device. Records what the engine was asked to do.
@MainActor
final class FakeAudioOutput: AudioOutput {
    nonisolated(unsafe) var snapshot = PlayerSnapshot()
    nonisolated(unsafe) var onTrackEnded: (@MainActor () -> Void)?
    nonisolated(unsafe) var onTick: (@MainActor (PlayerSnapshot) -> Void)?

    private(set) var loaded: [Track] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var seeks: [TimeInterval] = []
    private(set) var appliedEQ: EQSettings?
    private(set) var polarityInverted = false

    /// File names that should fail to load, to exercise the corrupt-file path.
    var failingFiles: Set<String> = []

    func load(track: Track) throws {
        if failingFiles.contains(track.fileName) {
            throw AudioEngineError.fileUnreadable(track.fileName)
        }
        loaded.append(track)
        snapshot.duration = track.duration
        snapshot.currentTime = 0
        snapshot.status = .paused
    }
    func play() { playCount += 1; snapshot.status = .playing }
    func pause() { pauseCount += 1; snapshot.status = .paused }
    func stop() { stopCount += 1; snapshot.status = .stopped }
    func seek(to time: TimeInterval) { seeks.append(time); snapshot.currentTime = time }
    func setVolume(_ volume: Double) { snapshot.volume = volume }
    func applyEQ(_ settings: EQSettings) { appliedEQ = settings }
    func setPolarityInverted(_ inverted: Bool) { polarityInverted = inverted }

    /// Simulate a track running to its natural end.
    func finishTrack() { onTrackEnded?() }
}

private func makeTracks(_ n: Int) -> [Track] {
    (1...n).map { Track(fileName: "t\($0)", title: "Track \($0)", duration: 100) }
}

@MainActor
final class PlayerControllerTests: XCTestCase {

    private func makeController() -> (PlayerController, FakeAudioOutput) {
        let out = FakeAudioOutput()
        return (PlayerController(output: out), out)
    }

    func testPlayLoadsAndStarts() {
        let (player, out) = makeController()
        player.play(tracks: makeTracks(3), startAt: 0)
        XCTAssertEqual(out.loaded.map(\.title), ["Track 1"])
        XCTAssertEqual(out.playCount, 1)
        XCTAssertEqual(player.current?.title, "Track 1")
    }

    func testTogglePlayPause() {
        let (player, out) = makeController()
        player.play(tracks: makeTracks(2), startAt: 0)
        player.togglePlayPause()
        XCTAssertEqual(out.pauseCount, 1)
        player.togglePlayPause()
        XCTAssertEqual(out.playCount, 2)
    }

    func testNaturalEndAdvancesToNextTrack() {
        let (player, out) = makeController()
        player.play(tracks: makeTracks(3), startAt: 0)
        out.finishTrack()
        XCTAssertEqual(player.current?.title, "Track 2")
        XCTAssertEqual(out.loaded.map(\.title), ["Track 1", "Track 2"])
    }

    func testContinuousPlaybackRunsThroughTheWholeList() {
        let (player, out) = makeController()
        player.play(tracks: makeTracks(3), startAt: 0)
        out.finishTrack()
        out.finishTrack()
        XCTAssertEqual(player.current?.title, "Track 3")
        out.finishTrack()   // end of list, repeat off
        XCTAssertEqual(out.stopCount, 1, "deve parar no fim sem repeat")
    }

    func testRepeatAllKeepsGoing() {
        let (player, out) = makeController()
        player.play(tracks: makeTracks(2), startAt: 0)
        player.setRepeat(.all)
        out.finishTrack()
        out.finishTrack()
        XCTAssertEqual(player.current?.title, "Track 1", "volta ao começo")
        XCTAssertEqual(out.stopCount, 0)
    }

    func testRepeatOneRestartsWithoutReloading() {
        let (player, out) = makeController()
        player.play(tracks: makeTracks(3), startAt: 0)
        player.setRepeat(.one)
        out.finishTrack()
        XCTAssertEqual(player.current?.title, "Track 1")
        XCTAssertEqual(out.loaded.count, 1, "não recarrega o arquivo")
        XCTAssertEqual(out.seeks.last, 0, "volta ao início")
    }

    func testPreviousRestartsWhenPastThreeSeconds() {
        let (player, out) = makeController()
        player.play(tracks: makeTracks(3), startAt: 1)
        out.snapshot.currentTime = 10
        out.onTick?(out.snapshot)          // engine reports progress
        player.previous()
        XCTAssertEqual(out.seeks.last, 0)
        XCTAssertEqual(player.current?.title, "Track 2", "não troca de música")
    }

    func testPreviousGoesBackWhenNearStart() {
        let (player, out) = makeController()
        player.play(tracks: makeTracks(3), startAt: 1)
        out.snapshot.currentTime = 1
        out.onTick?(out.snapshot)
        player.previous()
        XCTAssertEqual(player.current?.title, "Track 1")
    }

    func testSeekByProgress() {
        let (player, out) = makeController()
        player.play(tracks: makeTracks(1), startAt: 0)   // duração 100 s
        player.seek(progress: 0.5)
        XCTAssertEqual(out.seeks.last, 50)
    }

    func testVolumeIsClamped() {
        let (player, out) = makeController()
        player.setVolume(5)
        XCTAssertEqual(out.snapshot.volume, 1)
        player.setVolume(-2)
        XCTAssertEqual(out.snapshot.volume, 0)
    }

    // MARK: EQ and polarity reach the engine

    func testEQIsAppliedToEngine() {
        let (player, out) = makeController()
        player.updateEQ { $0.setGain(9, forBandAt: 0) }
        XCTAssertEqual(out.appliedEQ?.bands[0].gain, 9)
    }

    func testEQPresetIsApplied() {
        let (player, out) = makeController()
        player.applyEQPreset(EQPreset.builtIn[1])
        XCTAssertEqual(out.appliedEQ?.presetName, EQPreset.builtIn[1].name)
    }

    func testLocalPolarityReachesEngine() {
        let (player, out) = makeController()
        player.toggleLocalPolarity()
        XCTAssertTrue(out.polarityInverted)
        XCTAssertEqual(player.phase.localPolarity, .inverted)
        player.toggleLocalPolarity()
        XCTAssertFalse(out.polarityInverted)
    }

    func testEQAndPolarityAreReappliedOnEachTrack() {
        // A new file must not silently reset the operator's EQ or polarity.
        let (player, out) = makeController()
        player.updateEQ { $0.setGain(6, forBandAt: 1) }
        player.setLocalPolarity(.inverted)
        player.play(tracks: makeTracks(2), startAt: 0)
        out.finishTrack()
        XCTAssertEqual(out.appliedEQ?.bands[1].gain, 6)
        XCTAssertTrue(out.polarityInverted)
    }

    // MARK: Failure handling

    func testCorruptFileIsSkippedInsteadOfStallingTheSet() {
        let (player, out) = makeController()
        out.failingFiles = ["t2"]
        player.play(tracks: makeTracks(3), startAt: 0)
        out.finishTrack()          // tries t2, fails, should move on to t3
        XCTAssertEqual(player.current?.title, "Track 3")
        XCTAssertNotNil(player.lastError)
    }

    func testAllFilesFailingDoesNotLoopForever() {
        let (player, out) = makeController()
        out.failingFiles = ["t1", "t2", "t3"]
        player.play(tracks: makeTracks(3), startAt: 0)
        XCTAssertEqual(out.stopCount, 1, "desiste em vez de girar para sempre")
    }

    // MARK: History hook

    func testTrackStartedCallbackFiresForHistory() {
        let (player, out) = makeController()
        var started: [String] = []
        player.onTrackStarted = { started.append($0.title) }
        player.play(tracks: makeTracks(2), startAt: 0)
        out.finishTrack()
        XCTAssertEqual(started, ["Track 1", "Track 2"])
    }

    func testShuffleAndRepeatSurviveOnController() {
        let (player, _) = makeController()
        player.play(tracks: makeTracks(5), startAt: 0)
        player.toggleShuffle()
        XCTAssertTrue(player.isShuffled)
        player.cycleRepeat()
        XCTAssertEqual(player.repeatMode, .all)
    }
}

// MARK: - Player keeps running while the mixer is down

@MainActor
final class PlayerUI16IntegrationTests: XCTestCase {

    func testPlayerIsUnaffectedByMixerDisconnection() {
        // The whole point of separating the layers: losing the Ui16 mid-show must never
        // interrupt the music.
        let out = FakeAudioOutput()
        let player = PlayerController(output: out)
        let mixer = UI16Store()

        player.play(tracks: makeTracks(3), startAt: 0)
        XCTAssertTrue(out.snapshot.status == .playing)

        // Mixer goes away and comes back with completely different state.
        mixer.apply("SETD^m.mix^0.2")
        mixer.apply("SETD^i.0.mute^1")

        XCTAssertEqual(out.snapshot.status, .playing, "a música continua")
        XCTAssertEqual(player.current?.title, "Track 1")
        XCTAssertEqual(out.stopCount, 0)
    }

    func testMixerStateChangesDoNotTouchPlayerEQ() {
        let out = FakeAudioOutput()
        let player = PlayerController(output: out)
        let mixer = UI16Store()

        player.updateEQ { $0.setGain(8, forBandAt: 0) }
        mixer.apply("SETD^i.0.eq.high.gain^0.9")

        XCTAssertEqual(out.appliedEQ?.bands[0].gain, 8,
                       "EQ do player é local e não é sobrescrito pela mesa")
    }

    func testPolarityKeyIsDiscoveredFromMixerState() {
        // Nothing is transmitted until the mixer itself reveals a polarity parameter.
        let mixer = UI16Store()
        mixer.apply("SETD^i.0.mix^0.5")
        XCTAssertEqual(PhaseControl.resolve(channelAddress: "i.0",
                                            reportedKeys: mixer.state.raw.keys),
                       .unconfirmed)

        mixer.apply("SETD^i.0.phase^0")
        XCTAssertEqual(PhaseControl.resolve(channelAddress: "i.0",
                                            reportedKeys: mixer.state.raw.keys),
                       .available(key: "i.0.phase"))
    }

    func testMixerEchoConfirmsPolarity() {
        let out = FakeAudioOutput()
        let player = PlayerController(output: out)

        player.noteMixerPolarityRequested(.inverted)
        XCTAssertTrue(player.phase.awaitingConfirmation || player.phase.mixerConfirmed == nil)

        player.noteMixerPolarityConfirmed(.inverted)
        XCTAssertTrue(player.phase.isSynced)
        XCTAssertEqual(player.phase.mixerPolarity, .inverted)
    }
}

// MARK: - Persistence

final class ParedaoStorageTests: XCTestCase {

    private func tempStorage() -> ParedaoStorage {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paredao-test-\(UUID().uuidString).json")
        return ParedaoStorage(fileURL: url)
    }

    func testRoundTrip() throws {
        let storage = tempStorage()
        defer { try? FileManager.default.removeItem(at: storage.fileURL) }

        var snapshot = ParedaoSnapshot()
        snapshot.library.upsert([
            Track(fileName: "a", title: "Música A", artist: "Artista", absolutePath: "/a.mp3")
        ])
        let id = snapshot.library.tracks[0].id
        snapshot.library.toggleFavorite(id)
        snapshot.library.recordPlay(id)
        _ = snapshot.playlists.create(name: "Set 1")
        snapshot.eq.apply(EQPreset.builtIn[1])
        snapshot.repeatMode = .all
        snapshot.isShuffled = true
        snapshot.volume = 0.8

        try storage.save(snapshot)
        let loaded = try storage.load()

        XCTAssertEqual(loaded.library.tracks.count, 1)
        XCTAssertEqual(loaded.library.tracks[0].title, "Música A")
        XCTAssertTrue(loaded.library.isFavorite(id))
        XCTAssertEqual(loaded.library.history, [id])
        XCTAssertEqual(loaded.playlists.count, 1)
        XCTAssertEqual(loaded.eq.presetName, EQPreset.builtIn[1].name)
        XCTAssertEqual(loaded.repeatMode, .all)
        XCTAssertTrue(loaded.isShuffled)
        XCTAssertEqual(loaded.volume, 0.8)
    }

    func testMissingFileGivesEmptySnapshot() throws {
        let storage = tempStorage()
        XCTAssertEqual(try storage.load().library.tracks.count, 0)
    }

    func testCorruptFileDoesNotBrickTheApp() throws {
        // A damaged index must not stop the app from starting before a show.
        let storage = tempStorage()
        defer { try? FileManager.default.removeItem(at: storage.fileURL) }
        try Data("{ not json".utf8).write(to: storage.fileURL)
        XCTAssertEqual(storage.loadOrEmpty().library.tracks.count, 0)
    }

    func testSaveIsAtomicAndOverwrites() throws {
        let storage = tempStorage()
        defer { try? FileManager.default.removeItem(at: storage.fileURL) }

        var first = ParedaoSnapshot()
        first.volume = 0.3
        try storage.save(first)

        var second = ParedaoSnapshot()
        second.volume = 0.9
        try storage.save(second)

        XCTAssertEqual(try storage.load().volume, 0.9)
    }

    func testLargeLibraryPersists() throws {
        let storage = tempStorage()
        defer { try? FileManager.default.removeItem(at: storage.fileURL) }

        var snapshot = ParedaoSnapshot()
        snapshot.library.upsert((1...3000).map {
            Track(fileName: "f\($0)", title: "T\($0)", artist: "A\($0 % 20)",
                  absolutePath: "/m/\($0).mp3")
        })
        try storage.save(snapshot)
        XCTAssertEqual(try storage.load().library.tracks.count, 3000)
    }
}
