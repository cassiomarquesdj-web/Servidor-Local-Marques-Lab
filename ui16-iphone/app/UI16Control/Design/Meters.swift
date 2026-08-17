import SwiftUI
import UI16Controller

/// LED-style segmented meter.
///
/// Segments rather than a continuous bar because that is how console metering reads: the
/// operator judges level by *how many* segments are lit and *what colour* the top one is,
/// which is far faster than reading a smooth gradient at arm's length.
///
/// The scale is in dB, not linear amplitude — a linear bar spends most of its length on
/// levels nobody cares about and squashes the useful −20…0 dB region into a sliver.
struct SegmentedMeter: View {
    /// Linear level, `0...1`.
    var level: Double
    var orientation: Axis = .vertical
    var segments: Int = 22
    var segmentSpacing: CGFloat = 1.5
    /// Peak-hold marker position, `0...1` on the dB scale.
    var peak: Double? = nil

    /// Meter floor. Below this nothing lights.
    private let floorDB: Double = -60

    /// Position on the dB scale, `0...1`.
    private var scalePosition: Double {
        let db = FaderMath.vuValueToDB(min(max(level, 0), 1))
        guard db > floorDB else { return 0 }
        return min(max((db - floorDB) / (0 - floorDB), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let lit = Int((Double(segments) * scalePosition).rounded())
            let peakIndex = peak.map { Int((Double(segments) * $0).rounded()) }

            // Unlit segments are neutral, not a dim tint of their own colour: tinted
            // "off" segments read as a permanently hot meter out of the corner of the eye.
            let stack = (0..<segments).map { index -> (Int, Color) in
                let position = Double(index) / Double(max(segments - 1, 1))
                let isLit = index < lit
                let isPeak = peakIndex == index
                if isLit { return (index, Theme.meterColor(at: position)) }
                if isPeak { return (index, Theme.meterColor(at: position).opacity(0.7)) }
                return (index, Color(white: 0.13))
            }

            if orientation == .vertical {
                VStack(spacing: segmentSpacing) {
                    ForEach(stack.reversed(), id: \.0) { _, color in
                        RoundedRectangle(cornerRadius: 1).fill(color)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            } else {
                HStack(spacing: segmentSpacing) {
                    ForEach(stack, id: \.0) { _, color in
                        RoundedRectangle(cornerRadius: 1).fill(color)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .animation(.linear(duration: 0.05), value: level)
    }
}

/// Stereo master meter with a printed dB scale, the way a console front panel labels it.
struct StereoMeterWithScale: View {
    var left: Double
    var right: Double
    var showScale: Bool = true

    private let marks: [Int] = [-60, -48, -36, -24, -12, -6, 0]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("L").font(Theme.label).foregroundStyle(Theme.textFaint).frame(width: 9)
                SegmentedMeter(level: left, orientation: .horizontal, segments: 28)
                    .frame(height: 11)
            }
            HStack(spacing: 6) {
                Text("R").font(Theme.label).foregroundStyle(Theme.textFaint).frame(width: 9)
                SegmentedMeter(level: right, orientation: .horizontal, segments: 28)
                    .frame(height: 11)
            }
            if showScale {
                HStack(spacing: 0) {
                    Spacer().frame(width: 15)
                    ForEach(marks, id: \.self) { mark in
                        Text("\(mark)")
                            .font(.system(size: 8, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.textFaint)
                            .frame(maxWidth: .infinity,
                                   alignment: mark == marks.first ? .leading
                                            : (mark == marks.last ? .trailing : .center))
                    }
                }
            }
        }
    }
}

/// Vertical fader built like a console fader: a recessed slot, a travelling cap with a
/// centre line, and relative dragging.
///
/// Relative dragging matters live — touching the fader must never make the level jump to
/// the finger, which a stray tap on an absolute fader would do.
struct ConsoleFader: View {
    @Binding var value: Double
    var tint: Color = Theme.accent
    var showTicks: Bool = true
    var onCommit: (() -> Void)? = nil

    @State private var dragAnchor: Double? = nil

    private let capHeight: CGFloat = 28

    private var tickColumn: some View {
        VStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { _ in
                Rectangle().fill(Theme.stroke).frame(width: 5, height: 1)
                Spacer(minLength: 0)
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let travel = max(h - capHeight, 1)
            let capY = travel * (1 - CGFloat(min(max(value, 0), 1)))

            ZStack(alignment: .top) {
                // slot
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.well)
                        .frame(width: 9)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.black.opacity(0.6), lineWidth: 1)
                        )
                    Spacer()
                }

                // travelled portion
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tint.opacity(0.6))
                            .frame(width: 9, height: max(0, h - capY - capHeight / 2))
                        Spacer()
                    }
                }

                if showTicks {
                    // Scale marks on both flanks, like a printed fader scale.
                    HStack {
                        tickColumn
                        Spacer()
                        tickColumn
                    }
                }

                // cap
                FaderCap(tint: tint)
                    .frame(height: capHeight)
                    .offset(y: capY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let anchor = dragAnchor ?? value
                        if dragAnchor == nil { dragAnchor = value }
                        let delta = -g.translation.height / travel
                        value = min(max(anchor + Double(delta), 0), 1)
                    }
                    .onEnded { _ in
                        dragAnchor = nil
                        onCommit?()
                    }
            )
        }
    }
}

private struct FaderCap: View {
    let tint: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color(white: 0.26), Color(white: 0.09)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.black.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            Rectangle()
                .fill(tint)
                .frame(height: 2)
                .shadow(color: tint.opacity(0.8), radius: 3)
                .padding(.horizontal, 5)
        }
    }
}

/// Rotary control. Used where a console would use a pot — gain, pan, EQ, sends — because
/// knobs pack far more controls into a phone screen than sliders do.
struct Knob: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var tint: Color = Theme.accent
    /// Draw the indicator from the centre (pan, EQ gain) instead of from the minimum.
    var bipolar: Bool = false
    var size: CGFloat = 54
    var onCommit: (() -> Void)? = nil

    @State private var dragAnchor: Double? = nil

    private var normalized: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// Sweep from 135° to 405° (i.e. 270° of travel), the standard pot arc.
    private let startAngle: Double = 135
    private let sweep: Double = 270

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: [Color(white: 0.19), Color(white: 0.07)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(Circle().stroke(Color.black.opacity(0.75), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)

            // track
            Circle()
                .trim(from: 0, to: sweep / 360)
                .stroke(Theme.well, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(startAngle))
                .padding(2.5)

            // value arc
            Circle()
                .trim(from: bipolar ? min(0.5, normalized) * (sweep / 360)
                                    : 0,
                      to: bipolar ? max(0.5, normalized) * (sweep / 360)
                                  : normalized * (sweep / 360))
                .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(startAngle))
                .padding(2.5)
                .shadow(color: tint.opacity(0.5), radius: 3)

            // pointer
            GeometryReader { geo in
                let r = min(geo.size.width, geo.size.height) / 2
                Rectangle()
                    .fill(Theme.text)
                    .frame(width: 2, height: r * 0.46)
                    .offset(y: -r * 0.40)
                    .rotationEffect(.degrees(startAngle + 90 + normalized * sweep))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            // Vertical drag, like a real pot under a finger. Absolute rotation tracking
            // would need the finger to orbit the knob, which is unusable on a phone.
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let anchor = dragAnchor ?? value
                    if dragAnchor == nil { dragAnchor = value }
                    let span = range.upperBound - range.lowerBound
                    let delta = -Double(g.translation.height) / 140 * span
                    value = min(max(anchor + delta, range.lowerBound), range.upperBound)
                }
                .onEnded { _ in
                    dragAnchor = nil
                    onCommit?()
                }
        )
        .animation(.interactiveSpring(response: 0.15), value: value)
    }
}

/// Labelled knob with a numeric readout under it.
struct KnobControl: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var readout: String
    var tint: Color = Theme.accent
    var bipolar: Bool = false
    var size: CGFloat = 54

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
            Knob(value: $value, range: range, tint: tint, bipolar: bipolar, size: size)
            Text(readout)
                .font(Theme.readout(11))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Thin meter used in dense lists (diagnostics, bus rows) where a full segmented meter
/// would be too tall. Same dB scaling as `SegmentedMeter`, fewer segments.
struct MeterBar: View {
    var level: Double
    var vertical = true

    var body: some View {
        SegmentedMeter(level: level,
                       orientation: vertical ? .vertical : .horizontal,
                       segments: vertical ? 14 : 20,
                       segmentSpacing: 1)
    }
}
