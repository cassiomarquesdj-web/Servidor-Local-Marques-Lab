import Foundation

/// Typed VU meter data decoded from a `VU2^<base64>` frame.
///
/// Byte layout confirmed against the reference implementation (fmalcher/soundcraft-ui,
/// `vu.utils.ts`). The frame begins with an 8-byte preamble; bytes `0...6` are the per-type
/// channel counts in this fixed order, and each type's samples follow as fixed-size blocks:
///
/// | type   | count byte | block | fields                                   |
/// |--------|-----------|-------|------------------------------------------|
/// | input  | 0         | 6     | pre, post, postFader                     |
/// | player | 1         | 6     | pre, post, postFader                     |
/// | sub    | 2         | 7     | postL, postR, postFaderL, postFaderR     |
/// | fx     | 3         | 7     | postL, postR, postFaderL, postFaderR     |
/// | aux    | 4         | 5     | post, postFader                          |
/// | master | 5         | 5     | post, postFader (index 0 = L, 1 = R)     |
/// | line   | 6         | 6     | pre, post, postFader                     |
///
/// Raw bytes are scaled by `normalizeFactor` (≈ 1/240) to a `0...1` linear meter value.
public struct VUFrame: Equatable, Sendable {

    public struct Mono: Equatable, Sendable {
        public var pre: Double
        public var post: Double
        public var postFader: Double
    }

    public struct Send: Equatable, Sendable {
        public var post: Double
        public var postFader: Double
    }

    public struct Stereo: Equatable, Sendable {
        public var postL: Double
        public var postR: Double
        public var postFaderL: Double
        public var postFaderR: Double
    }

    public var input: [Mono] = []
    public var player: [Mono] = []
    public var line: [Mono] = []
    public var aux: [Send] = []
    public var fx: [Stereo] = []
    public var sub: [Stereo] = []
    public var master: [Send] = []   // [0] = L, [1] = R

    public init() {}

    /// Post-fader meter level (`0...1`) for a strip, if present in this frame.
    public func postFader(for ref: ChannelRef) -> Double? {
        let i = ref.number - 1
        switch ref.kind {
        case .input:  return input.indices.contains(i) ? input[i].postFader : nil
        case .player: return player.indices.contains(i) ? player[i].postFader : nil
        case .line:   return line.indices.contains(i) ? line[i].postFader : nil
        case .aux:    return aux.indices.contains(i) ? aux[i].postFader : nil
        case .fx:     return fx.indices.contains(i) ? max(fx[i].postFaderL, fx[i].postFaderR) : nil
        case .sub:    return sub.indices.contains(i) ? max(sub[i].postFaderL, sub[i].postFaderR) : nil
        case .vca:    return nil
        }
    }

    /// Stereo master post-fader levels (L, R), if present.
    public var masterPostFader: (l: Double, r: Double)? {
        guard master.count >= 2 else { return nil }
        return (master[0].postFader, master[1].postFader)
    }
}

public enum VUDecoder {

    static let normalizeFactor = 0.004167508166392142

    /// Decode a `VU2` base64 body into a typed frame. Returns `nil` on malformed input.
    public static func decode(base64 body: String) -> VUFrame? {
        guard let data = Data(base64Encoded: body), data.count >= 8 else { return nil }
        let bytes = [UInt8](data)
        let f = normalizeFactor

        var frame = VUFrame()
        var index = 8   // skip preamble

        // (count byte index, block size)
        func mono(_ start: Int) -> VUFrame.Mono {
            VUFrame.Mono(pre: Double(bytes[start]) * f,
                         post: Double(bytes[start + 1]) * f,
                         postFader: Double(bytes[start + 2]) * f)
        }
        func stereo(_ start: Int) -> VUFrame.Stereo {
            VUFrame.Stereo(postL: Double(bytes[start]) * f,
                           postR: Double(bytes[start + 1]) * f,
                           postFaderL: Double(bytes[start + 2]) * f,
                           postFaderR: Double(bytes[start + 3]) * f)
        }
        func send(_ start: Int) -> VUFrame.Send {
            VUFrame.Send(post: Double(bytes[start]) * f,
                         postFader: Double(bytes[start + 1]) * f)
        }

        // order: input, player, sub, fx, aux, master, line
        let plan: [(count: Int, block: Int, apply: (Int) -> Void)] = [
            (Int(bytes[0]), 6, { frame.input.append(mono($0)) }),
            (Int(bytes[1]), 6, { frame.player.append(mono($0)) }),
            (Int(bytes[2]), 7, { frame.sub.append(stereo($0)) }),
            (Int(bytes[3]), 7, { frame.fx.append(stereo($0)) }),
            (Int(bytes[4]), 5, { frame.aux.append(send($0)) }),
            (Int(bytes[5]), 5, { frame.master.append(send($0)) }),
            (Int(bytes[6]), 6, { frame.line.append(mono($0)) }),
        ]

        for step in plan {
            for _ in 0..<step.count {
                guard index + step.block <= bytes.count else { return frame }
                step.apply(index)
                index += step.block
            }
        }
        return frame
    }
}
