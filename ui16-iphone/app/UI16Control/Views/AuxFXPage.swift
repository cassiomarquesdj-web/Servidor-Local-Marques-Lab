import SwiftUI
import UI16Controller

/// AUX, FX and SUB buses as a card grid.
///
/// A grid rather than a vertical stack: the operator needs to see every monitor mix and
/// effect return at once to judge the show, and stacked full-width rows would push half of
/// them off screen.
struct AuxFXPage: View {
    @ObservedObject var store: UI16Store

    @State private var section: Section = .aux
    @State private var detail: ChannelRef?

    enum Section: String, CaseIterable, Identifiable {
        case aux, fx, sub
        var id: String { rawValue }
        var label: String {
            switch self {
            case .aux: return "AUX SENDS"
            case .fx: return "FX RETURNS"
            case .sub: return "SUB GROUPS"
            }
        }
        var refs: [ChannelRef] {
            switch self {
            case .aux: return UI16Model.auxBuses
            case .fx: return UI16Model.fxReturns
            case .sub: return UI16Model.subGroups
            }
        }
        var tint: Color {
            switch self {
            case .aux: return Theme.ok
            case .fx: return Color(red: 1.0, green: 0.55, blue: 0.85)
            case .sub: return Theme.solo
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            TabSelector(items: Section.allCases, selection: $section, label: { $0.label })
                .padding(.horizontal, 10)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)],
                          spacing: 8) {
                    ForEach(section.refs) { ref in
                        BusCard(store: store, ref: ref, tint: section.tint) {
                            detail = ref
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 6)
        .sheet(item: $detail) { ref in
            BusDetailSheet(store: store, ref: ref)
        }
    }
}

/// One bus as a card: name, meter, level and mute — enough to judge and fix in one tap.
struct BusCard: View {
    @ObservedObject var store: UI16Store
    let ref: ChannelRef
    let tint: Color
    let onOpen: () -> Void

    var body: some View {
        let strip = store.state.strip(ref)
        let meter = store.state.vu.postFader(for: ref) ?? 0

        VStack(spacing: 8) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ref.defaultLabel)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(tint)
                    Text(store.state.label(ref))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Button {
                    onOpen()
                    hapticTap(.light)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(Theme.textDim)
                        .background(Theme.surfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            SegmentedMeter(level: meter, orientation: .horizontal, segments: 20)
                .frame(height: 9)

            HStack(spacing: 8) {
                Text(FaderMath.dbString(strip.level))
                    .font(Theme.readout(13))
                    .foregroundStyle(strip.muted ? Theme.danger : tint)
                Spacer()
                Button {
                    store.setMute(ref, !strip.muted)
                    hapticTap()
                } label: {
                    Text("MUTE")
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .foregroundStyle(strip.muted ? .black : Theme.textDim)
                        .background(strip.muted ? Theme.danger : Theme.surfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!store.state.connected)
            }

            SliderTrack(value: Binding(get: { strip.level },
                                       set: { store.setLevel(ref, $0) }),
                        tint: tint)
                .frame(height: 26)
                .disabled(!store.state.connected)
                .opacity(store.state.connected ? 1 : 0.45)
        }
        .padding(10)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}

/// Full controls for one bus.
struct BusDetailSheet: View {
    @ObservedObject var store: UI16Store
    let ref: ChannelRef
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let strip = store.state.strip(ref)

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Panel {
                        HStack(spacing: 14) {
                            ConsoleFader(value: Binding(get: { strip.level },
                                                        set: { store.setLevel(ref, $0) }),
                                         tint: strip.muted ? Theme.danger : Theme.accent)
                                .frame(width: 44, height: 150)
                            SegmentedMeter(level: store.state.vu.postFader(for: ref) ?? 0,
                                           orientation: .vertical)
                                .frame(width: 12, height: 150)

                            VStack(spacing: 10) {
                                Text(FaderMath.dbString(strip.level))
                                    .font(Theme.bigReadout(20))
                                    .foregroundStyle(Theme.accent)
                                ConsoleButton(title: "MUTE", isOn: strip.muted,
                                              onColor: Theme.danger,
                                              enabled: store.state.connected) {
                                    store.setMute(ref, !strip.muted)
                                }
                                ConsoleButton(title: "SOLO", isOn: strip.solo,
                                              onColor: Theme.solo,
                                              enabled: store.state.connected) {
                                    store.setSolo(ref, !strip.solo)
                                }
                            }
                        }
                    }

                    if ref.kind == .fx {
                        fxPanel
                    }
                }
                .padding(14)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(store.state.label(ref))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }

    /// FX type and BPM are confirmed protocol keys (`f.<n>.fxtype`, `f.<n>.bpm`).
    private var fxPanel: some View {
        let typeKey = UI16Key.fxType(ref.number)
        let bpmKey = UI16Key.fxBpm(ref.number)
        let type = Int(store.state.raw[typeKey]?.double ?? -1)
        let bpm = store.state.raw[bpmKey]?.double ?? 120

        return SectionPanel(title: "EFEITO") {
            VStack(alignment: .leading, spacing: 12) {
                Text("TIPO").font(Theme.label).foregroundStyle(Theme.textDim)
                HStack(spacing: 5) {
                    ForEach(Array(fxTypes.enumerated()), id: \.offset) { index, name in
                        Button {
                            store.sendRawNumber(typeKey, Double(index))
                            hapticTap(.light)
                        } label: {
                            Text(name)
                                .font(.system(size: 10, weight: .heavy))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(type == index ? .black : Theme.textDim)
                                .background(type == index ? Theme.accent : Theme.surfaceHigh)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .disabled(!store.state.connected)

                HStack {
                    Text("BPM").font(Theme.label).foregroundStyle(Theme.textDim)
                    Spacer()
                    Text(String(format: "%.0f", bpm))
                        .font(Theme.bigReadout(18)).foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var fxTypes: [String] { ["REVERB", "DELAY", "CHORUS", "ROOM"] }
}
