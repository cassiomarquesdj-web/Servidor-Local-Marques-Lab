import SwiftUI

/// Visual language for the console: dark, high-contrast, readable at arm's length
/// under stage lighting. Sizes are tuned for one-handed operation during a show.
enum Theme {

    // MARK: Colors
    static let bg = Color(red: 0.04, green: 0.05, blue: 0.06)
    static let surface = Color(red: 0.10, green: 0.11, blue: 0.13)
    static let surfaceHigh = Color(red: 0.15, green: 0.16, blue: 0.19)
    static let stroke = Color.white.opacity(0.10)

    static let text = Color.white
    static let textDim = Color.white.opacity(0.55)

    static let accent = Color(red: 0.20, green: 0.78, blue: 1.00)   // cyan — selection
    static let mute = Color(red: 1.00, green: 0.23, blue: 0.25)     // red — mute
    static let solo = Color(red: 1.00, green: 0.78, blue: 0.13)     // amber — solo
    static let ok = Color(red: 0.22, green: 0.85, blue: 0.45)       // green — online

    /// Meter gradient: green -> amber -> red, matching a real console's scale.
    static let meterGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0.16, green: 0.80, blue: 0.40), location: 0.00),
            .init(color: Color(red: 0.16, green: 0.80, blue: 0.40), location: 0.60),
            .init(color: Color(red: 1.00, green: 0.78, blue: 0.13), location: 0.80),
            .init(color: Color(red: 1.00, green: 0.28, blue: 0.24), location: 1.00),
        ],
        startPoint: .bottom, endPoint: .top
    )

    // MARK: Metrics
    /// Minimum touch target. Apple's HIG floor is 44pt; critical live controls use more.
    static let tapMin: CGFloat = 44
    static let tapBig: CGFloat = 56
    static let radius: CGFloat = 12
    static let radiusSmall: CGFloat = 9

    // MARK: Type
    static let label = Font.system(size: 11, weight: .bold).width(.condensed)
    static let value = Font.system(size: 13, weight: .semibold).monospacedDigit()
    static let title = Font.system(size: 17, weight: .heavy)
}

/// Standard panel container.
struct Panel<Content: View>: View {
    var content: () -> Content
    var body: some View {
        content()
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    /// Fires a short haptic tap — confirms a command left the device even when the
    /// operator can't watch the screen.
    func hapticTap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
