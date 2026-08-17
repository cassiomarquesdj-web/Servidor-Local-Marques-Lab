import Foundation

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one

    public var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// Ordering and advance rules for playback. Pure logic — no audio, no I/O — so every
/// repeat/shuffle combination is unit-testable.
///
/// Shuffle is modelled as a permutation of positions rather than by mutating the track list.
/// That keeps the underlying order intact, so turning shuffle off restores the original
/// sequence and the currently playing track never changes just because the mode changed.
public struct PlaybackQueue: Equatable, Sendable {

    public private(set) var tracks: [Track] = []
    /// Playback order as indices into `tracks`. Identity when shuffle is off.
    public private(set) var order: [Int] = []
    /// Position within `order`, not within `tracks`.
    public private(set) var position: Int = 0

    public var repeatMode: RepeatMode = .off
    public private(set) var isShuffled: Bool = false

    /// Seed for deterministic shuffling in tests. `nil` uses the system generator.
    public var shuffleSeed: UInt64?

    public init() {}

    public init(tracks: [Track], startAt: Int = 0) {
        self.tracks = tracks
        self.order = Array(tracks.indices)
        self.position = tracks.isEmpty ? 0 : min(max(startAt, 0), tracks.count - 1)
    }

    // MARK: Current

    public var isEmpty: Bool { tracks.isEmpty }
    public var count: Int { tracks.count }

    /// Index into `tracks` of the current item.
    public var currentIndex: Int? {
        guard order.indices.contains(position) else { return nil }
        return order[position]
    }

    public var current: Track? {
        guard let i = currentIndex, tracks.indices.contains(i) else { return nil }
        return tracks[i]
    }

    /// Upcoming tracks in playback order (excludes the current one).
    public func upcoming(limit: Int = Int.max) -> [Track] {
        guard !order.isEmpty else { return [] }
        let tail = order.indices.filter { $0 > position }
        return tail.prefix(limit).compactMap { tracks.indices.contains(order[$0]) ? tracks[order[$0]] : nil }
    }

    // MARK: Loading

    /// Replace the queue. `startAt` is an index into `tracks`.
    public mutating func load(_ newTracks: [Track], startAt: Int = 0) {
        tracks = newTracks
        order = Array(newTracks.indices)
        position = newTracks.isEmpty ? 0 : min(max(startAt, 0), newTracks.count - 1)
        if isShuffled { applyShuffleKeepingCurrent() }
    }

    /// Jump to a specific track index, keeping the current mode.
    public mutating func jump(toTrackIndex index: Int) {
        guard tracks.indices.contains(index) else { return }
        if let p = order.firstIndex(of: index) { position = p }
    }

    public mutating func append(_ track: Track) {
        tracks.append(track)
        order.append(tracks.count - 1)
    }

    /// Insert right after the current item ("play next").
    public mutating func playNext(_ track: Track) {
        tracks.append(track)
        let newIndex = tracks.count - 1
        let insertAt = order.isEmpty ? 0 : min(position + 1, order.count)
        order.insert(newIndex, at: insertAt)
    }

    public mutating func remove(atOrderPosition p: Int) {
        guard order.indices.contains(p) else { return }
        let trackIndex = order[p]
        order.remove(at: p)
        tracks.remove(at: trackIndex)
        // indices after the removed track shift down by one
        order = order.map { $0 > trackIndex ? $0 - 1 : $0 }
        if p < position { position -= 1 }
        position = order.isEmpty ? 0 : min(position, order.count - 1)
    }

    // MARK: Modes

    /// Toggle shuffle. The currently playing track keeps playing and becomes the new
    /// starting point — switching modes must never interrupt what the room is hearing.
    public mutating func setShuffled(_ on: Bool) {
        guard on != isShuffled else { return }
        isShuffled = on
        if on {
            applyShuffleKeepingCurrent()
        } else {
            let currentTrack = currentIndex
            order = Array(tracks.indices)
            position = currentTrack.flatMap { order.firstIndex(of: $0) } ?? 0
        }
    }

    public mutating func toggleShuffle() { setShuffled(!isShuffled) }

    public mutating func cycleRepeat() { repeatMode = repeatMode.next }

    private mutating func applyShuffleKeepingCurrent() {
        guard !tracks.isEmpty else { order = []; position = 0; return }
        let keep = currentIndex
        var rest = Array(tracks.indices)
        if let keep { rest.removeAll { $0 == keep } }

        if let seed = shuffleSeed {
            // deterministic shuffle for tests
            var gen = SplitMix64(seed: seed)
            rest.shuffle(using: &gen)
        } else {
            rest.shuffle()
        }

        order = (keep.map { [$0] } ?? []) + rest
        position = 0
    }

    // MARK: Advancing

    /// Result of trying to move through the queue.
    public enum Advance: Equatable, Sendable {
        /// Play the track at this index into `tracks`.
        case play(Int)
        /// Restart the current track from the beginning (repeat-one).
        case restart
        /// Nothing left to play — stop.
        case stop
    }

    /// Move to the next item.
    ///
    /// - Parameter auto: `true` when a track ended on its own, `false` when the operator
    ///   pressed *next*. Repeat-one only repeats on natural end; pressing next must still
    ///   skip forward, otherwise the button appears broken.
    public mutating func next(auto: Bool) -> Advance {
        guard !order.isEmpty else { return .stop }

        if auto, repeatMode == .one { return .restart }

        if position + 1 < order.count {
            position += 1
            return .play(order[position])
        }

        // past the end
        switch repeatMode {
        case .all:
            if isShuffled { applyReshuffleForNewLap() } else { position = 0 }
            return .play(order[position])
        case .one:
            // manual next on the last track wraps rather than dead-ending
            if auto { return .restart }
            position = 0
            return .play(order[position])
        case .off:
            return .stop
        }
    }

    /// Reshuffle for a new lap so repeat-all doesn't replay the same random order forever.
    private mutating func applyReshuffleForNewLap() {
        var rest = Array(tracks.indices)
        if let seed = shuffleSeed {
            var gen = SplitMix64(seed: seed &+ 7)
            rest.shuffle(using: &gen)
        } else {
            rest.shuffle()
        }
        order = rest
        position = 0
    }

    /// Move to the previous item. Wraps under repeat-all; clamps at the start otherwise.
    public mutating func previous() -> Advance {
        guard !order.isEmpty else { return .stop }
        if position > 0 {
            position -= 1
            return .play(order[position])
        }
        if repeatMode == .all {
            position = order.count - 1
            return .play(order[position])
        }
        return .restart
    }
}

/// Small deterministic PRNG, so shuffle can be asserted in tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
