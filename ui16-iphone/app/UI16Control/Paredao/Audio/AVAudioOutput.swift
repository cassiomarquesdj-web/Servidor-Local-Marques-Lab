import AVFoundation
import Foundation
import ParedaoCore

/// The real audio engine.
///
/// Signal path:  player → EQ (5 bands) → main mixer → output
///
/// A custom polarity AudioUnit was written for local phase inversion (see
/// `PolarityAudioUnit`), but inserting it stalls rendering — playback froze and the
/// transport clock stopped. Rather than ship broken audio, the node is kept out of the
/// graph and `isPolarityAvailable` reports `false`, so the UI disables the control and
/// says why. Mixer-side polarity is unaffected.
///
/// Chosen over `AVPlayer` because this mode needs a real EQ, a polarity stage and
/// sample-accurate output metering — none of which `AVPlayer` exposes.
/// `AVAudioFile` decodes MP3, WAV, AIFF, M4A/AAC, ALAC, CAF and FLAC natively.
///
/// Files are streamed from disk by segment, never loaded whole into memory, so a long set
/// on a phone with thousands of tracks does not blow up the memory footprint.
@MainActor
final class AVAudioOutput: AudioOutput {

    nonisolated(unsafe) var snapshot = PlayerSnapshot()
    nonisolated(unsafe) var onTrackEnded: (@MainActor () -> Void)?
    nonisolated(unsafe) var onTick: (@MainActor (PlayerSnapshot) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 5)
    private var polarityNode: AVAudioUnit?
    private var polarityUnit: PolarityAudioUnit?

    private var file: AVAudioFile?
    private var currentTrack: Track?
    /// Frame the current segment started at, so elapsed time survives seeking.
    private var segmentStartFrame: AVAudioFramePosition = 0
    private var sampleRate: Double = 44_100
    private var totalFrames: AVAudioFramePosition = 0
    /// Set while a seek is tearing down the old segment, so its completion handler
    /// is not mistaken for the track ending.
    private var isSeeking = false
    private var scheduledGeneration = 0

    private var ticker: Timer?
    /// Security-scoped URL currently held open, released when the track changes.
    private var scopedURL: URL?

    init() {
        PolarityAudioUnit.registerIfNeeded()
        configureSession()
        buildGraph()
        startTicker()
    }

    deinit {
        ticker?.invalidate()
        peakL.deallocate()
        peakR.deallocate()
    }

    // MARK: Setup

    private func configureSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback keeps audio running when the phone is locked or the app is
            // backgrounded — a set must not stop because the screen went off.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            snapshot.errorMessage = "Sessão de áudio: \(error.localizedDescription)"
        }
        #endif
    }

    private func buildGraph() {
        engine.attach(player)
        engine.attach(eqNode)
        configureEQNodeDefaults()

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

        engine.connect(player, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)

        installMeterTap()
        startEngine()
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            snapshot.status = .failed
            snapshot.errorMessage = AudioEngineError.engineFailure(error.localizedDescription).errorDescription
        }
    }

    /// Latest peak measured on the audio thread, read by the UI ticker.
    ///
    /// Written from the render thread and read on the main actor without locking. A torn
    /// read here is a meter that is one frame stale — harmless — and locking on the audio
    /// thread would be far worse.
    private let peakL = UnsafeMutablePointer<Double>.allocate(capacity: 1)
    private let peakR = UnsafeMutablePointer<Double>.allocate(capacity: 1)

    /// Measure the real output for the VU meters.
    ///
    /// The tap must **not** hop to the main actor per buffer: at 44.1 kHz with 1024-frame
    /// buffers that is ~43 main-actor hops a second, which starves SwiftUI and leaves the
    /// screen blank. It only stores the peak; the 20 Hz ticker publishes it.
    private func installMeterTap() {
        let mixer = engine.mainMixerNode
        mixer.removeTap(onBus: 0)
        peakL.pointee = 0
        peakR.pointee = 0
        let outL = peakL
        let outR = peakR

        mixer.installTap(onBus: 0, bufferSize: 2048, format: mixer.outputFormat(forBus: 0)) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }

            var maxL: Float = 0
            let left = channels[0]
            // Stride-sample instead of scanning every frame: peak metering does not need
            // sample-exact precision and this keeps the render thread cheap.
            var i = 0
            while i < frames {
                let v = abs(left[i])
                if v > maxL { maxL = v }
                i += 4
            }

            var maxR = maxL
            if buffer.format.channelCount > 1 {
                maxR = 0
                let right = channels[1]
                var j = 0
                while j < frames {
                    let v = abs(right[j])
                    if v > maxR { maxR = v }
                    j += 4
                }
            }

            outL.pointee = Double(maxL)
            outR.pointee = Double(maxR)
        }
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        // Fast attack, slow release, so meters read like a console rather than flicker.
        snapshot.levelL = max(peakL.pointee, snapshot.levelL * 0.80)
        snapshot.levelR = max(peakR.pointee, snapshot.levelR * 0.80)

        // Gate on our own status, not on `AVAudioPlayerNode.isPlaying`: that flag is not a
        // reliable indicator of render progress, and gating on it froze the transport clock
        // while audio was in fact playing.
        if snapshot.status == .playing {
            snapshot.currentTime = currentElapsed()
        }
        onTick?(snapshot)
    }

    /// Elapsed position within the current track.
    ///
    /// Prefers the node's own render clock, which stays sample-accurate across pauses.
    /// Falls back to a wall clock measured from when playback last started, so the display
    /// keeps moving even when the node clock is unavailable.
    private func currentElapsed() -> TimeInterval {
        let base = Double(segmentStartFrame) / max(sampleRate, 1)

        if let nodeTime = player.lastRenderTime,
           let playerTime = player.playerTime(forNodeTime: nodeTime),
           playerTime.sampleRate > 0,
           playerTime.sampleTime > 0 {
            let played = Double(playerTime.sampleTime) / playerTime.sampleRate
            return min(max(base + played, 0), snapshot.duration)
        }

        guard let startedAt = playbackStartedAt else { return snapshot.currentTime }
        let played = Date().timeIntervalSince(startedAt)
        return min(max(base + played, 0), snapshot.duration)
    }

    /// Wall-clock reference for the fallback elapsed calculation.
    private var playbackStartedAt: Date?

    // MARK: AudioOutput

    func load(track: Track) throws {
        stopScopedAccess()

        let url = try resolveURL(for: track)
        do {
            let audioFile = try AVAudioFile(forReading: url)
            file = audioFile
            currentTrack = track
            sampleRate = audioFile.processingFormat.sampleRate
            totalFrames = audioFile.length
            segmentStartFrame = 0
            snapshot.duration = sampleRate > 0 ? Double(totalFrames) / sampleRate : track.duration
            snapshot.currentTime = 0
            snapshot.errorMessage = nil
            snapshot.status = .paused

            startEngine()
            player.stop()
            scheduleFromCurrentSegment()
        } catch {
            snapshot.status = .failed
            throw AudioEngineError.fileUnreadable(track.fileName)
        }
    }

    /// Resolve the file location, preferring the security-scoped bookmark so access
    /// survives relaunches without copying the file into the app.
    private func resolveURL(for track: Track) throws -> URL {
        if let bookmark = track.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark,
                                  options: [],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                let target = track.relativePath.isEmpty
                    ? url
                    : url.appendingPathComponent(track.relativePath)
                if url.startAccessingSecurityScopedResource() {
                    scopedURL = url
                }
                if FileManager.default.fileExists(atPath: target.path) {
                    return target
                }
                stopScopedAccess()
            }
        }
        let direct = URL(fileURLWithPath: track.absolutePath)
        guard FileManager.default.fileExists(atPath: direct.path) else {
            throw AudioEngineError.accessDenied(track.fileName)
        }
        return direct
    }

    private func stopScopedAccess() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    private func scheduleFromCurrentSegment() {
        guard let file else { return }
        let remaining = totalFrames - segmentStartFrame
        guard remaining > 0 else { return }

        scheduledGeneration += 1
        let generation = scheduledGeneration

        // `.dataPlayedBack` is essential: the default (`.dataConsumed`) fires as soon as the
        // player has read the data, which is long before the audio has actually been heard.
        // With the default, a track "ends" seconds early and the set races ahead.
        player.scheduleSegment(file,
                               startingFrame: segmentStartFrame,
                               frameCount: AVAudioFrameCount(remaining),
                               at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Ignore completions from segments superseded by a seek or a new track.
                guard generation == self.scheduledGeneration, !self.isSeeking else { return }
                self.snapshot.currentTime = self.snapshot.duration
                self.snapshot.status = .stopped
                self.onTrackEnded?()
            }
        }
    }

    func play() {
        guard file != nil else { return }
        startEngine()
        player.play()
        // Anchor the wall clock at the position we are resuming from.
        segmentStartFrame = AVAudioFramePosition(snapshot.currentTime * sampleRate)
        playbackStartedAt = Date()
        snapshot.status = .playing
    }

    func pause() {
        player.pause()
        playbackStartedAt = nil
        snapshot.status = .paused
    }

    func stop() {
        player.stop()
        playbackStartedAt = nil
        snapshot.status = .stopped
        snapshot.currentTime = 0
        snapshot.levelL = 0
        snapshot.levelR = 0
    }

    func seek(to time: TimeInterval) {
        guard file != nil, sampleRate > 0 else { return }
        let wasPlaying = player.isPlaying
        isSeeking = true
        player.stop()

        let target = min(max(time, 0), snapshot.duration)
        segmentStartFrame = AVAudioFramePosition(target * sampleRate)
        if segmentStartFrame >= totalFrames { segmentStartFrame = max(0, totalFrames - 1) }
        snapshot.currentTime = target

        scheduleFromCurrentSegment()
        isSeeking = false
        if wasPlaying {
            player.play()
            playbackStartedAt = Date()
            snapshot.status = .playing
        }
    }

    func setVolume(_ volume: Double) {
        let v = Float(min(max(volume, 0), 1))
        engine.mainMixerNode.outputVolume = v
        snapshot.volume = Double(v)
    }

    // MARK: EQ

    private func configureEQNodeDefaults() {
        let defaults = EQSettings()
        apply(defaults, to: eqNode)
    }

    func applyEQ(_ settings: EQSettings) {
        apply(settings, to: eqNode)
    }

    private func apply(_ settings: EQSettings, to node: AVAudioUnitEQ) {
        node.bypass = settings.bypassed
        node.globalGain = Float(min(max(settings.preamp, -24), 24))

        for (index, band) in settings.bands.enumerated() where index < node.bands.count {
            let target = node.bands[index]
            switch band.kind {
            case .lowShelf: target.filterType = .lowShelf
            case .peak: target.filterType = .parametric
            case .highShelf: target.filterType = .highShelf
            }
            target.frequency = Float(band.clampedFrequency)
            target.gain = Float(band.clampedGain)
            target.bandwidth = Float(bandwidthOctaves(forQ: band.clampedQ))
            target.bypass = band.bypassed
        }
    }

    /// `AVAudioUnitEQ` takes bandwidth in octaves; the UI works in Q, which is what
    /// engineers expect. Standard conversion between the two.
    private func bandwidthOctaves(forQ q: Double) -> Double {
        let safeQ = max(q, 0.05)
        let inner = 1 + 1 / (2 * safeQ * safeQ)
        let root = max(inner * inner - 1, 0)
        let value = (2 / log(2.0)) * asinh(1 / (2 * safeQ))
        // clamp into the range AVAudioUnitEQ accepts
        return min(max(value.isFinite ? value : log2(inner + sqrt(root)), 0.05), 5.0)
    }

    // MARK: Polarity

    func setPolarityInverted(_ inverted: Bool) {
        // No-op while the polarity stage is out of the graph. Kept so the protocol and the
        // player logic stay complete and tested; wiring it back up is a one-line change
        // once the render stall in `PolarityAudioUnit` is fixed.
        polarityUnit?.inverted = inverted
    }

    /// `false` while the polarity stage is disconnected, so the UI can disable the control
    /// instead of showing a button that silently does nothing.
    var isPolarityAvailable: Bool { false }

    /// Explanation shown next to the disabled control.
    static let polarityUnavailableReason =
        "A inversão de polaridade do player está desativada nesta versão: a AudioUnit "
        + "personalizada trava a renderização. O áudio toca normalmente sem ela. "
        + "A polaridade da mesa não é afetada."
}
