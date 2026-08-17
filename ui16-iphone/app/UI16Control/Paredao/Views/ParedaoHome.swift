import ParedaoCore
import SwiftUI
import UI16Controller

/// The Paredão dashboard: what the operator needs during a set, all on one screen.
/// Transport, output meters, master control on the mixer, and the phase button.
struct ParedaoHome: View {
    @ObservedObject var paredao: ParedaoStore
    @ObservedObject var mixer: UI16Store
    let onOpenPlayer: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                nowPlaying
                masterPanel
                phasePanel
                monitorPanel
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    // MARK: Now playing

    private var nowPlaying: some View {
        let player = paredao.player
        return Panel {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Artwork(url: player.current.flatMap(paredao.artworkURL), size: 72, corner: 10)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.current?.displayTitle ?? "Nada tocando")
                            .font(.system(size: 17, weight: .heavy)).lineLimit(2)
                        Text(player.current?.displayArtist ?? "Escolha uma música na biblioteca")
                            .font(.system(size: 12)).foregroundStyle(Theme.textDim).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(Track.timeText(player.snapshot.currentTime))
                            Text("/")
                            Text(Track.timeText(player.snapshot.duration))
                        }
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                }

                // Player output meters — the level actually leaving the phone.
                HStack(spacing: 6) {
                    Text("PLAYER").font(Theme.label).foregroundStyle(Theme.textDim)
                    MeterBar(level: player.snapshot.levelL, vertical: false).frame(height: 8)
                    MeterBar(level: player.snapshot.levelR, vertical: false).frame(height: 8)
                }

                HStack(spacing: 8) {
                    transportButton("backward.fill", size: 20) { player.previous() }
                    transportButton(player.isPlaying ? "pause.fill" : "play.fill",
                                    size: 26, wide: true) { player.togglePlayPause() }
                    transportButton("forward.fill", size: 20) { player.next() }
                    Button {
                        onOpenPlayer()
                        hapticTap()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 52, height: Theme.tapBig)
                            .foregroundStyle(Theme.textDim)
                            .background(Theme.surfaceHigh)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func transportButton(_ icon: String, size: CGFloat,
                                 wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action()
            hapticTap()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .frame(maxWidth: wide ? .infinity : 72, minHeight: Theme.tapBig)
                .foregroundStyle(wide ? .black : Theme.text)
                .background(wide ? Theme.accent : Theme.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Master (on the mixer)

    private var masterPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("MASTER DA MESA").font(Theme.label).foregroundStyle(Theme.textDim)
                    Spacer()
                    if !mixer.state.connected {
                        Text("MESA OFFLINE")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.mute).foregroundStyle(.black)
                            .clipShape(Capsule())
                    }
                    Text(FaderMath.dbString(mixer.state.master.level))
                        .font(Theme.value).foregroundStyle(Theme.ok)
                }

                HStack(spacing: 10) {
                    Fader(
                        value: Binding(
                            get: { mixer.state.master.level },
                            set: { mixer.setMasterLevel($0) }
                        ),
                        tint: Theme.ok
                    )
                    .frame(height: 120)
                    .disabled(!mixer.state.connected)
                    .opacity(mixer.state.connected ? 1 : 0.4)

                    // Master VU L/R straight from the console.
                    HStack(spacing: 4) {
                        MeterBar(level: mixer.state.vu.masterPostFader?.l ?? 0).frame(width: 10)
                        MeterBar(level: mixer.state.vu.masterPostFader?.r ?? 0).frame(width: 10)
                    }
                    .frame(height: 120)

                    VStack(spacing: 6) {
                        ConsoleButton(title: "MUTE", isOn: mixer.state.master.muted,
                                      onColor: Theme.mute, height: 54) {
                            mixer.setMasterMute(!mixer.state.master.muted)
                        }
                        ConsoleButton(title: "DIM", isOn: mixer.state.master.dim,
                                      onColor: Theme.solo, height: 54) {
                            mixer.setMasterDim(!mixer.state.master.dim)
                        }
                    }
                    .frame(width: 96)
                    .disabled(!mixer.state.connected)
                    .opacity(mixer.state.connected ? 1 : 0.4)
                }
            }
        }
    }

    // MARK: Phase

    private var phasePanel: some View {
        PhasePanel(paredao: paredao, mixer: mixer)
    }

    // MARK: Monitoring

    private var monitorPanel: some View {
        let solo = mixer.state.raw[VolumeBus.solo]?.double ?? 0
        let hp = mixer.state.raw[VolumeBus.headphones(1)]?.double ?? 0

        return Panel {
            VStack(alignment: .leading, spacing: 10) {
                Text("MONITORAÇÃO").font(Theme.label).foregroundStyle(Theme.textDim)
                ParamSlider(title: "SOLO",
                            value: Binding(get: { solo }, set: { mixer.setSoloVolume($0) }),
                            readout: FaderMath.dbString(solo))
                ParamSlider(title: "FONE",
                            value: Binding(get: { hp }, set: { mixer.setHeadphoneVolume(1, $0) }),
                            readout: FaderMath.dbString(hp))
            }
            .disabled(!mixer.state.connected)
            .opacity(mixer.state.connected ? 1 : 0.4)
        }
    }
}

/// PHASE control.
///
/// Two independent things, shown separately so the operator is never misled about what is
/// actually being processed:
/// - **PLAYER**: real polarity inversion of the app's own audio output.
/// - **MESA**: the Ui16 channel polarity. Only transmits once the mixer has reported a real
///   polarity address; otherwise it says so plainly instead of pretending.
struct PhasePanel: View {
    @ObservedObject var paredao: ParedaoStore
    @ObservedObject var mixer: UI16Store

    var body: some View {
        let phase = paredao.player.phase
        let availability = paredao.phaseAvailability

        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("PHASE / POLARIDADE").font(Theme.label).foregroundStyle(Theme.textDim)

                // Local player polarity — always real.
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PLAYER").font(.system(size: 12, weight: .heavy))
                        Text(phase.localPolarity.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(phase.localPolarity.isInverted ? Theme.solo : Theme.textDim)
                    }
                    Spacer()
                    ConsoleButton(title: phase.localPolarity.isInverted ? "Ø INVERTIDA" : "NORMAL",
                                  isOn: phase.localPolarity.isInverted,
                                  onColor: Theme.solo, height: Theme.tapMin) {
                        paredao.player.toggleLocalPolarity()
                    }
                    .frame(width: 150)
                    .disabled(!paredao.isPolarityEngineAvailable)
                    .opacity(paredao.isPolarityEngineAvailable ? 1 : 0.45)
                }

                if !paredao.isPolarityEngineAvailable {
                    Text(AVAudioOutput.polarityUnavailableReason)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Theme.stroke)

                // Mixer channel polarity.
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MESA · \(paredao.phaseChannel.defaultLabel)")
                            .font(.system(size: 12, weight: .heavy))
                        Text(mixerStatusText(availability, phase))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(mixerStatusColor(availability, phase))
                    }
                    Spacer()
                    ConsoleButton(title: phase.mixerPolarity.isInverted ? "Ø INVERTIDA" : "NORMAL",
                                  isOn: phase.mixerPolarity.isInverted && availability.isAvailable,
                                  onColor: Theme.solo, height: Theme.tapMin) {
                        paredao.toggleMixerPhase()
                    }
                    .frame(width: 150)
                    .disabled(!availability.isAvailable || !mixer.state.connected)
                    .opacity(availability.isAvailable && mixer.state.connected ? 1 : 0.45)
                }

                // Channel picker for the mixer-side control.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(UI16Model.inputSources) { ref in
                            Button {
                                paredao.phaseChannel = ref
                                hapticTap()
                            } label: {
                                Text(ref.defaultLabel)
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .frame(height: 34)
                                    .foregroundStyle(ref == paredao.phaseChannel ? .black : Theme.textDim)
                                    .background(ref == paredao.phaseChannel ? Theme.accent : Theme.surfaceHigh)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !availability.isAvailable {
                    Text(PhaseControl.unconfirmedExplanation)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func mixerStatusText(_ availability: PhaseAvailability, _ phase: PhaseState) -> String {
        guard let key = availability.key else { return "ENDEREÇO NÃO CONFIRMADO" }
        if !mixer.state.connected { return "MESA OFFLINE" }
        if phase.awaitingConfirmation { return "AGUARDANDO CONFIRMAÇÃO…" }
        return "\(phase.mixerPolarity.label) · \(key)"
    }

    private func mixerStatusColor(_ availability: PhaseAvailability, _ phase: PhaseState) -> Color {
        guard availability.isAvailable else { return Theme.mute }
        if phase.awaitingConfirmation { return Theme.solo }
        return phase.mixerPolarity.isInverted ? Theme.solo : Theme.textDim
    }
}
