import SwiftUI

@main
struct UI16PhoneApp: App {
    var body: some Scene {
        WindowGroup { RootView().preferredColorScheme(.dark) }
    }
}

struct RootView: View {
    @StateObject private var store = UI16Store()
    @AppStorage("ui16.ip") private var ip = "10.10.2.1"

    var body: some View {
        MixerHome(store: store)
            .task { store.connect(ip: ip) }
    }
}

struct MixerHome: View {
    @ObservedObject var store: UI16Store
    @State private var selectedChannel = 1
    @State private var page = 0
    @State private var showConnection = false

    var selected: UI16State.ChannelState { store.state.channels[selectedChannel, default: .init()] }

    var body: some View {
        VStack(spacing: 0) {
            header
            if page == 0 { mixerPage } else if page == 1 { channelPage } else if page == 2 { busesPage } else { metricsPage }
            bottomBar
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showConnection) { ConnectionView(store: store).presentationDetents([.medium]) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(store.state.connected ? Color.green : Color.red).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text("UI16 CONTROL").font(.headline.bold())
                Text(store.state.connected ? "ONLINE • 10.10.2.1" : "OFFLINE").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showConnection = true } label: { Image(systemName: "gearshape.fill") }
                .buttonStyle(.bordered)
        }.padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var mixerPage: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                LevelCard(title: "MASTER", value: store.state.masterLevel, mute: store.state.masterMuted,
                          onValue: store.setMaster, onMute: { store.setMasterMute(!store.state.masterMuted) })
                MeterCard(title: "OUTPUT", level: store.state.meters["m.0"] ?? 0)
            }.padding(.horizontal, 10)
            channelSelector
            HStack(spacing: 10) {
                VStack(spacing: 7) {
                    Text("CH \(selectedChannel)").font(.caption.bold()).foregroundStyle(.secondary)
                    BigFader(value: Binding(get: { selected.level }, set: { store.setChannelLevel(selectedChannel, value: $0) }))
                    Text(db(selected.level)).font(.caption.monospacedDigit())
                }.frame(width: 82)
                VStack(spacing: 8) {
                    Text(selected.name.isEmpty ? "INPUT \(selectedChannel)" : selected.name).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    ToggleButton(title: "MUTE", active: selected.muted, danger: true) { store.setChannelMute(selectedChannel, muted: !selected.muted) }
                    ToggleButton(title: "SOLO", active: selected.solo) { store.setChannelSolo(selectedChannel, solo: !selected.solo) }
                    HStack { SmallMetric(title: "GAIN", value: db(selected.gain)); SmallMetric(title: "PAN", value: panText(selected.pan)) }
                    HStack { SmallMetric(title: "HPF", value: String(format: "%.0f", selected.highPass)); SmallMetric(title: "AUX", value: "1–4") }
                }
            }.padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
    }

    private var channelPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                channelSelector
                GroupBox("INPUT / PREAMP") {
                    VStack(spacing: 10) {
                        SliderRow(title: "GAIN", value: Binding(get: { selected.gain }, set: { store.setChannelGain(selectedChannel, value: $0) }), valueText: db(selected.gain))
                        SliderRow(title: "HPF", value: Binding(get: { selected.highPass }, set: { store.setChannelLevel(selectedChannel, value: $0) }), valueText: String(format: "%.2f", selected.highPass))
                        HStack { ToggleButton(title: "48V", active: selected.phantom, danger: true) { store.setPhantom(selectedChannel, enabled: !selected.phantom) }; ToggleButton(title: "PHASE", active: selected.phase) { store.setPhase(selectedChannel, enabled: !selected.phase) } }
                    }
                }
                GroupBox("EQ / DYNAMICS") {
                    VStack(spacing: 8) {
                        MetricButton("EQ", key: "i.\(selectedChannel-1).eq")
                        MetricButton("GATE", key: "i.\(selectedChannel-1).gate")
                        MetricButton("COMPRESSOR", key: "i.\(selectedChannel-1).comp")
                    }
                }
                GroupBox("AUX SENDS") {
                    ForEach(1...4, id: \.self) { aux in
                        let current = selected.auxSends[aux] ?? 0
                        SliderRow(title: "AUX \(aux)", value: Binding(get: { current }, set: { store.setAux(selectedChannel, aux: aux, value: $0) }), valueText: db(current))
                    }
                }
            }.padding(10)
        }
    }

    private var busesPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("AUX / FX / MASTER").font(.headline.bold()).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(["AUX 1", "AUX 2", "AUX 3", "AUX 4", "FX 1", "FX 2", "FX 3", "FX 4", "MASTER"], id: \.self) { bus in
                    HStack {
                        Text(bus).font(.subheadline.bold()); Spacer()
                        Text(bus == "MASTER" ? db(store.state.masterLevel) : db(store.state.buses[bus]?.level ?? 0)).monospacedDigit().foregroundStyle(.secondary)
                        Button("MUTE") { store.setRaw("bus.\(bus.lowercased().replacingOccurrences(of: " ", with: ".")).mute", value: "1") }.buttonStyle(.bordered)
                    }.padding(12).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }.padding(10)
        }
    }

    private var metricsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAS AS MÉTRICAS RECEBIDAS").font(.headline.bold())
                Text("A Ui16 envia o estado por mensagens SETD. O app mantém também as métricas que não têm controle visual dedicado.").font(.caption).foregroundStyle(.secondary)
                ForEach(store.state.metrics.keys.sorted(), id: \.self) { key in
                    HStack(spacing: 8) { Text(key).font(.caption.monospaced()); Spacer(); Text(store.state.metrics[key] ?? "").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        .padding(9).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if store.state.metrics.isEmpty { Text("Aguardando estado da mesa…").foregroundStyle(.secondary).padding(.top, 30) }
            }.padding(12)
        }
    }

    private var channelSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { ForEach(1...16, id: \.self) { ch in
                Button { selectedChannel = ch } label: { Text("CH \(ch)").font(.caption.bold()).frame(width: 57, height: 38) }
                    .foregroundStyle(ch == selectedChannel ? .black : .white)
                    .background(ch == selectedChannel ? Color.white : Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }}.padding(.horizontal, 10)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            BottomTab(icon: "slider.horizontal.3", title: "MIX", active: page == 0) { page = 0 }
            BottomTab(icon: "dial.medium", title: "CANAL", active: page == 1) { page = 1 }
            BottomTab(icon: "arrow.up.and.down", title: "BUS", active: page == 2) { page = 2 }
            BottomTab(icon: "waveform.path.ecg", title: "MÉTRICAS", active: page == 3) { page = 3 }
        }.padding(.top, 7).padding(.bottom, 5).background(Color.black)
    }

    private func db(_ v: Double) -> String { String(format: "%+.1f dB", v * 100 - 100) }
    private func panText(_ v: Double) -> String { String(format: "%+.0f", (v * 2 - 1) * 100) }
}

struct LevelCard: View {
    let title: String; let value: Double; let mute: Bool; let onValue: (Double) -> Void; let onMute: () -> Void
    var body: some View { VStack(spacing: 7) { HStack { Text(title).font(.caption.bold()); Spacer(); Text(String(format: "%+.1f", value * 100 - 100)).monospacedDigit() }; HStack { BigFader(value: Binding(get: { value }, set: onValue)).frame(width: 55, height: 105); ToggleButton(title: "MUTE", active: mute, danger: true, action: onMute).frame(maxWidth: .infinity) } }.padding(10).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12)) }
}

struct MeterCard: View { let title: String; let level: Double; var body: some View { VStack(alignment: .leading) { Text(title).font(.caption.bold()); GeometryReader { p in VStack { Spacer(); RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)).frame(width: 14, height: p.size.height); RoundedRectangle(cornerRadius: 4).fill(Color.green).frame(width: 14, height: p.size.height * min(1, max(0, level))) } }.frame(height: 105) } .padding(10).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12)) }

struct BigFader: View { @Binding var value: Double; var body: some View { GeometryReader { p in ZStack(alignment: .bottom) { Capsule().fill(Color.white.opacity(0.12)); Capsule().fill(Color.white).frame(height: max(5, p.size.height * max(0.01, min(1, value)))); Circle().fill(.white).frame(width: 30, height: 30).offset(y: -p.size.height * value + p.size.height / 2 - 15) }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { g in value = min(1, max(0, 1 - g.location.y / p.size.height)) }) } }

struct SliderRow: View { let title: String; @Binding var value: Double; let valueText: String; var body: some View { VStack(alignment: .leading, spacing: 5) { HStack { Text(title).font(.caption.bold()); Spacer(); Text(valueText).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }; Slider(value: $value) } }
struct ToggleButton: View { let title: String; let active: Bool; var danger = false; let action: () -> Void; var body: some View { Button(action: action) { Text(title).font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 42) }.foregroundStyle(active ? .white : (danger ? .red : .white)).background(active ? (danger ? .red : Color.white) : Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10)) } }
struct SmallMetric: View { let title: String; let value: String; var body: some View { VStack { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption.bold().monospacedDigit()) }.frame(maxWidth: .infinity).padding(8).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8)) } }
struct MetricButton: View { let title: String; let key: String; var body: some View { HStack { Text(title).font(.caption.bold()); Spacer(); Text(key).font(.caption2.monospaced()).foregroundStyle(.secondary) }.padding(10).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8)) } }
struct BottomTab: View { let icon: String; let title: String; let active: Bool; let action: () -> Void; var body: some View { Button(action: action) { VStack(spacing: 3) { Image(systemName: icon); Text(title).font(.caption2) }.frame(maxWidth: .infinity) }.foregroundStyle(active ? .white : .secondary) } }

struct ConnectionView: View {
    @ObservedObject var store: UI16Store
    @AppStorage("ui16.ip") private var ip = "10.10.2.1"
    var body: some View { NavigationStack { Form { Section("REDE LOCAL") { TextField("IP da Ui16", text: $ip).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.numbersAndPunctuation) }; Section { Button("CONECTAR") { store.connect(ip: ip) }; Button("DESCONECTAR", role: .destructive) { store.disconnect() } }; Section("STATUS") { Text(status) } }.navigationTitle("Ui16") } }
    private var status: String { switch store.connection { case .disconnected: "Desconectada"; case .connecting: "Conectando…"; case .connected: "Conectada"; case .reconnecting: "Reconectando…"; case .failed(let e): "Falha: \(e)" } }
}
