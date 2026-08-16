import SwiftUI

@main
struct UI16PhoneApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @StateObject private var store = UI16Store()
    @AppStorage("ui16.ip") private var ip = "192.168.1.1"

    var body: some View {
        NavigationStack {
            MixerView(store: store)
        }
        .task {
            store.connect(ip: ip)
        }
    }
}

struct MixerView: View {
    @ObservedObject var store: UI16Store

    @State private var selectedChannel = 1
    @State private var showConnection = false

    var selected: UI16State.ChannelState {
        store.state.channels[selectedChannel, default: .init()]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            master
            channelStrip
            quickChannels
            Divider()
            bottomTabs
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showConnection) {
            ConnectionView(store: store)
                .presentationDetents([.medium])
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.state.connected ? .green : .red)
                .frame(width: 10, height: 10)
            Text("UI16")
                .font(.headline.bold())
            Spacer()
            Text(store.state.connected ? "CONECTADA" : "DESCONECTADA")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Button { showConnection = true } label: {
                Image(systemName: "wifi")
                    .font(.title3.bold())
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var master: some View {
        VStack(spacing: 12) {
            HStack {
                Text("MASTER")
                    .font(.caption.bold())
                Spacer()
                Text(String(format: "%+.1f dB", db(store.state.masterLevel)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                VerticalFader(value: Binding(
                    get: { store.state.masterLevel },
                    set: store.setMaster
                ))
                .frame(width: 54, height: 150)

                Button {
                    store.setMasterMute(!store.state.masterMuted)
                } label: {
                    Text("MUTE")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .foregroundStyle(store.state.masterMuted ? .white : .red)
                .background(store.state.masterMuted ? .red : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(16)
    }

    private var channelStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CANAL \(selectedChannel)")
                    .font(.title3.bold())
                Spacer()
                Text(selected.name.isEmpty ? "Input \(selectedChannel)" : selected.name)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                VerticalFader(value: Binding(
                    get: { selected.level },
                    set: { store.setChannelLevel(selectedChannel, value: $0) }
                ))
                .frame(width: 50, height: 130)

                VStack(spacing: 10) {
                    quickButton(title: "MUTE", destructive: true,
                                active: selected.muted) {
                        store.setChannelMute(selectedChannel, muted: !selected.muted)
                    }
                    quickButton(title: "EQ") { }
                    quickButton(title: "AUX") { }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var quickChannels: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(1...16, id: \.self) { channel in
                    Button {
                        selectedChannel = channel
                    } label: {
                        VStack(spacing: 4) {
                            Text("CH \(channel)")
                                .font(.caption.bold())
                            RoundedRectangle(cornerRadius: 4)
                                .fill(channel == selectedChannel ? Color.white : Color.white.opacity(0.15))
                                .frame(height: 4)
                        }
                        .frame(width: 64, height: 44)
                    }
                    .foregroundStyle(channel == selectedChannel ? .black : .white)
                    .background(channel == selectedChannel ? .white : Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var bottomTabs: some View {
        HStack {
            tab("slider.horizontal.3", "Mixer")
            tab("dial.medium", "Canal")
            tab("waveform.path.ecg", "FX")
            tab("arrow.up.and.down", "Aux")
            tab("rectangle.stack", "Shows")
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func tab(_ icon: String, _ title: String) -> some View {
        Button { } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
    }

    private func quickButton(title: String, destructive: Bool = false, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.bold())
                .frame(width: 92, height: 44)
        }
        .foregroundStyle(active ? .white : (destructive ? .red : .white))
        .background(active ? .red : Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func db(_ normalized: Double) -> Double {
        normalized * 100 - 100
    }
}

struct VerticalFader: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Color.white)
                    .frame(height: max(8, proxy.size.height * max(0.02, min(1, value))))
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    .frame(width: 28, height: 28)
                    .offset(y: -proxy.size.height * max(0.02, min(1, value)) + proxy.size.height / 2 - 14)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let normalized = 1 - drag.location.y / proxy.size.height
                        value = min(1, max(0, normalized))
                    }
            )
        }
    }
}

struct ConnectionView: View {
    @ObservedObject var store: UI16Store
    @AppStorage("ui16.ip") private var ip = "192.168.1.1"

    var body: some View {
        NavigationStack {
            Form {
                Section("Mesa") {
                    TextField("IP da Ui16", text: $ip)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                }
                Section {
                    Button("Conectar") { store.connect(ip: ip) }
                    Button("Desconectar", role: .destructive) { store.disconnect() }
                }
                Section("Status") {
                    Text(statusText)
                }
            }
            .navigationTitle("Conexão")
        }
    }

    private var statusText: String {
        switch store.connection {
        case .disconnected: "Desconectada"
        case .connecting: "Conectando…"
        case .connected: "Conectada"
        case .reconnecting: "Reconectando…"
        case .failed(let message): "Falha: \(message)"
        }
    }
}
