import SwiftUI
import UI16Controller

@main
struct UI16ControlApp: App {
    @StateObject private var store = UI16Store()
    @AppStorage("ui16.host") private var host = "10.10.2.1"
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(store: store, host: $host)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { _, phase in
            // Reconnect on foreground; iOS suspends sockets in the background.
            switch phase {
            case .active: store.connect(host: host)
            case .background: store.disconnect()
            default: break
            }
        }
    }
}

struct RootView: View {
    @ObservedObject var store: UI16Store
    @Binding var host: String

    var body: some View {
        MixerView(store: store, host: $host)
            .task {
                // Keep the screen awake — the operator needs the console visible mid-show.
                #if canImport(UIKit)
                UIApplication.shared.isIdleTimerDisabled = true
                #endif
                store.connect(host: host)
            }
    }
}
