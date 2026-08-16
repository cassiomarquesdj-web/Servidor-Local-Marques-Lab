import SwiftUI
import UI16Controller

/// Root live-operation screen: status bar, channel strip, master, and tabs.
struct MixerView: View {
    @ObservedObject var store: UI16Store
    @Binding var host: String

    @State private var selected = ChannelRef(.input, 1)
    @State private var tab: Tab = .mix
    @State private var showSettings = false

    enum Tab: String, CaseIterable {
        case mix, channel, buses, diagnostics
        var label: String {
            switch self {
            case .mix: return "MIXER"
            case .channel: return "CANAL"
            case .buses: return "AUX/FX"
            case .diagnostics: return "DIAG"
            }
        }
        var icon: String {
            switch self {
            case .mix: return "slider.vertical.3"
            case .channel: return "dial.high.fill"
            case .buses: return "arrow.triangle.branch"
            case .diagnostics: return "waveform.path.ecg"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusBar(store: store, host: host) { showSettings = true }

            // Connection loss must be unmistakable — it sits in the layout flow so it
            // never covers the status header.
            if !store.state.connected {
                ConnectionBanner(state: store.connection)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .background(Color.black)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Group {
                switch tab {
                case .mix:
                    MixPage(store: store, selected: $selected)
                case .channel:
                    ChannelPage(store: store, ref: selected, onSelect: { selected = $0 })
                case .buses:
                    BusesPage(store: store)
                case .diagnostics:
                    DiagnosticsPage(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(tab: $tab)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            ConnectionSheet(store: store, host: $host)
        }
        .animation(.easeOut(duration: 0.2), value: store.state.connected)
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @ObservedObject var store: UI16Store
    let host: String
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.state.connected ? Theme.ok : Theme.mute)
                .frame(width: 10, height: 10)
                .shadow(color: store.state.connected ? Theme.ok : Theme.mute, radius: 4)

            VStack(alignment: .leading, spacing: 0) {
                Text("UI16 CONTROL").font(Theme.title)
                Text(store.state.connected ? "ONLINE · \(host)" : statusText)
                    .font(Theme.label)
                    .foregroundStyle(Theme.textDim)
            }

            Spacer()

            // Master meter always visible, even on other pages.
            if let m = store.state.vu.masterPostFader {
                HStack(spacing: 3) {
                    MeterBar(level: m.l).frame(width: 6)
                    MeterBar(level: m.r).frame(width: 6)
                }
                .frame(height: 30)
            }

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: Theme.tapMin, height: Theme.tapMin)
                    .foregroundStyle(Theme.text)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.black)
    }

    private var statusText: String {
        switch store.connection {
        case .disconnected: return "DESCONECTADO"
        case .connecting: return "CONECTANDO…"
        case .connected: return "ONLINE"
        case .reconnecting: return "RECONECTANDO…"
        case .failed(let e): return "FALHA: \(e.uppercased())"
        }
    }
}

struct ConnectionBanner: View {
    let state: UI16Connection.State
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
            Text(text).font(.system(size: 13, weight: .bold))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Theme.mute)
        .foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    private var text: String {
        switch state {
        case .reconnecting: return "SEM CONEXÃO — RECONECTANDO"
        case .connecting: return "CONECTANDO À MESA…"
        case .failed(let e): return "FALHA: \(e)"
        default: return "SEM CONEXÃO COM A MESA"
        }
    }
}

// MARK: - Tab bar

struct TabBar: View {
    @Binding var tab: MixerView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MixerView.Tab.allCases, id: \.self) { t in
                Button {
                    tab = t
                    hapticTap()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 17, weight: .semibold))
                        Text(t.label).font(.system(size: 10, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.tapMin)
                    .foregroundStyle(tab == t ? Theme.accent : Theme.textDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
        .background(Color.black)
    }
}
