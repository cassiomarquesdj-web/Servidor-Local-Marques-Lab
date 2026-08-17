import SwiftUI
import UI16Controller

/// Per-channel detail, organised in tabs.
///
/// Tabs rather than one long scroll: on a phone a giant vertical page buries everything
/// below the fold, and mid-show the operator needs a parameter in one tap, not after
/// hunting through a scroll.
struct ChannelPage: View {
    @ObservedObject var store: UI16Store
    let ref: ChannelRef
    let onSelect: (ChannelRef) -> Void

    @State private var tab: Tab = .preamp
    @State private var renaming = false
    @State private var draftName = ""

    enum Tab: String, CaseIterable, Identifiable {
        case preamp, eq, dyn, sends, out
        var id: String { rawValue }
        var label: String {
            switch self {
            case .preamp: return "PREAMP"
            case .eq: return "EQ"
            case .dyn: return "DYN"
            case .sends: return "SENDS"
            case .out: return "OUT"
            }
        }
    }

    private var strip: StripState { store.state.strip(ref) }

    var body: some View {
        VStack(spacing: 8) {
            channelBar
            TabSelector(items: Tab.allCases, selection: $tab, label: { $0.label })
                .padding(.horizontal, 10)

            ScrollView {
                VStack(spacing: 10) {
                    switch tab {
                    case .preamp: preampTab
                    case .eq: ProcessingTab(store: store, ref: ref, group: .eq)
                    case .dyn: ProcessingTab(store: store, ref: ref, group: .dyn)
                    case .sends: SendsTab(store: store, ref: ref)
                    case .out: outTab
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 6)
        .alert("Nome do canal", isPresented: $renaming) {
            TextField(ref.defaultLabel, text: $draftName)
            Button("Salvar") { store.setName(ref, draftName) }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("O nome é gravado na mesa e aparece para todos os clientes.")
        }
    }

    // MARK: Channel selector bar

    private var channelBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.state.label(ref))
                        .font(.system(size: 17, weight: .heavy)).lineLimit(1)
                    Text("\(ref.kind.displayName) \(ref.number) · \(ref.address)")
                        .font(Theme.label).foregroundStyle(Theme.textFaint)
                }
                Spacer()
                Button {
                    draftName = strip.name
                    renaming = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(Theme.accent)
                        .background(Theme.surfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                Text(FaderMath.dbString(strip.level))
                    .font(Theme.bigReadout(17))
                    .foregroundStyle(strip.muted ? Theme.danger : Theme.accent)
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(UI16Model.inputSources) { item in
                        Button {
                            onSelect(item)
                            hapticTap(.light)
                        } label: {
                            Text(shortLabel(item))
                                .font(.system(size: 11, weight: .heavy))
                                .padding(.horizontal, 11)
                                .frame(height: 36)
                                .foregroundStyle(item == ref ? .black : Theme.textDim)
                                .background(item == ref ? Theme.accent : Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private func shortLabel(_ r: ChannelRef) -> String {
        switch r.kind {
        case .input: return String(format: "%02d", r.number)
        case .line: return "L\(r.number)"
        case .player: return "P\(r.number)"
        default: return r.defaultLabel
        }
    }

    // MARK: PREAMP

    private var preampTab: some View {
        VStack(spacing: 10) {
            SectionPanel(title: "PREAMP") {
                HStack(alignment: .top, spacing: 14) {
                    if ref.kind == .input {
                        KnobControl(title: "GAIN",
                                    value: Binding(get: { strip.gain },
                                                   set: { store.setGain(ref, $0) }),
                                    readout: String(format: "%+.1f dB",
                                                    FaderMath.gainValueToDB(strip.gain)),
                                    size: 62)
                    }
                    KnobControl(title: "PAN",
                                value: Binding(get: { strip.pan },
                                               set: { store.setPan(ref, $0) }),
                                readout: panText(strip.pan),
                                bipolar: true, size: 62)
                    Spacer(minLength: 0)
                    if ref.kind == .input {
                        VStack(spacing: 6) {
                            ConsoleButton(title: "48V", subtitle: strip.phantom ? "ON" : "OFF",
                                          isOn: strip.phantom, onColor: Theme.danger,
                                          height: 46, compact: true,
                                          enabled: store.state.connected) {
                                store.setPhantom(ref, !strip.phantom)
                            }
                            PhaseInlineButton(store: store, ref: ref)
                        }
                        .frame(width: 104)
                    }
                }
            }

            SectionPanel(title: "FADER") {
                HStack(spacing: 14) {
                    ConsoleFader(value: Binding(get: { strip.level },
                                                set: { store.setLevel(ref, $0) }),
                                 tint: strip.muted ? Theme.danger : Theme.accent)
                        .frame(width: 44, height: 120)
                    SegmentedMeter(level: store.state.vu.postFader(for: ref) ?? 0,
                                   orientation: .vertical)
                        .frame(width: 12, height: 120)
                    VStack(spacing: 8) {
                        ConsoleButton(title: "MUTE", isOn: strip.muted, onColor: Theme.danger,
                                      height: 52, enabled: store.state.connected) {
                            store.setMute(ref, !strip.muted)
                        }
                        ConsoleButton(title: "SOLO", isOn: strip.solo, onColor: Theme.solo,
                                      height: 52, enabled: store.state.connected) {
                            store.setSolo(ref, !strip.solo)
                        }
                    }
                }
            }
        }
    }

    // MARK: OUT

    private var outTab: some View {
        SectionPanel(title: "SAÍDA / ESTADO") {
            VStack(spacing: 8) {
                infoRow("NÍVEL", FaderMath.dbString(strip.level))
                infoRow("PAN", panText(strip.pan))
                infoRow("MUTE", strip.muted ? "ATIVO" : "—",
                        color: strip.muted ? Theme.danger : Theme.textDim)
                infoRow("SOLO", strip.solo ? "ATIVO" : "—",
                        color: strip.solo ? Theme.solo : Theme.textDim)
                if ref.kind == .input {
                    infoRow("48V", strip.phantom ? "LIGADO" : "—",
                            color: strip.phantom ? Theme.danger : Theme.textDim)
                    infoRow("GANHO", String(format: "%+.1f dB", FaderMath.gainValueToDB(strip.gain)))
                }
                infoRow("ENDEREÇO", ref.address, color: Theme.textDim)
            }
        }
    }

    private func infoRow(_ title: String, _ value: String,
                         color: Color = Theme.accent) -> some View {
        HStack {
            Text(title).font(Theme.label).foregroundStyle(Theme.textDim)
            Spacer()
            Text(value).font(Theme.readout(13)).foregroundStyle(color)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
    }

    private func panText(_ v: Double) -> String {
        let p = (v * 2 - 1) * 100
        if abs(p) < 1 { return "C" }
        return p < 0 ? String(format: "L %.0f", -p) : String(format: "R %.0f", p)
    }
}

/// PHASE for a mixer channel, inline in the preamp section.
///
/// Only transmits once the mixer has reported a real polarity address; otherwise it is
/// disabled and says so. The project does not invent protocol.
struct PhaseInlineButton: View {
    @ObservedObject var store: UI16Store
    let ref: ChannelRef

    private var availability: PhaseAvailabilityShim {
        PhaseAvailabilityShim(store: store, ref: ref)
    }

    var body: some View {
        let a = availability
        ConsoleButton(title: "PHASE",
                      subtitle: a.available ? (a.inverted ? "Ø INV" : "NORMAL") : "N/D",
                      isOn: a.available && a.inverted,
                      onColor: Theme.solo, height: 46, compact: true,
                      enabled: a.available && store.state.connected) {
            a.toggle()
        }
    }
}

/// Bridges the phase resolution logic into the technical mixer without pulling ParedaoCore
/// into this file's dependencies.
@MainActor
struct PhaseAvailabilityShim {
    let store: UI16Store
    let ref: ChannelRef

    private var key: String? {
        let prefix = ref.address + "."
        let candidates = ["phase", "polarity", "invert", "pol", "phaseinvert"]
        for k in store.state.raw.keys where k.hasPrefix(prefix) {
            if candidates.contains(String(k.dropFirst(prefix.count)).lowercased()) { return k }
        }
        return nil
    }

    var available: Bool { key != nil }
    var inverted: Bool {
        guard let key, let v = store.state.raw[key]?.double else { return false }
        return v != 0
    }
    func toggle() {
        guard let key else { return }
        store.sendRawBool(key, !inverted)
    }
}
