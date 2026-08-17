import Foundation

/// A single EQ band.
///
/// These values drive the **local player EQ** (`AVAudioUnitEQ`). They are not sent to the
/// Ui16: the mixer's EQ write addresses are not publicly confirmed, and this project does
/// not invent protocol. See `docs/paredao.md`.
public struct EQBand: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case lowShelf, peak, highShelf
    }

    public let id: UUID
    public var name: String
    public var kind: Kind
    /// Centre (or corner) frequency in Hz.
    public var frequency: Double
    /// Gain in dB, `-24...+24`.
    public var gain: Double
    /// Q / bandwidth. For shelves this is the slope.
    public var q: Double
    public var bypassed: Bool

    public init(id: UUID = UUID(), name: String, kind: Kind,
                frequency: Double, gain: Double = 0, q: Double = 1.0, bypassed: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.frequency = frequency
        self.gain = gain
        self.q = q
        self.bypassed = bypassed
    }

    public static let gainRange: ClosedRange<Double> = -24 ... 24
    public static let freqRange: ClosedRange<Double> = 20 ... 20_000
    public static let qRange: ClosedRange<Double> = 0.1 ... 10

    public var clampedGain: Double { min(max(gain, EQBand.gainRange.lowerBound), EQBand.gainRange.upperBound) }
    public var clampedFrequency: Double { min(max(frequency, EQBand.freqRange.lowerBound), EQBand.freqRange.upperBound) }
    public var clampedQ: Double { min(max(q, EQBand.qRange.lowerBound), EQBand.qRange.upperBound) }
}

/// The five-band EQ applied to the player output.
public struct EQSettings: Equatable, Codable, Sendable {
    public var bands: [EQBand]
    /// Master bypass for the whole EQ.
    public var bypassed: Bool
    /// Output trim in dB applied after the bands, to compensate for boosted gain.
    public var preamp: Double
    /// Name of the preset currently applied, or empty when edited by hand.
    public var presetName: String

    public init(bands: [EQBand] = EQSettings.flatBands(),
                bypassed: Bool = false,
                preamp: Double = 0,
                presetName: String = "FLAT") {
        self.bands = bands
        self.bypassed = bypassed
        self.preamp = preamp
        self.presetName = presetName
    }

    /// Default band layout: the five bands the operator expects on a PA rig.
    public static func flatBands() -> [EQBand] {
        [
            EQBand(name: "LOW", kind: .lowShelf, frequency: 80, gain: 0, q: 0.7),
            EQBand(name: "LOW MID", kind: .peak, frequency: 250, gain: 0, q: 1.0),
            EQBand(name: "MID", kind: .peak, frequency: 1_000, gain: 0, q: 1.0),
            EQBand(name: "HIGH MID", kind: .peak, frequency: 3_500, gain: 0, q: 1.0),
            EQBand(name: "HIGH", kind: .highShelf, frequency: 10_000, gain: 0, q: 0.7),
        ]
    }

    public mutating func reset() {
        bands = EQSettings.flatBands()
        preamp = 0
        bypassed = false
        presetName = "FLAT"
    }

    public mutating func setGain(_ gain: Double, forBandAt index: Int) {
        guard bands.indices.contains(index) else { return }
        bands[index].gain = min(max(gain, EQBand.gainRange.lowerBound), EQBand.gainRange.upperBound)
        presetName = ""
    }

    public mutating func setFrequency(_ hz: Double, forBandAt index: Int) {
        guard bands.indices.contains(index) else { return }
        bands[index].frequency = min(max(hz, EQBand.freqRange.lowerBound), EQBand.freqRange.upperBound)
        presetName = ""
    }

    public mutating func setQ(_ q: Double, forBandAt index: Int) {
        guard bands.indices.contains(index) else { return }
        bands[index].q = min(max(q, EQBand.qRange.lowerBound), EQBand.qRange.upperBound)
        presetName = ""
    }

    public mutating func toggleBypass(bandAt index: Int) {
        guard bands.indices.contains(index) else { return }
        bands[index].bypassed.toggle()
        presetName = ""
    }

    public mutating func apply(_ preset: EQPreset) {
        bands = preset.bands
        preamp = preset.preamp
        presetName = preset.name
        bypassed = false
    }

    /// Combined magnitude response in dB at a frequency — used to draw the curve.
    /// Uses standard RBJ biquad magnitude responses so the graph matches what is heard.
    public func responseDB(at frequency: Double, sampleRate: Double = 48_000) -> Double {
        guard !bypassed else { return 0 }
        var total = preamp
        for band in bands where !band.bypassed {
            total += EQSettings.bandResponseDB(band, at: frequency, sampleRate: sampleRate)
        }
        return total
    }

    /// Magnitude response of one band at a frequency, in dB.
    static func bandResponseDB(_ band: EQBand, at f: Double, sampleRate: Double) -> Double {
        let gain = band.clampedGain
        guard gain != 0 else { return 0 }
        let f0 = band.clampedFrequency
        let q = band.clampedQ
        guard f > 0, f0 > 0 else { return 0 }

        let a = pow(10, gain / 40)          // amplitude for shelf/peak formulas
        let w0 = 2 * Double.pi * f0 / sampleRate
        let w = 2 * Double.pi * min(f, sampleRate / 2 - 1) / sampleRate
        let cosW0 = cos(w0), sinW0 = sin(w0)
        let alpha = sinW0 / (2 * q)

        var b0 = 0.0, b1 = 0.0, b2 = 0.0, a0 = 0.0, a1 = 0.0, a2 = 0.0

        switch band.kind {
        case .peak:
            b0 = 1 + alpha * a;  b1 = -2 * cosW0; b2 = 1 - alpha * a
            a0 = 1 + alpha / a;  a1 = -2 * cosW0; a2 = 1 - alpha / a
        case .lowShelf:
            let sq = 2 * sqrt(a) * alpha
            b0 = a * ((a + 1) - (a - 1) * cosW0 + sq)
            b1 = 2 * a * ((a - 1) - (a + 1) * cosW0)
            b2 = a * ((a + 1) - (a - 1) * cosW0 - sq)
            a0 = (a + 1) + (a - 1) * cosW0 + sq
            a1 = -2 * ((a - 1) + (a + 1) * cosW0)
            a2 = (a + 1) + (a - 1) * cosW0 - sq
        case .highShelf:
            let sq = 2 * sqrt(a) * alpha
            b0 = a * ((a + 1) + (a - 1) * cosW0 + sq)
            b1 = -2 * a * ((a - 1) + (a + 1) * cosW0)
            b2 = a * ((a + 1) + (a - 1) * cosW0 - sq)
            a0 = (a + 1) - (a - 1) * cosW0 + sq
            a1 = 2 * ((a - 1) - (a + 1) * cosW0)
            a2 = (a + 1) - (a - 1) * cosW0 - sq
        }

        guard a0 != 0 else { return 0 }
        // |H(e^jw)| for a biquad
        let cosW = cos(w), cos2W = cos(2 * w)
        let sinW = sin(w), sin2W = sin(2 * w)
        let numRe = b0 + b1 * cosW + b2 * cos2W
        let numIm = -(b1 * sinW + b2 * sin2W)
        let denRe = a0 + a1 * cosW + a2 * cos2W
        let denIm = -(a1 * sinW + a2 * sin2W)
        let num = sqrt(numRe * numRe + numIm * numIm)
        let den = sqrt(denRe * denRe + denIm * denIm)
        guard den > 0, num > 0 else { return 0 }
        return 20 * log10(num / den)
    }
}

/// A named EQ curve.
public struct EQPreset: Identifiable, Hashable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    public let bands: [EQBand]
    public let preamp: Double

    public init(name: String, bands: [EQBand], preamp: Double = 0) {
        self.name = name
        self.bands = bands
        self.preamp = preamp
    }

    static func make(_ name: String, _ gains: [Double], preamp: Double = 0,
                     freqs: [Double]? = nil) -> EQPreset {
        var bands = EQSettings.flatBands()
        for (i, g) in gains.enumerated() where bands.indices.contains(i) {
            bands[i].gain = g
            if let freqs, freqs.indices.contains(i) { bands[i].frequency = freqs[i] }
        }
        return EQPreset(name: name, bands: bands, preamp: preamp)
    }

    /// Presets aimed at the kind of material a paredão plays.
    /// Boosting bands raises headroom demand, so heavy curves carry negative preamp
    /// to avoid clipping the output.
    public static let builtIn: [EQPreset] = [
        .make("FLAT", [0, 0, 0, 0, 0]),
        .make("PAREDÃO", [7, 2, -1, 1.5, 4], preamp: -4),
        .make("GRAVE PESADO", [9, 3, -2, 0, 2], preamp: -5),
        .make("VOZ / MC", [-2, -1, 3, 4, 2], preamp: -2),
        .make("BRILHO", [1, 0, 0, 3, 6], preamp: -3),
        .make("AO VIVO", [4, 1, 0, 2, 3], preamp: -3),
        .make("RÁDIO", [2, -2, 2, 2, 1], preamp: -1),
    ]
}
