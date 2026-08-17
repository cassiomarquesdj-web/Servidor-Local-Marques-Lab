import SwiftUI
import UI16Controller

/// The technical Ui16 console.
///
/// Laid out like a digital mixer adapted to a phone rather than a settings screen:
/// a master section on top, several channel strips side by side, and the selected
/// channel's detail in tabs below. The operator sees the mix, not a list.
struct MixerView: View {
    @ObservedObject var store: UI16Store
    @Binding var host: String
    /// Lets the shell switch back to Paredão from the header.
    var onExitToParedao: (() -> Void)? = nil
    /// Now-playing strip, injected by the shell so it sits above this view's tab bar
    /// instead of below it.
    var nowPlaying: AnyView? = nil

    @State private var selected = ChannelRef(.input, 1)
    @State private var tab: Tab = .mixer
    @State private var showSettings = false

    enum Tab: String, CaseIterable, Identifiable {
        case mixer, channel, auxfx, shows, diag
        var id: String { rawValue }
        var label: String {
            switch self {
            case .mixer: return "MIXER"
            case .channel: return "CANAL"
            case .auxfx: return "AUX/FX"
            case .shows: return "SHOWS"
            case .diag: return "DIAG"
            }
        }
        var icon: String {
            switch self {
            case .mixer: return "slider.vertical.3"
            case .channel: return "dial.high.fill"
            case .auxfx: return "arrow.triangle.branch"
            case .shows: return "square.stack.3d.up.fill"
            case .diag: return "waveform.path.ecg"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ConsoleHeader(store: store, host: host,
                          onSettings: { showSettings = true },
                          onExit: onExitToParedao)

            if !store.state.connected {
                ConnectionBanner(state: store.connection)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .background(Color.black)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Group {
                switch tab {
                case .mixer:
                    MixerPage(store: store, selected: $selected,
                              onOpenChannel: { tab = .channel })
                case .channel:
                    ChannelPage(store: store, ref: selected, onSelect: { selected = $0 })
                case .auxfx:
                    AuxFXPage(store: store)
                case .shows:
                    ShowsPage(store: store)
                case .diag:
                    DiagnosticsPage(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let nowPlaying { nowPlaying }

            TechTabBar(tab: $tab)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            ConnectionSheet(store: store, host: $host)
        }
        .animation(.easeOut(duration: 0.18), value: store.state.connected)
    }
}

/// Header for the technical mode. Carries the mode badge so the operator always knows
/// which of the two worlds they are in.
struct ConsoleHeader: View {
    @ObservedObject var store: UI16Store
    let host: String
    let onSettings: () -> Void
    var onExit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let onExit {
                Button {
                    onExit()
                    hapticTap(.light)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .heavy))
                        Text("PAREDÃO").font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(Theme.textDim)
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .background(Theme.surfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Text("UI16")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            StatusPill(text: statusText,
                       color: store.state.connected ? Theme.ok : Theme.danger)

            Spacer(minLength: 0)

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: Theme.tapMin, height: Theme.tapMin)
                    .foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.black)
    }

    private var statusText: String {
        switch store.connection {
        case .disconnected: return "OFFLINE"
        case .connecting: return "CONECTANDO"
        case .connected: return "ONLINE"
        case .reconnecting: return "RECONECTANDO"
        case .failed: return "FALHA"
        }
    }
}

struct ConnectionBanner: View {
    let state: UI16Connection.State
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
            Text(text).font(.system(size: 12, weight: .heavy))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.danger)
        .foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    private var text: String {
        switch state {
        case .reconnecting: return "SEM CONEXÃO — RECONECTANDO"
        case .connecting: return "CONECTANDO À MESA…"
        case .failed(let e): return "FALHA: \(e.uppercased())"
        default: return "SEM CONEXÃO COM A MESA"
        }
    }
}

struct TechTabBar: View {
    @Binding var tab: MixerView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MixerView.Tab.allCases) { t in
                Button {
                    tab = t
                    hapticTap(.light)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 16, weight: .semibold))
                        Text(t.label)
                            .font(.system(size: 9, weight: .heavy))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.tapMin)
                    .foregroundStyle(tab == t ? Theme.accent : Theme.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 5)
        .background(Color.black)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
    }
}
