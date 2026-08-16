import SwiftUI
import UI16Controller

/// AUX, FX and SUB buses with their own faders, mutes and meters.
struct BusesPage: View {
    @ObservedObject var store: UI16Store

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                section("AUX", UI16Model.auxBuses)
                section("FX", UI16Model.fxReturns)
                section("SUB GROUPS", UI16Model.subGroups)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
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
