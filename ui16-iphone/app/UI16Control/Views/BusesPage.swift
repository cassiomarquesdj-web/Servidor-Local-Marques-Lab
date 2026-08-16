import SwiftUI
import UI16Controller

/// AUX, FX and SUB buses with their own faders, mutes and meters.
struct BusesPage: View {
    @ObservedObject var store: UI16Store

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                masterPanel
                monitorPanel
                section("AUX", UI16Model.auxBuses)
                section("FX", UI16Model.fxReturns)
                section("SUB GROUPS", UI16Model.subGroups)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var masterPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("MASTER").font(Theme.label).foregroundStyle(Theme.textDim)
                    Spacer()
                    Text(FaderMath.dbString(store.state.master.level))
                        .font(Theme.value).foregroundStyle(Theme.ok)
                }
                ParamSlider(
                    title: "PAN",
                    value: Binding(
                        get: { store.state.master.pan },
                        set: { store.setMasterPan($0) }
                    ),
                    readout: panText(store.state.master.pan)
                )
                HStack(spacing: 8) {
                    ConsoleButton(title: "MUTE", isOn: store.state.master.muted,
                                  onColor: Theme.mute, height: Theme.tapMin) {
                        store.setMasterMute(!store.state.master.muted)
                    }
                    // DIM drops the master level for talk-back moments.
                    ConsoleButton(title: "DIM", isOn: store.state.master.dim,
                                  onColor: Theme.solo, height: Theme.tapMin) {
                        store.setMasterDim(!store.state.master.dim)
                    }
                }
            }
        }
    }

    /// Monitoring levels live under `settings.*`, outside the channel address space.
    private var monitorPanel: some View {
        let solo = store.state.raw[VolumeBus.solo]?.double ?? 0
        let hp = store.state.raw[VolumeBus.headphones(1)]?.double ?? 0

        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("MONITORAÇÃO").font(Theme.label).foregroundStyle(Theme.textDim)
                ParamSlider(
                    title: "SOLO",
                    value: Binding(get: { solo }, set: { store.setSoloVolume($0) }),
                    readout: FaderMath.dbString(solo)
                )
                ParamSlider(
                    title: "FONE",
                    value: Binding(get: { hp }, set: { store.setHeadphoneVolume(1, $0) }),
                    readout: FaderMath.dbString(hp)
                )
            }
        }
    }

    private func panText(_ v: Double) -> String {
        let p = (v * 2 - 1) * 100
        if abs(p) < 1 { return "C" }
        return p < 0 ? String(format: "L %.0f", -p) : String(format: "R %.0f", p)
    }

    private func section(_ title: String, _ refs: [ChannelRef]) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(Theme.label).foregroundStyle(Theme.textDim)
                ForEach(refs) { ref in
                    BusRow(store: store, ref: ref)
                    if ref != refs.last { Divider().overlay(Theme.stroke) }
                }
            }
        }
    }
}

struct BusRow: View {
    @ObservedObject var store: UI16Store
    let ref: ChannelRef

    private var strip: StripState { store.state.strip(ref) }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.state.label(ref)).font(.system(size: 14, weight: .bold))
                    Text(ref.address).font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                MeterBar(level: store.state.vu.postFader(for: ref) ?? 0)
                    .frame(width: 46, height: 8)
                Text(FaderMath.dbString(strip.level))
                    .font(Theme.value).foregroundStyle(Theme.accent)
                    .frame(width: 74, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Slider(
                    value: Binding(get: { strip.level }, set: { store.setLevel(ref, $0) }),
                    in: 0...1
                )
                .tint(Theme.accent)

                Button {
                    store.setMute(ref, !strip.muted)
                    hapticTap()
                } label: {
                    Text("MUTE")
                        .font(.system(size: 12, weight: .heavy))
                        .frame(width: 68, height: Theme.tapMin)
                        .foregroundStyle(strip.muted ? .black : Theme.textDim)
                        .background(strip.muted ? Theme.mute : Theme.surfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}
