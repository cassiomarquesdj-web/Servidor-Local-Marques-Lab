import SwiftUI
import UI16Controller

/// A vertical console fader.
///
/// Dragging is **relative**: the value moves by the drag delta from where the finger
/// landed, so touching the fader never makes the level jump to the touch point. That
/// matters live — a stray tap can't slam a channel to full.
struct Fader: View {
    @Binding var value: Double
    var meter: Double? = nil
    var tint: Color = Theme.accent
    var onCommit: (() -> Void)? = nil

    @State private var dragStart: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let capH: CGFloat = 34

            ZStack(alignment: .bottom) {
                // track
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1)
                    )

                // live meter behind the fill
                if let meter {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.meterGradient)
                        .frame(height: max(0, min(1, meter)) * (h - 4))
                        .padding(.horizontal, 7)
                        .padding(.bottom, 2)
                        .opacity(0.9)
                        .animation(.linear(duration: 0.06), value: meter)
                }

                // fader position fill
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.30))
                    .frame(height: position(h))

                // cap
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.surfaceHigh, Color.black.opacity(0.9)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(tint.opacity(0.85), lineWidth: 1.5)
                    )
                    .overlay(
                        Rectangle().fill(tint).frame(height: 2).padding(.horizontal, 6)
                    )
                    .frame(height: capH)
                    .offset(y: -(position(h) - capH / 2).clamped(0, h - capH))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = value }
                        // relative: translate the drag distance into a value delta
                        let delta = -g.translation.height / max(1, h - capH)
                        value = (start + Double(delta)).clamped(0, 1)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onCommit?()
                    }
            )
        }
    }

    private func position(_ h: CGFloat) -> CGFloat {
        max(0, min(1, CGFloat(value))) * h
    }
}

/// A horizontal meter bar (used where a vertical fader isn't present).
struct MeterBar: View {
    var level: Double
    var vertical = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: vertical ? .bottom : .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.6))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.meterGradient)
                    .frame(
                        width: vertical ? nil : geo.size.width * clamped(level),
                        height: vertical ? geo.size.height * clamped(level) : nil
                    )
                    .animation(.linear(duration: 0.06), value: level)
            }
        }
    }

    private func clamped(_ v: Double) -> CGFloat { CGFloat(max(0, min(1, v))) }
}

/// A large, unmistakable action button — used for MUTE / SOLO / 48V.
struct ConsoleButton: View {
    let title: String
    var subtitle: String? = nil
    let isOn: Bool
    var onColor: Color = Theme.accent
    var height: CGFloat = Theme.tapBig
    let action: () -> Void

    var body: some View {
        Button {
            action()
            hapticTap()
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                if let subtitle {
                    Text(subtitle).font(.system(size: 10, weight: .semibold))
                        .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(isOn ? Color.black : Theme.text)
            .background(isOn ? onColor : Theme.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .stroke(isOn ? onColor : Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A labelled horizontal parameter slider with a live value readout.
struct ParamSlider: View {
    let title: String
    @Binding var value: Double
    var readout: String
    var onCommit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Theme.label).foregroundStyle(Theme.textDim)
                Spacer()
                Text(readout).font(Theme.value).foregroundStyle(Theme.text)
            }
            Slider(value: $value, in: 0...1) { editing in
                if !editing { onCommit?() }
            }
            .tint(Theme.accent)
        }
    }
}

extension Comparable {
    func clamped(_ low: Self, _ high: Self) -> Self { min(max(self, low), high) }
}
