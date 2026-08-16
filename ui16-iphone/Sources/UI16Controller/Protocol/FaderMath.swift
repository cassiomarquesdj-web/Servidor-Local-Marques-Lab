import Foundation

/// Value conversions for the Soundcraft Ui series.
///
/// The fader transfer function is the exact curve used by the mixer's own web UI,
/// reproduced from the open-source reference implementation
/// (fmalcher/soundcraft-ui, `value-converters.ts`). Faders on the Ui are **not**
/// linear in dB: a linear fader position `0...1` maps through this polynomial to a
/// linear amplitude, and only then to dB. Using a naive `position * range` mapping
/// (as the previous code did) shows wrong dB numbers on screen.
public enum FaderMath {

    /// Transfer function of the Ui fader: fader position (`0...1`) -> linear amplitude.
    public static func faderToLinearAmplitude(_ v: Double) -> Double {
        let poly = (23.90844819639692
                    + (-26.23877598214595
                       + (12.195249692570245 - 0.4878099877028098 * v) * v) * v) * v
        let head = v < 0.055 ? sin(28.559933214452666 * v) : 1
        return head * exp(poly) * 2.676529517952372e-4
    }

    /// Derivative of `faderToLinearAmplitude`, used to invert the curve with Newton's method.
    private static func faderToLinearAmplitudeDeriv(_ v: Double) -> Double {
        let p = (23.90844819639692
                 + (-26.23877598214595
                    + (12.195249692570245 - 0.4878099877028098 * v) * v) * v) * v
        let pPrime = 23.90844819639692
            + (-52.4775519642919
               + (36.58574907771074 - 1.9512399508112392 * v) * v) * v
        let expP = exp(p)
        if v < 0.055 {
            let wv = 28.559933214452666 * v
            return 2.676529517952372e-4 * expP * (28.559933214452666 * cos(wv) + sin(wv) * pPrime)
        }
        return 2.676529517952372e-4 * expP * pPrime
    }

    /// Convert a linear fader position (`0...1`) to dB (`-Infinity ... +10`).
    public static func faderValueToDB(_ value: Double) -> Double {
        let lin = faderToLinearAmplitude(value)
        if lin < 1e-10 { return -.infinity }
        let db = (20 * log10(lin) * 10).rounded() / 10
        return db == 0 ? 0 : db
    }

    /// Convert dB (`-Infinity ... +10`) to a linear fader position (`0...1`).
    /// Numerically inverts the transfer function with Newton's method.
    public static func dbToFaderValue(_ dbValue: Double) -> Double {
        if dbValue <= -200 { return 0 }
        if dbValue >= 10 { return 1 }
        let target = pow(10, dbValue / 20)
        var v = 0.5
        for _ in 0..<20 {
            let delta = (faderToLinearAmplitude(v) - target) / faderToLinearAmplitudeDeriv(v)
            v -= delta
            if v < 0 { v = 1e-10 }
            if v > 1 { v = 1 }
            if abs(delta) < 1e-15 { break }
        }
        return (v * 1e11).rounded() / 1e11
    }

    /// Linear scaling of a `0...1` value into an arbitrary range (e.g. gain 0...1 -> -40...50 dB).
    /// Rounds to one decimal place, matching the reference implementation.
    public static func mapValueToRange(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        let result = ((value * (upper - lower) + lower) * 10).rounded() / 10
        return min(max(result, lower), upper)
    }

    /// Inverse of `mapValueToRange`: an in-range value back to `0...1`.
    public static func mapRangeToValue(_ rangeValue: Double, _ lower: Double, _ upper: Double) -> Double {
        let result = (rangeValue - lower) / (upper - lower)
        return min(max(result, 0), 1)
    }

    /// Ui12/Ui16 hardware gain range in dB.
    public static let gainRangeDB: ClosedRange<Double> = -40 ... 50

    /// Linear gain position (`0...1`) -> gain in dB for Ui12/Ui16.
    public static func gainValueToDB(_ value: Double) -> Double {
        mapValueToRange(value, gainRangeDB.lowerBound, gainRangeDB.upperBound)
    }

    /// Gain in dB -> linear gain position (`0...1`) for Ui12/Ui16.
    public static func gainDBToValue(_ db: Double) -> Double {
        mapRangeToValue(db, gainRangeDB.lowerBound, gainRangeDB.upperBound)
    }

    /// Convert a linear VU value (`0...1`) to dB (`-80...0`).
    public static func vuValueToDB(_ value: Double) -> Double {
        mapValueToRange(value, -80, 0)
    }

    /// Human-readable dB string, e.g. `-inf`, `-12.3 dB`, `+4.0 dB`.
    public static func dbString(_ value: Double) -> String {
        let db = faderValueToDB(value)
        if db == -.infinity { return "-∞" }
        return String(format: "%+.1f dB", db)
    }
}
