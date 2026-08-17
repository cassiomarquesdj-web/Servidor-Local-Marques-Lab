import Foundation

/// Polarity (phase) control.
///
/// Two distinct things are called "phase" here and they must not be confused:
///
/// 1. **Player polarity** — flips the sign of the player's own audio samples. Fully
///    implemented locally and verifiable without any hardware.
/// 2. **Mixer channel polarity** — the one that actually matters live, for time-aligning
///    subs against tops. That belongs to the Ui16.
///
/// The Ui16's polarity write address is **not** publicly confirmed, and this project does
/// not invent protocol. Instead of guessing a key and pretending it worked, the address is
/// **discovered from the mixer itself**: the Ui16 reports its full parameter set on connect,
/// so if a polarity parameter exists for a channel it will appear in the received state.
/// `resolve(...)` looks for it there. Until a real key is seen, the control reports
/// `.unconfirmed` and refuses to transmit.
public enum PhasePolarity: String, Codable, Sendable {
    case normal, inverted

    public var isInverted: Bool { self == .inverted }
    public var toggled: PhasePolarity { self == .normal ? .inverted : .normal }
    public var label: String { self == .normal ? "NORMAL" : "INVERTIDA" }
    /// Wire value if/when a mixer key is confirmed: `0` normal, `1` inverted.
    public var wireValue: Int { self == .inverted ? 1 : 0 }
}

/// Whether a mixer-side polarity parameter is usable for a given channel.
public enum PhaseAvailability: Equatable, Sendable {
    /// No polarity key has been reported by the mixer for this channel.
    /// Nothing is transmitted in this state.
    case unconfirmed
    /// The mixer reported this exact key; it is safe to read and write.
    case available(key: String)

    public var key: String? {
        if case .available(let k) = self { return k }
        return nil
    }
    public var isAvailable: Bool { key != nil }
}

public enum PhaseControl {

    /// Parameter suffixes that would denote polarity on a Ui-series channel.
    /// These are *candidates to look for in what the mixer actually reports* — never
    /// addresses to send blindly.
    public static let candidateSuffixes = ["phase", "polarity", "invert", "pol", "phaseinvert"]

    /// Find a real polarity key for `channelAddress` among the keys the mixer has reported.
    ///
    /// - Parameters:
    ///   - channelAddress: zero-based strip address, e.g. `i.0`.
    ///   - reportedKeys: every state key received from the mixer so far.
    public static func resolve(channelAddress: String, reportedKeys: some Collection<String>) -> PhaseAvailability {
        let prefix = channelAddress + "."
        for key in reportedKeys where key.hasPrefix(prefix) {
            let suffix = String(key.dropFirst(prefix.count)).lowercased()
            if candidateSuffixes.contains(suffix) {
                return .available(key: key)
            }
        }
        return .unconfirmed
    }

    /// Human-readable explanation for the UI when nothing can be transmitted.
    public static let unconfirmedExplanation =
        "A mesa ainda não reportou um parâmetro de polaridade para este canal. "
        + "Nenhum comando é enviado até o endereço real aparecer no estado da Ui16. "
        + "A inversão local do player continua funcionando."
}

/// Observable-friendly value type holding both polarity targets.
public struct PhaseState: Equatable, Codable, Sendable {
    /// Polarity applied to the player's own output (local DSP).
    public var localPolarity: PhasePolarity = .normal
    /// Last polarity we asked the mixer for.
    public var mixerPolarity: PhasePolarity = .normal
    /// Polarity the mixer last confirmed. Differs from `mixerPolarity` while a write is
    /// in flight, which is what drives the "aguardando confirmação" indicator.
    public var mixerConfirmed: PhasePolarity?

    public init() {}

    /// `true` when a mixer write has been sent but not yet echoed back.
    public var awaitingConfirmation: Bool {
        guard let confirmed = mixerConfirmed else { return false }
        return confirmed != mixerPolarity
    }

    /// `true` once the mixer has echoed the requested polarity.
    public var isSynced: Bool { mixerConfirmed == mixerPolarity }
}
