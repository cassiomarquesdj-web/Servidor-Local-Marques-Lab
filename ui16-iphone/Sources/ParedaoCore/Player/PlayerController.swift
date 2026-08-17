import Foundation

/// Drives playback: owns the queue, tells the audio engine what to do, and records history.
///
/// Deliberately knows **nothing** about the Ui16. The player must keep working when the
/// mixer is unreachable — losing the network mid-show must never stop the music.
/// Integration with the mixer happens one layer up, in the app.
@MainActor
public final class PlayerController: ObservableObject {

    @Published public private(set) var queue = PlaybackQueue()
    @Published public private(set) var snapshot = PlayerSnapshot()
    @Published public private(set) var eq = EQSettings()
    @Published public private(set) var phase = PhaseState()
    /// Last error shown to the operator, if any.
    @Published public private(set) var lastError: String?

    private let output: AudioOutput
    /// Called when a track starts, so the library can record history.
    public var onTrackStarted: ((Track) -> Void)?
    /// Called whenever state worth persisting changes.
    public var onStateChanged: (() -> Void)?

    public init(output: AudioOutput) {
        self.output = output
        self.output.onTrackEnded = { [weak self] in self?.handleTrackEnded() }
        self.output.onTick = { [weak self] snap in self?.snapshot = snap }
    }

    /// Pull the engine's current state. Called after every transport command so the UI
    /// updates on the same run loop turn as the tap, rather than on the next tick.
    private func syncSnapshot() { snapshot = output.snapshot }

    // MARK: Transport

    public var current: Track? { queue.current }
    public var isPlaying: Bool { snapshot.status == .playing }

    /// Load a list and start at a given track.
    public func play(tracks: [Track], startAt index: Int) {
        guard !tracks.isEmpty else { return }
        lastError = nil
        queue.load(tracks, startAt: index)
        startCurrent()
    }

    /// Clear the last error once the operator has seen it.
    public func clearError() { lastError = nil }

    /// Play a single track without disturbing the rest of the queue order.
    public func play(track: Track) {
        if let existing = queue.tracks.firstIndex(of: track) {
            queue.jump(toTrackIndex: existing)
        } else {
            queue.append(track)
            queue.jump(toTrackIndex: queue.count - 1)
        }
        startCurrent()
    }

    public func togglePlayPause() {
        switch snapshot.status {
        case .playing:
            output.pause()
            syncSnapshot()
        case .paused, .stopped:
            output.play()
            syncSnapshot()
        case .idle, .failed:
            if queue.current != nil { startCurrent() }
        case .loading:
            break
        }
    }

    public func pause() { output.pause(); syncSnapshot() }
    public func resume() { output.play(); syncSnapshot() }

    public func stop() {
        output.stop()
        syncSnapshot()
    }

    /// Skip forward. Explicit, so repeat-one still advances.
    public func next() {
        apply(queue.next(auto: false))
    }

    /// Previous. Restarts the track when more than 3 s has elapsed, which is what
    /// operators expect from a transport button.
    public func previous() {
        if snapshot.currentTime > 3 {
            output.seek(to: 0)
            return
        }
        apply(queue.previous())
    }

    public func seek(to time: TimeInterval) {
        output.seek(to: time)
        syncSnapshot()
    }

    public func seek(progress: Double) {
        guard snapshot.duration > 0 else { return }
        output.seek(to: min(max(progress, 0), 1) * snapshot.duration)
    }

    public func setVolume(_ volume: Double) {
        output.setVolume(min(max(volume, 0), 1))
        syncSnapshot()
        onStateChanged?()
    }

    // MARK: Modes

    public func toggleShuffle() {
        queue.toggleShuffle()
        onStateChanged?()
    }

    public func cycleRepeat() {
        queue.cycleRepeat()
        onStateChanged?()
    }

    public func setRepeat(_ mode: RepeatMode) {
        queue.repeatMode = mode
        onStateChanged?()
    }

    public var repeatMode: RepeatMode { queue.repeatMode }
    public var isShuffled: Bool { queue.isShuffled }

    // MARK: Queue editing

    public func enqueue(_ track: Track) {
        queue.append(track)
        onStateChanged?()
    }

    public func playNext(_ track: Track) {
        queue.playNext(track)
        onStateChanged?()
    }

    public func loadQueue(_ tracks: [Track], startAt index: Int = 0, autoplay: Bool) {
        queue.load(tracks, startAt: index)
        if autoplay { startCurrent() }
        onStateChanged?()
    }

    // MARK: EQ

    public func updateEQ(_ change: (inout EQSettings) -> Void) {
        change(&eq)
        output.applyEQ(eq)
        onStateChanged?()
    }

    public func setEQ(_ settings: EQSettings) {
        eq = settings
        output.applyEQ(eq)
        onStateChanged?()
    }

    public func resetEQ() {
        eq.reset()
        output.applyEQ(eq)
        onStateChanged?()
    }

    public func applyEQPreset(_ preset: EQPreset) {
        eq.apply(preset)
        output.applyEQ(eq)
        onStateChanged?()
    }

    // MARK: Local polarity

    /// Flip the polarity of the player output. This is real local DSP, independent of
    /// whatever the mixer does with its own channel polarity.
    public func setLocalPolarity(_ polarity: PhasePolarity) {
        phase.localPolarity = polarity
        output.setPolarityInverted(polarity.isInverted)
        onStateChanged?()
    }

    public func toggleLocalPolarity() {
        setLocalPolarity(phase.localPolarity.toggled)
    }

    /// Record what we asked the mixer for (the send itself happens in the app layer).
    public func noteMixerPolarityRequested(_ polarity: PhasePolarity) {
        phase.mixerPolarity = polarity
    }

    /// Record what the mixer echoed back, which clears the "awaiting" indicator.
    public func noteMixerPolarityConfirmed(_ polarity: PhasePolarity) {
        phase.mixerConfirmed = polarity
        phase.mixerPolarity = polarity
    }

    // MARK: Internals

    private func startCurrent() {
        guard let track = queue.current else { return }
        do {
            try output.load(track: track)
            output.applyEQ(eq)
            output.setPolarityInverted(phase.localPolarity.isInverted)
            output.play()
            syncSnapshot()
            onTrackStarted?(track)
            onStateChanged?()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            snapshot.status = .failed
            // A bad file must not stall the set — move on to the next one.
            skipAfterFailure()
        }
    }

    /// Advance past a file that failed, guarding against a run of bad files looping forever.
    private var consecutiveFailures = 0
    private func skipAfterFailure() {
        consecutiveFailures += 1
        guard consecutiveFailures < min(queue.count, 10) else {
            consecutiveFailures = 0
            output.stop()
            syncSnapshot()
            return
        }
        apply(queue.next(auto: false))
    }

    private func handleTrackEnded() {
        consecutiveFailures = 0
        apply(queue.next(auto: true))
    }

    private func apply(_ advance: PlaybackQueue.Advance) {
        switch advance {
        case .play:
            startCurrent()
        case .restart:
            output.seek(to: 0)
            output.play()
            syncSnapshot()
        case .stop:
            output.stop()
            syncSnapshot()
        }
        onStateChanged?()
    }
}
