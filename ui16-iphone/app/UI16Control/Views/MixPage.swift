import SwiftUI
import UI16Controller

/// The live page: pick a channel, ride its fader with one hand, hit MUTE/SOLO instantly,
/// and keep the master under the thumb. Everything visible at once — no hidden menus.
struct MixPage: View {
    @ObservedObject var store: UI16Store
    @Binding var selected: ChannelRef

    var body: some View {
        VStack(spacing: 8) {
            ChannelRail(store: store, selected: $selected)

            HStack(alignment: .top, spacing: 10) {
                selectedStrip
                masterStrip
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .frame(maxHeight: .infinity)
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Selected channel

    private var strip: StripState { store.state.strip(selected) }

    private var selectedStrip: some View {
        Panel {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.state.label(selected))
                            .font(.system(size: 16, weight: .heavy))
                            .lineLimit(1)
                        Text(selected.address.uppercased())
                            .font(Theme.label).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Text(FaderMath.dbString(strip.level))
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }

                Fader(
                    value: Binding(
                        get: { strip.level },
                        set: { store.setLevel(selected, $0) }
                    ),
                    meter: store.state.vu.postFader(for: selected),
                    tint: Theme.accent
                )
                .frame(maxHeight: .infinity)

                HStack(spacing: 8) {
                    ConsoleButton(title: "MUTE", isOn: strip.muted, onColor: Theme.mute) {
                        store.setMute(selected, !strip.muted)
                    }
                    ConsoleButton(title: "SOLO", isOn: strip.solo, onColor: Theme.solo) {
                        store.setSolo(selected, !strip.solo)
                    }
                }
            }
        }
    }

    // MARK: Master

    private var masterStrip: some View {
        Panel {
            VStack(spacing: 8) {
                HStack {
                    Text("MASTER").font(.system(size: 16, weight: .heavy))
                    Spacer()
                }
                Text(FaderMath.dbString(store.state.master.level))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.ok)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Fader(
                        value: Binding(
                            get: { store.state.master.level },
                            set: { store.setMasterLevel($0) }
                        ),
                        tint: Theme.ok
                    )
                    .frame(width: 54)

                    // Stereo master meters, always visible.
                    HStack(spacing: 3) {
                        MeterBar(level: store.state.vu.masterPostFader?.l ?? 0).frame(width: 9)
                        MeterBar(level: store.state.vu.masterPostFader?.r ?? 0).frame(width: 9)
                    }
                }
                .frame(maxHeight: .infinity)

                ConsoleButton(title: "MUTE", isOn: store.state.master.muted, onColor: Theme.mute) {
                    store.setMasterMute(!store.state.master.muted)
                }
            }
        }
        .frame(width: 132)
    }
}

/// Horizontally scrolling channel selector with per-channel meter, mute and solo state.
/// Tapping selects; the mute/solo indicators make the whole mix legible at a glance.
struct ChannelRail: View {
    @ObservedObject var store: UI16Store
    @Binding var selected: ChannelRef

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(UI16Model.inputSources) { ref in
                    ChannelChip(
                        label: store.state.label(ref),
                        index: shortIndex(ref),
                        level: store.state.vu.postFader(for: ref) ?? 0,
                        muted: store.state.strip(ref).muted,
                        solo: store.state.strip(ref).solo,
                        isSelected: ref == selected
                    ) {
                        selected = ref
                        hapticTap()
                    } onMute: {
                        store.setMute(ref, !store.state.strip(ref).muted)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func shortIndex(_ ref: ChannelRef) -> String {
        switch ref.kind {
        case .input: return "\(ref.number)"
        case .line: return "L\(ref.number)"
        case .player: return "P\(ref.number)"
        default: return ref.defaultLabel
        }
    }
}

struct ChannelChip: View {
    let label: String
    let index: String
    let level: Double
    let muted: Bool
    let solo: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onMute: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onSelect) {
                VStack(spacing: 3) {
                    Text(index)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(isSelected ? .black : Theme.text)
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .black.opacity(0.7) : Theme.textDim)
                    MeterBar(level: level).frame(height: 4)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(width: 68)
                .background(isSelected ? Theme.accent : Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .stroke(solo ? Theme.solo : Theme.stroke, lineWidth: solo ? 2 : 1)
                )
            }
            .buttonStyle(.plain)

            // Dedicated mute tap target — mute is reachable without selecting the channel.
            Button {
                onMute()
                hapticTap()
            } label: {
                Text("M")
                    .font(.system(size: 12, weight: .heavy))
                    .frame(width: 68, height: 30)
                    .foregroundStyle(muted ? .black : Theme.textDim)
                    .background(muted ? Theme.mute : Theme.surfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
