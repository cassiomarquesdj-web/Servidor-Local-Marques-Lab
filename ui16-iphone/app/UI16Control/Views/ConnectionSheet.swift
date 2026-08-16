import SwiftUI
import UI16Controller

/// Connection setup: manual IP plus the known factory addresses and a Bonjour scan.
struct ConnectionSheet: View {
    @ObservedObject var store: UI16Store
    @Binding var host: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = MixerBrowser()

    /// Factory defaults for the Ui series: the mixer's own Wi-Fi AP and typical
    /// wired/DHCP addresses. Confirmed against Soundcraft Ui documentation.
    private let presets = ["10.10.2.1", "10.10.1.1", "192.168.1.1"]

    var body: some View {
        NavigationStack {
            Form {
                Section("ENDEREÇO DA MESA") {
                    TextField("IP da Ui16", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))

                    Button {
                        store.connect(host: host)
                        dismiss()
                    } label: {
                        Label("CONECTAR", systemImage: "bolt.horizontal.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                    }

                    Button(role: .destructive) {
                        store.disconnect()
                    } label: {
                        Label("DESCONECTAR", systemImage: "xmark.circle.fill")
                    }
                }

                Section("ENDEREÇOS PADRÃO") {
                    ForEach(presets, id: \.self) { ip in
                        Button {
                            host = ip
                            store.connect(host: ip)
                            dismiss()
                        } label: {
                            HStack {
                                Text(ip).font(.system(.body, design: .monospaced))
                                Spacer()
                                if ip == host { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                    }
                }

                Section {
                    if browser.found.isEmpty {
                        HStack {
                            Text(browser.isScanning ? "Procurando…" : "Nenhuma mesa encontrada")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if browser.isScanning { ProgressView() }
                        }
                    } else {
                        ForEach(browser.found, id: \.self) { name in
                            Button(name) { }
                                .disabled(true)
                        }
                    }
                    Button("PROCURAR NA REDE") { browser.start() }
                } header: {
                    Text("DESCOBERTA AUTOMÁTICA")
                } footer: {
                    Text("A Ui16 nem sempre anuncia um serviço Bonjour. Se nada aparecer, use o IP mostrado no painel da mesa ou um dos endereços padrão.")
                }

                Section("STATUS") {
                    LabeledContent("Conexão", value: statusText)
                    LabeledContent("Mensagens", value: "\(store.state.messageCount)")
                    LabeledContent("VU frames", value: "\(store.state.vuFrameCount)")
                }
            }
            .navigationTitle("Conexão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }

    private var statusText: String {
        switch store.connection {
        case .disconnected: return "Desconectado"
        case .connecting: return "Conectando…"
        case .connected: return "Conectado"
        case .reconnecting: return "Reconectando…"
        case .failed(let e): return "Falha: \(e)"
        }
    }
}

/// Bonjour scan for HTTP services on the local network. The Ui series does not reliably
/// advertise itself, so this is a convenience on top of manual entry — never the only path.
@MainActor
final class MixerBrowser: NSObject, ObservableObject {
    @Published var found: [String] = []
    @Published var isScanning = false

    private var browser: NetServiceBrowser?

    func start() {
        stop()
        found = []
        isScanning = true
        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: "_http._tcp.", inDomain: "local.")
        browser = b
        Task {
            try? await Task.sleep(for: .seconds(6))
            self.stop()
        }
    }

    func stop() {
        browser?.stop()
        browser = nil
        isScanning = false
    }
}

extension MixerBrowser: NetServiceBrowserDelegate {
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser,
                                       didFind service: NetService,
                                       moreComing: Bool) {
        let name = service.name
        Task { @MainActor in
            if !self.found.contains(name) { self.found.append(name) }
        }
    }
}
