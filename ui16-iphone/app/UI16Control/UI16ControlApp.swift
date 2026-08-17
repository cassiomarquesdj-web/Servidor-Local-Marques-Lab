import SwiftUI
import UI16Controller

@main
struct UI16ControlApp: App {
    @StateObject private var mixer = UI16Store()
    @StateObject private var paredao: ParedaoStore
    @AppStorage("ui16.host") private var host = "10.10.2.1"
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = UI16Store()
        _mixer = StateObject(wrappedValue: store)
        _paredao = StateObject(wrappedValue: ParedaoStore(mixer: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView(mixer: mixer, paredao: paredao, host: $host)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Reconnect to the mixer on foreground; iOS suspends sockets in the
                // background. Audio is unaffected — the session keeps playing.
                mixer.connect(host: host)
            case .background:
                mixer.disconnect()
                paredao.saveNow()
            default:
                break
            }
        }
    }
}

struct RootView: View {
    @ObservedObject var mixer: UI16Store
    @ObservedObject var paredao: ParedaoStore
    @Binding var host: String

    var body: some View {
        ParedaoShell(paredao: paredao, mixer: mixer, host: $host)
            .task {
                // Keep the screen awake — the console must stay visible mid-show.
                #if canImport(UIKit)
                UIApplication.shared.isIdleTimerDisabled = true
                #endif
                mixer.connect(host: host)
            }
    }
}
