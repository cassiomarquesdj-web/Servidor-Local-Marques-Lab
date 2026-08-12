import SwiftUI
import FamilyControls
import ManagedSettings

@main
struct GamblingBlockerApp: App {
    @StateObject private var model = ProtectionModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task { await model.authorize() }
        }
    }
}

@MainActor
final class ProtectionModel: ObservableObject {
    @Published var authorized = false
    @Published var protectionEnabled = false
    @Published var status = "Preparando proteção…"

    private let store = ManagedSettingsStore(named: .gamblingBlocker)

    func authorize() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorized = true
            status = "Proteção pronta"
        } catch {
            status = "Autorização necessária"
        }
    }

    func enableProtection() {
        guard authorized else { return }
        store.webContent.blockedByFilter = .all()
        protectionEnabled = true
        status = "PROTEÇÃO ATIVA"
    }

    func disableProtection() {
        // Deliberately unavailable in the strict product flow.
        status = protectionEnabled ? "PROTEÇÃO ATIVA" : status
    }
}

private extension ManagedSettingsStore.Name {
    static let gamblingBlocker = Self("GamblingBlocker")
}

struct ContentView: View {
    @ObservedObject var model: ProtectionModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: model.protectionEnabled ? "checkmark.shield.fill" : "shield")
                .font(.system(size: 72))
            Text("Gambling Blocker")
                .font(.largeTitle.bold())
            Text(model.status)
                .font(.headline)
            Text("Bloqueio rigoroso de conteúdo de jogos de azar")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(model.protectionEnabled ? "Proteção ativa" : "Ativar proteção") {
                model.enableProtection()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.protectionEnabled || !model.authorized)
        }
        .padding(32)
    }
}
