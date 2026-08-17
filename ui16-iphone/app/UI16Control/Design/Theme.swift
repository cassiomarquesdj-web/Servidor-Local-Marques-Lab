import SwiftUI

/// Visual language for the console.
///
/// Target is an iPhone Pro Max held in one hand, in the dark, mid-show. Everything here is
/// tuned for that: near-black ground so meters and state colours carry the signal, condensed
/// numeric type that stays legible at a glance, and touch targets sized for a thumb rather
/// than a cursor.
enum Theme {

    // MARK: Ground
    /// Page background — deep, slightly blue-black, so panels read as lit surfaces above it.
    static let bg = Color(red: 0.02, green: 0.022, blue: 0.028)
    /// Panel surface.
    static let surface = Color(red: 0.055, green: 0.060, blue: 0.072)
    /// Raised control surface (buttons, wells).
    static let surfaceHigh = Color(red: 0.098, green: 0.105, blue: 0.125)
    /// Recessed well (meter tracks, fader slots).
    static let well = Color(red: 0.012, green: 0.014, blue: 0.018)
    static let stroke = Color.white.opacity(0.085)
    static let strokeStrong = Color.white.opacity(0.16)

    // MARK: Text
    static let text = Color(white: 0.97)
    static let textDim = Color(white: 0.56)
    static let textFaint = Color(white: 0.34)

    // MARK: State
    /// Primary accent — selection, active values, the player.
    static let accent = Color(red: 0.16, green: 0.72, blue: 1.00)
    static let accentDim = Color(red: 0.10, green: 0.42, blue: 0.60)
    /// Signal present / online / safe.
    static let ok = Color(red: 0.20, green: 0.82, blue: 0.42)
    /// Mute / danger / offline.
    static let danger = Color(red: 1.00, green: 0.24, blue: 0.27)
    /// Solo / caution.
    static let solo = Color(red: 1.00, green: 0.76, blue: 0.13)
    /// Hot level.
    static let hot = Color(red: 1.00, green: 0.50, blue: 0.13)

    /// Backwards-compatible alias used across older views.
    static let mute = danger

    // MARK: Metering
    /// Colour of a meter segment at a given position (0 = bottom of scale, 1 = top).
    static func meterColor(at position: Double) -> Color {
        switch position {
        case ..<0.62: return ok
        case ..<0.80: return Color(red: 0.72, green: 0.86, blue: 0.22)
        case ..<0.90: return solo
        case ..<0.96: return hot
        default: return danger
        }
    }

    // MARK: Metrics
    /// Apple's HIG floor. Nothing interactive goes below this.
    static let tapMin: CGFloat = 44
    /// Critical live controls (mute, solo, transport).
    static let tapBig: CGFloat = 56
    static let radius: CGFloat = 10
    static let radiusSmall: CGFloat = 7
    /// Panels use a restrained corner radius — gear, not app chrome.
    static let radiusPanel: CGFloat = 12

    // MARK: Type
    /// Section labels: small, condensed, wide-tracked.
    static let label = Font.system(size: 10, weight: .bold).width(.condensed)
    /// Numeric readouts.
    static func readout(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold).monospacedDigit()
    }
    /// Big numeric readouts (dB values that must be read at arm's length).
    static func bigReadout(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .heavy).monospacedDigit()
    }
    static let title = Font.system(size: 17, weight: .heavy)
    static let panelTitle = Font.system(size: 11, weight: .heavy).width(.condensed)
}

/// Standard panel: a lit surface with a hairline edge. Deliberately low-radius so the app
/// reads as equipment rather than as a settings form.
struct Panel<Content: View>: View {
    var padding: CGFloat = 12
    var content: () -> Content

    init(padding: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

/// A panel with a header strip, used for the main sections.
struct SectionPanel<Content: View>: View {
    let title: String
    var accessory: AnyView? = nil
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        Panel(padding: padding) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(Theme.panelTitle)
                        .tracking(0.8)
                        .foregroundStyle(Theme.textDim)
                    Spacer(minLength: 4)
                    if let accessory { accessory }
                }
                content()
            }
        }
    }
}

extension View {
    /// Short haptic tap — confirms a command left the device when the operator can't
    /// watch the screen.
    func hapticTap(_ style: HapticStyle = .medium) {
        #if canImport(UIKit)
        switch style {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
        #endif
    }
}

enum HapticStyle { case light, medium, heavy }
