import SwiftUI
import UI16Controller

/// The mixer surface: master section, then channel strips side by side.
///
/// Several strips visible at once is the whole point of a mixer — a stacked list of
/// channels tells the operator nothing about the balance of the mix.
struct MixerPage: View {
    @ObservedObject var store: UI16Store
    @Binding var selected: ChannelRef
    let onOpenChannel: () -> Void

    /// Strip bank shown in the scroller.
    @State private var bank: Bank = .inputs

    enum Bank: String, CaseIterable, Identifiable {
        case inputs, buses
        var id: String { rawValue }
        var label: String { self == .inputs ? "ENTRADAS" : "AUX · FX · SUB" }
        var refs: [ChannelRef] {
            self == .inputs
                ? UI16Model.inputSources
                : UI16Model.auxBuses + UI16Model.fxReturns + UI16Model.subGroups
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                masterSection
                bankPicker
                strips
                quickChannel
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    // MARK: Master

    private var masterSection: some View {
        SectionPanel(title: "MASTER L/R",
                     accessory: AnyView(
                        Text(FaderMath.dbString(store.state.master.level))
                            .font(Theme.bigReadout(18))
                            .foregroundStyle(store.state.master.muted ? Theme.danger : Theme.ok)
                     )) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    StereoMeterWithScale(left: store.state.vu.masterPostFader?.l ?? 0,
                                         right: store.state.vu.masterPostFader?.r ?? 0)

                    HStack(spacing: 6) {
                        ConsoleButton(title: "MUTE", isOn: store.state.master.muted,
                                      onColor: Theme.danger, height: 46, compact: true,
                                      enabled: store.state.connected) {
                            store.setMasterMute(!store.state.master.muted)
                        }
                        ConsoleButton(title: "DIM", isOn: store.state.master.dim,
                                      onColor: Theme.solo, height: 46, compact: true,
                                      enabled: store.state.connected) {
                            store.setMasterDim(!store.state.master.dim)
                        }
                        ConsoleButton(title: "SOLO", isOn: anySolo,
                                      onColor: Theme.solo, height: 46, compact: true,
                                      enabled: store.state.connected && anySolo) {
                            clearAllSolos()
                        }
                        ConsoleButton(title: "FONE", isOn: false,
                                      onColor: Theme.accent, height: 46, compact: true,
                                      enabled: store.state.connected) {
                            showMonitor = true
                        }
                    }
                }

                ConsoleFader(
                    value: Binding(get: { store.state.master.level },
                                   set: { store.setMasterLevel($0) }),
                    tint: store.state.master.muted ? Theme.danger : Theme.ok
                )
                .frame(width: 40, height: 132)
                .disabled(!store.state.connected)
                .opacity(store.state.connected ? 1 : 0.4)
            }
        }
        .sheet(isPresented: $showMonitor) {
            MonitorSheet(store: store)
        }
    }

    @State private var showMonitor = false

    private var anySolo: Bool {
        store.state.strips.values.contains { $0.solo }
    }

    private func clearAllSolos() {
        for ref in UI16Model.allStrips where store.state.strip(ref).solo {
            store.setSolo(ref, false)
        }
    }

    // MARK: Strips

    private var bankPicker: some View {
        TabSelector(items: Bank.allCases, selection: $bank, label: { $0.label }, height: 34)
    }

    private var strips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(bank.refs) { ref in
                    let strip = store.state.strip(ref)
                    ChannelStrip(
                        index: shortIndex(ref),
                        name: store.state.label(ref),
                        level: strip.level,
                        meter: store.state.vu.postFader(for: ref) ?? 0,
                        db: FaderMath.dbString(strip.level),
                        muted: strip.muted,
                        soloed: strip.solo,
                        isSelected: ref == selected,
                        accent: tint(for: ref),
                        onSelect: { selected = ref },
                        onLevel: { store.setLevel(ref, $0) },
                        onMute: { store.setMute(ref, !strip.muted) },
                        onSolo: { store.setSolo(ref, !strip.solo) }
                    )
                    .frame(width: 84)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 310)
    }

    /// Colour-code strip families so the operator can tell inputs from buses at a glance.
    private func tint(for ref: ChannelRef) -> Color {
        switch ref.kind {
        case .input: return Theme.accent
        case .line: return Color(red: 0.55, green: 0.75, blue: 1.0)
        case .player: return Color(red: 0.72, green: 0.60, blue: 1.0)
        case .aux: return Theme.ok
        case .fx: return Color(red: 1.0, green: 0.55, blue: 0.85)
        case .sub: return Theme.solo
        case .vca: return Theme.textDim
        }
    }

    private func shortIndex(_ ref: ChannelRef) -> String {
        switch ref.kind {
        case .input: return String(format: "CH %02d", ref.number)
        case .line: return "LINE \(ref.number)"
        case .player: return "PLAY \(ref.number)"
        case .aux: return "AUX \(ref.number)"
        case .fx: return "FX \(ref.number)"
        case .sub: return "SUB \(ref.number)"
        case .vca: return "VCA \(ref.number)"
        }
    }

    // MARK: Selected channel quick panel

    private var quickChannel: some View {
        let strip = store.state.strip(selected)
        return SectionPanel(title: "\(shortIndex(selected))  ·  \(store.state.label(selected))",
                            accessory: AnyView(
                                Button {
                                    onOpenChannel()
                                    hapticTap(.light)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("ABRIR CANAL").font(.system(size: 10, weight: .heavy))
                                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .heavy))
                                    }
                                    .foregroundStyle(Theme.accent)
                                }
                                .buttonStyle(.plain)
                            )) {
            HStack(spacing: 10) {
                if selected.kind == .input {
                    KnobControl(title: "GAIN",
                                value: Binding(get: { strip.gain },
                                               set: { store.setGain(selected, $0) }),
                                readout: String(format: "%+.1f", FaderMath.gainValueToDB(strip.gain)),
                                size: 48)
                }
                KnobControl(title: "PAN",
                            value: Binding(get: { strip.pan },
                                           set: { store.setPan(selected, $0) }),
                            readout: panText(strip.pan),
                            bipolar: true, size: 48)

                Spacer(minLength: 0)

                VStack(spacing: 6) {
                    ConsoleButton(title: "MUTE", isOn: strip.muted, onColor: Theme.danger,
                                  height: 44, compact: true,
                                  enabled: store.state.connected) {
                        store.setMute(selected, !strip.muted)
                    }
                    ConsoleButton(title: "SOLO", isOn: strip.solo, onColor: Theme.solo,
                                  height: 44, compact: true,
                                  enabled: store.state.connected) {
                        store.setSolo(selected, !strip.solo)
                    }
                }
                .frame(width: 96)

                if selected.kind == .input {
                    ConsoleButton(title: "48V", isOn: strip.phantom, onColor: Theme.danger,
                                  height: 94, compact: true,
                                  enabled: store.state.connected) {
                        store.setPhantom(selected, !strip.phantom)
                    }
                    .frame(width: 62)
                }
            }
        }
    }

    private func panText(_ v: Double) -> String {
        let p = (v * 2 - 1) * 100
        if abs(p) < 1 { return "C" }
        return p < 0 ? String(format: "L%.0f", -p) : String(format: "R%.0f", p)
    }
}

/// Monitor levels (solo bus and headphones) — kept off the main surface because they are
/// set once and rarely touched mid-song.
struct MonitorSheet: View {
    @ObservedObject var store: UI16Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                let solo = store.state.raw[VolumeBus.solo]?.double ?? 0
                let hp = store.state.raw[VolumeBus.headphones(1)]?.double ?? 0

                Panel {
                    VStack(spacing: 16) {
                        ParamSlider(title: "SOLO",
                                    value: Binding(get: { solo },
                                                   set: { store.setSoloVolume($0) }),
                                    readout: FaderMath.dbString(solo))
                        ParamSlider(title: "FONE / MONITOR",
                                    value: Binding(get: { hp },
                                                   set: { store.setHeadphoneVolume(1, $0) }),
                                    readout: FaderMath.dbString(hp))
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Monitoração")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}
