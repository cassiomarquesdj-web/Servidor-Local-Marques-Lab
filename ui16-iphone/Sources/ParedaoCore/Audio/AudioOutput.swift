import Foundation

/// What the player is doing right now.
public enum PlaybackStatus: String, Equatable, Sendable, Codable {
    case idle, loading, playing, paused, stopped, failed
}

/// Snapshot of the audio engine, published to the UI.
public struct PlayerSnapshot: Equatable, Sendable {
    public var status: PlaybackStatus = .idle
    public var currentTime: TimeInterval = 0
    public var duration: TimeInterval = 0
    /// Output level `0...1` for the meters, left and right.
    public var levelL: Double = 0
    public var levelR: Double = 0
    /// Player output volume `0...1` (independent of the Ui16 master).
    public var volume: Double = 1
    public var errorMessage: String?

    public init() {}

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
    public var remaining: TimeInterval { max(0, duration - currentTime) }
    public var isPlaying: Bool { status == .playing }
}

/// The audio engine contract.
///
/// The player layer talks only to this, so playback logic (queue, repeat, shuffle) is
/// testable with a fake and never needs a real audio device or CI audio session.
public protocol AudioOutput: AnyObject {
    /// Current engine state. Read straight after a transport call so the UI reflects the
    /// change immediately instead of waiting for the next tick.
    var snapshot: PlayerSnapshot { get }

    /// Called when a track reaches its natural end, so the queue can advance.
    /// Delivered on the main actor — implementations must hop from the audio thread.
    var onTrackEnded: (@MainActor () -> Void)? { get set }
    /// Called on each engine tick so the UI can follow time and meters.
    /// Delivered on the main actor.
    var onTick: (@MainActor (PlayerSnapshot) -> Void)? { get set }

    func load(track: Track) throws
    func play()
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    func setVolume(_ volume: Double)

    func applyEQ(_ settings: EQSettings)
    /// Flip the polarity of the player's own output.
    func setPolarityInverted(_ inverted: Bool)
}

/// Errors the engine can raise, in language the operator can act on.
public enum AudioEngineError: LocalizedError, Equatable {
    case fileUnreadable(String)
    case unsupportedFormat(String)
    case accessDenied(String)
    case engineFailure(String)

    public var errorDescription: String? {
        switch self {
        case .fileUnreadable(let name): return "Não foi possível abrir \"\(name)\"."
        case .unsupportedFormat(let ext): return "Formato .\(ext) não suportado."
        case .accessDenied(let name): return "Sem permissão para acessar \"\(name)\". Reimporte a pasta."
        case .engineFailure(let detail): return "Falha no motor de áudio: \(detail)"
        }
    }
}
