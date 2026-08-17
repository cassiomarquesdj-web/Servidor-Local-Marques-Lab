import SwiftUI
import UI16Controller

/// A console button: rectangular, high contrast, lit when engaged.
///
/// Deliberately not a pill — engaged state is carried by fill and a glow, the way a lit
/// switch cap reads on real gear.
struct ConsoleButton: View {
    let title: String
    var subtitle: String? = nil
    let isOn: Bool
    var onColor: Color = Theme.accent
    var height: CGFloat = Theme.tapBig
    var compact: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            guard enabled else { return }
            action()
            hapticTap()
        } label: {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: compact ? 11 : 13, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .bold))
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(isOn ? .black : (enabled ? Theme.text : Theme.textFaint))
            .background(isOn ? onColor : Theme.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .stroke(isOn ? onColor : Theme.stroke, lineWidth: 1)
            )
            .shadow(color: isOn ? onColor.opacity(0.45) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .animation(.easeOut(duration: 0.12), value: isOn)
    }
}

/// Horizontal tab selector used inside panels (PREAMP / EQ / DYN / SENDS / OUT).
struct TabSelector<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    var height: CGFloat = 40

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                    hapticTap(.light)
                } label: {
                    Text(label(item))
                        .font(.system(size: 11, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .foregroundStyle(selection == item ? .black : Theme.textDim)
                        .background(selection == item ? Theme.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.well)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}

/// A compact horizontal parameter row with a drag-anywhere track.
///
/// The whole track is the target, not a small thumb — a 10pt circle is unusable on a phone
/// in the dark.
struct ParamSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var readout: String
    var tint: Color = Theme.accent
    var bipolar: Bool = false
    var onCommit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(Theme.label).foregroundStyle(Theme.textDim)
                Spacer()
                Text(readout).font(Theme.readout(12)).foregroundStyle(tint)
            }
            SliderTrack(value: $value, range: range, tint: tint,
                        bipolar: bipolar, onCommit: onCommit)
                .frame(height: 26)
        }
    }
}

/// The track itself, reusable where a label is not wanted.
struct SliderTrack: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var tint: Color = Theme.accent
    var bipolar: Bool = false
    var onCommit: (() -> Void)? = nil

    private var normalized: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let x = w * CGFloat(normalized)

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.well)
                    .frame(height: 6)
                    .overlay(Capsule().stroke(Color.black.opacity(0.5), lineWidth: 1).frame(height: 6))

                if bipolar {
                    // fill outward from centre, so 0 reads as "no change"
                    let centre = w / 2
                    Capsule().fill(tint)
                        .frame(width: abs(x - centre), height: 6)
                        .offset(x: min(x, centre))
                } else {
                    Capsule().fill(tint).frame(width: max(0, x), height: 6)
                }

                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.12)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(tint, lineWidth: 1.5))
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .offset(x: min(max(x - 10, 0), w - 20))
            }
            .frame(height: h)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let pos = min(max(g.location.x / w, 0), 1)
                        value = range.lowerBound + Double(pos) * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in onCommit?() }
            )
        }
    }
}

/// A compact channel strip: the core of the technical mixer.
///
/// Everything the operator needs to judge and ride one channel, sized so several fit
/// across a Pro Max screen at once — the point of a mixer is seeing channels side by side.
struct ChannelStrip: View {
    let index: String
    let name: String
    let level: Double
    let meter: Double
    let db: String
    let muted: Bool
    let soloed: Bool
    let isSelected: Bool
    var accent: Color = Theme.accent

    let onSelect: () -> Void
    let onLevel: (Double) -> Void
    let onMute: () -> Void
    let onSolo: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // header
            Button(action: {
                onSelect()
                hapticTap(.light)
            }) {
                VStack(spacing: 1) {
                    Text(index)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(isSelected ? .black : accent)
                    Text(name)
                        .font(.system(size: 8.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isSelected ? .black.opacity(0.75) : Theme.textDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(isSelected ? accent : Theme.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            // fader + meter side by side, like a real strip
            HStack(spacing: 5) {
                ConsoleFader(
                    value: Binding(get: { level }, set: onLevel),
                    tint: muted ? Theme.danger : accent,
                    showTicks: false
                )
                .frame(width: 26)

                SegmentedMeter(level: meter, orientation: .vertical, segments: 18)
                    .frame(width: 8)
            }
            .frame(height: 172)

            Text(db)
                .font(Theme.readout(11))
                .foregroundStyle(muted ? Theme.danger : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 4) {
                stateButton("M", on: muted, color: Theme.danger, action: onMute)
                stateButton("S", on: soloed, color: Theme.solo, action: onSolo)
            }
        }
        .padding(6)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(isSelected ? accent.opacity(0.8) : Theme.stroke,
                        lineWidth: isSelected ? 1.5 : 1)
        )
    }

    private func stateButton(_ text: String, on: Bool, color: Color,
                             action: @escaping () -> Void) -> some View {
        Button {
            action()
            hapticTap()
        } label: {
            Text(text)
                .font(.system(size: 12, weight: .heavy))
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(on ? .black : Theme.textDim)
                .background(on ? color : Theme.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: on ? color.opacity(0.5) : .clear, radius: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Status pill used in headers (ONLINE / OFFLINE / RECONECTANDO).
struct StatusPill: View {
    let text: String
    let color: Color
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color, radius: 3)
            Text(text)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(filled ? .black : color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(filled ? color : color.opacity(0.13))
        .clipShape(Capsule())
    }
}

extension Comparable {
    func clamped(_ low: Self, _ high: Self) -> Self { min(max(self, low), high) }
}
