import ParedaoCore
import SwiftUI
import UI16Controller

/// The Paredão dashboard.
///
/// Everything needed to run a set on one screen: what is playing, the master on the
/// console, output metering, phase, and the EQ curve. Dense on purpose — scrolling to find
/// the mute button mid-song is a failure.
struct ParedaoHome: View {
    @ObservedObject var paredao: ParedaoStore
    @ObservedObject var mixer: UI16Store
    let onOpenPlayer: () -> Void
    var onOpenEQ: (() -> Void)? = nil

    @State private var showMonitor = false
    @State private var selectedBand = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 9) {
                    nowPlaying
                    masterSection
                    PhasePanel(paredao: paredao, mixer: mixer)
                    eqSummary
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showMonitor) { MonitorSheet(store: mixer) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 9) {
            Text("PAREDÃO")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(Theme.text)

            Text("UI16")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(mixer.state.connected ? .black : Theme.textFaint)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(mixer.state.connected ? Theme.accent : Theme.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            StatusPill(text: mixer.state.connected ? "ONLINE" : "OFFLINE",
                       color: mixer.state.connected ? Theme.ok : Theme.danger)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.black)
    }

    // MARK: Player

    private var nowPlaying: some View {
        let player = paredao.player
        return Panel(padding: 10) {
            VStack(spacing: 9) {
                HStack(spacing: 11) {
                    Artwork(url: player.current.flatMap(paredao.artworkURL), size: 66, corner: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.current?.displayTitle ?? "Nada tocando")
                            .font(.system(size: 15, weight: .heavy))
                            .lineLimit(1)
                        Text(player.current?.displayArtist ?? "Escolha uma música")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textDim)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text(Track.timeText(player.snapshot.currentTime))
                                .foregroundStyle(Theme.accent)
                            Text("/").foregroundStyle(Theme.textFaint)
                            Text(Track.timeText(player.snapshot.duration))
                                .foregroundStyle(Theme.textDim)
                        }
                        .font(Theme.readout(11))
                    }

                    Spacer(minLength: 0)

                    Button {
                        onOpenPlayer()
                        hapticTap(.light)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .heavy))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(Theme.textDim)
                            .background(Theme.surfaceHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.well).frame(height: 4)
                        Capsule().fill(Theme.accent)
                            .frame(width: geo.size.width * player.snapshot.progress, height: 4)
                    }
                }
                .frame(height: 4)

                HStack(spacing: 7) {
                    Text("PLAYER").font(Theme.label).foregroundStyle(Theme.textFaint)
                    SegmentedMeter(level: player.snapshot.levelL,
                                   orientation: .horizontal, segments: 22)
                        .frame(height: 8)
                    SegmentedMeter(level: player.snapshot.levelR,
                                   orientation: .horizontal, segments: 22)
                        .frame(height: 8)
                }

                HStack(spacing: 7) {
                    transportButton("shuffle", active: player.isShuffled) {
                        player.toggleShuffle()
                    }
                    transportButton("backward.fill") { player.previous() }

                    Button {
                        player.togglePlayPause()
                        hapticTap()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .black))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.black)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall,
                                                        style: .continuous))
                            .shadow(color: Theme.accent.opacity(0.4), radius: 7)
                    }
                    .buttonStyle(.plain)

                    transportButton("forward.fill") { player.next() }
                    transportButton(repeatIcon, active: player.repeatMode != .off) {
                        player.cycleRepeat()
                    }
                }
            }
        }
    }

    private var repeatIcon: String {
        paredao.player.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private func transportButton(_ icon: String, active: Bool = false,
                                 action: @escaping () -> Void) -> some View {
        Button {
            action()
            hapticTap(.light)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 52, height: 52)
                .foregroundStyle(active ? .black : Theme.text)
                .background(active ? Theme.accent : Theme.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Master

    private var masterSection: some View {
        SectionPanel(title: "MASTER DA MESA",
                     accessory: AnyView(
                        HStack(spacing: 6) {
                            if !mixer.state.connected {
                                StatusPill(text: "OFFLINE", color: Theme.danger, filled: true)
                            }
                            Text(FaderMath.dbString(mixer.state.master.level))
                                .font(Theme.bigReadout(17))
                                .foregroundStyle(mixer.state.master.muted ? Theme.danger : Theme.ok)
                        }
                     ),
                     padding: 10) {
            VStack(spacing: 10) {
                StereoMeterWithScale(left: mixer.state.vu.masterPostFader?.l ?? 0,
                                     right: mixer.state.vu.masterPostFader?.r ?? 0)

                HStack(spacing: 10) {
                    ConsoleFader(value: Binding(get: { mixer.state.master.level },
                                                set: { mixer.setMasterLevel($0) }),
                                 tint: mixer.state.master.muted ? Theme.danger : Theme.ok)
                        .frame(width: 40, height: 96)

                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            ConsoleButton(title: "MUTE", isOn: mixer.state.master.muted,
                                          onColor: Theme.danger, height: 44, compact: true,
                                          enabled: mixer.state.connected) {
                                mixer.setMasterMute(!mixer.state.master.muted)
                            }
                            ConsoleButton(title: "DIM", isOn: mixer.state.master.dim,
                                          onColor: Theme.solo, height: 44, compact: true,
                                          enabled: mixer.state.connected) {
                                mixer.setMasterDim(!mixer.state.master.dim)
                            }
                        }
                        HStack(spacing: 6) {
                            ConsoleButton(title: "SOLO", isOn: anySolo,
                                          onColor: Theme.solo, height: 44, compact: true,
                                          enabled: mixer.state.connected && anySolo) {
                                clearSolos()
                            }
                            ConsoleButton(title: "FONE", isOn: false,
                                          onColor: Theme.accent, height: 44, compact: true,
                                          enabled: mixer.state.connected) {
                                showMonitor = true
                            }
                        }
                    }
                }
                .opacity(mixer.state.connected ? 1 : 0.45)
            }
        }
    }

    private func freqText(_ hz: Double) -> String {
        hz >= 1_000 ? String(format: "%.1fk", hz / 1_000) : String(format: "%.0f", hz)
    }

    private var anySolo: Bool { mixer.state.strips.values.contains { $0.solo } }

    private func clearSolos() {
        for ref in UI16Model.allStrips where mixer.state.strip(ref).solo {
            mixer.setSolo(ref, false)
        }
    }

    // MARK: EQ

    /// The EQ block is extracted and `Equatable` on purpose.
    ///
    /// The dashboard re-renders 20 times a second because the meters do. The EQ depends
    /// only on `EQSettings` and the selected band, so leaving it inline made SwiftUI
    /// rebuild ~20 extra view nodes per tick for a curve that had not changed — that alone
    /// doubled CPU. Isolating it lets SwiftUI skip it entirely between EQ edits.
    private var eqSummary: some View {
        ParedaoEQBlock(
            eq: paredao.player.eq,
            selectedBand: $selectedBand,
            onBandChange: { index, freq, gain in
                paredao.player.updateEQ {
                    $0.setFrequency(freq, forBandAt: index)
                    $0.setGain(gain, forBandAt: index)
                }
            },
            onGain: { gain in
                paredao.player.updateEQ { $0.setGain(gain, forBandAt: selectedBand) }
            },
            onToggleBypass: { paredao.player.updateEQ { $0.bypassed.toggle() } },
            onFlat: {
                paredao.player.resetEQ()
                selectedBand = 0
            },
            onPreset: { paredao.player.applyEQPreset($0) },
            onOpenFull: { onOpenEQ?() }
        )
        .equatable()
    }
}

/// A working EQ on the dashboard, not a preview.
///
/// Reaching for the EQ during a set should not cost a screen change: the curve is
/// draggable here, band values are live, and bypass / flat / presets are one tap away.
/// The full page stays for fine work (Q, exact frequency, per-band bypass).
struct ParedaoEQBlock: View, Equatable {
    let eq: EQSettings
    @Binding var selectedBand: Int
    let onBandChange: (Int, Double, Double) -> Void
    let onGain: (Double) -> Void
    let onToggleBypass: () -> Void
    let onFlat: () -> Void
    let onPreset: (EQPreset) -> Void
    let onOpenFull: () -> Void

    /// Closures are ignored: only the data that can change the pixels is compared.
    static func == (a: ParedaoEQBlock, b: ParedaoEQBlock) -> Bool {
        a.eq == b.eq && a.selectedBand == b.selectedBand
    }

    var body: some View {
        let band = eq.bands.indices.contains(selectedBand) ? eq.bands[selectedBand] : eq.bands[0]

        return SectionPanel(title: "EQUALIZADOR DO PLAYER",
                            accessory: AnyView(
                                Button {
                                    onOpenFull()
                                    hapticTap(.light)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("AJUSTE FINO").font(.system(size: 10, weight: .heavy))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9, weight: .heavy))
                                    }
                                    .foregroundStyle(Theme.accent)
                                }
                                .buttonStyle(.plain)
                            ),
                            padding: 10) {
            VStack(spacing: 9) {
                EQCurveView(settings: eq,
                            selectedBand: $selectedBand,
                            onDrag: onBandChange)
                    .equatable()
                    .frame(height: 150)

                // Band readouts double as the band selector.
                HStack(spacing: 4) {
                    ForEach(Array(eq.bands.enumerated()), id: \.element.id) { index, b in
                        Button {
                            selectedBand = index
                            hapticTap(.light)
                        } label: {
                            VStack(spacing: 1) {
                                Text(b.name)
                                    .font(.system(size: 8, weight: .bold))
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                Text(String(format: "%+.1f", b.gain))
                                    .font(Theme.readout(12))
                                Text(Self.freqText(b.frequency))
                                    .font(.system(size: 7.5, design: .monospaced))
                                    .opacity(0.75)
                            }
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(index == selectedBand ? .black
                                             : (b.bypassed ? Theme.textFaint : Theme.text))
                            .background(index == selectedBand ? Theme.accent : Theme.surfaceHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Gain of the selected band, so the curve can be ridden without dragging
                // a small handle mid-show.
                ParamSlider(title: "GANHO · \(band.name)",
                            value: Binding(get: { band.gain }, set: onGain),
                            range: EQBand.gainRange,
                            readout: String(format: "%+.1f dB", band.gain),
                            bipolar: true)

                HStack(spacing: 6) {
                    ConsoleButton(title: eq.bypassed ? "BYPASS" : "ATIVO",
                                  isOn: !eq.bypassed, onColor: Theme.ok,
                                  height: 42, compact: true, action: onToggleBypass)
                    ConsoleButton(title: "FLAT", isOn: false, onColor: Theme.accent,
                                  height: 42, compact: true, action: onFlat)
                    Menu {
                        ForEach(EQPreset.builtIn) { preset in
                            Button(preset.name) { onPreset(preset) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(eq.presetName.isEmpty ? "AJUSTADO" : eq.presetName)
                                .font(.system(size: 11, weight: .heavy))
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
                        }
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(Theme.text)
                        .background(Theme.surfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                .stroke(Theme.stroke, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    static func freqText(_ hz: Double) -> String {
        hz >= 1_000 ? String(format: "%.1fk", hz / 1_000) : String(format: "%.0f", hz)
    }
}

/// PHASE control.
///
/// Two independent things, kept visually separate so the operator is never misled about
/// what is actually being processed:
/// - **PLAYER** — polarity of the app's own output.
/// - **MESA** — the Ui16 channel polarity, which only transmits once the console has
///   reported a real polarity address.
struct PhasePanel: View {
    @ObservedObject var paredao: ParedaoStore
    @ObservedObject var mixer: UI16Store

    var body: some View {
        let phase = paredao.player.phase
        let availability = paredao.phaseAvailability

        return SectionPanel(title: "PHASE / POLARIDADE", padding: 10) {
            VStack(spacing: 10) {
                phaseRow(
                    tag: "PLAYER",
                    state: phase.localPolarity.isInverted ? "INVERTED" : "NORMAL",
                    inverted: phase.localPolarity.isInverted,
                    enabled: paredao.isPolarityEngineAvailable,
                    note: paredao.isPolarityEngineAvailable ? nil : "indisponível nesta versão"
                ) {
                    paredao.player.toggleLocalPolarity()
                }

                Rectangle().fill(Theme.stroke).frame(height: 1)

                phaseRow(
                    tag: "MESA · \(paredao.phaseChannel.defaultLabel)",
                    state: availability.isAvailable
                        ? (phase.mixerPolarity.isInverted ? "INVERTED" : "NORMAL")
                        : "N/D",
                    inverted: availability.isAvailable && phase.mixerPolarity.isInverted,
                    enabled: availability.isAvailable && mixer.state.connected,
                    note: mixerNote(availability, phase)
                ) {
                    paredao.toggleMixerPhase()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(UI16Model.inputSources) { ref in
                            Button {
                                paredao.phaseChannel = ref
                                hapticTap(.light)
                            } label: {
                                Text(ref.defaultLabel)
                                    .font(.system(size: 10, weight: .heavy))
                                    .padding(.horizontal, 9)
                                    .frame(height: 32)
                                    .foregroundStyle(ref == paredao.phaseChannel ? .black : Theme.textDim)
                                    .background(ref == paredao.phaseChannel ? Theme.accent : Theme.surfaceHigh)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func phaseRow(tag: String, state: String, inverted: Bool,
                          enabled: Bool, note: String?,
                          action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("PHASE").font(Theme.label).foregroundStyle(Theme.textFaint)
                    Text(state)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(inverted ? Theme.solo
                                         : (enabled ? Theme.ok : Theme.textFaint))
                }
                if let note {
                    Text(note)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            ConsoleButton(title: inverted ? "Ø INV" : "NORMAL",
                          isOn: inverted, onColor: Theme.solo,
                          height: 46, compact: true, enabled: enabled, action: action)
                .frame(width: 118)
        }
    }

    private func mixerNote(_ availability: PhaseAvailability, _ phase: PhaseState) -> String? {
        guard availability.isAvailable else {
            return "endereço não confirmado — nada é enviado à mesa"
        }
        if !mixer.state.connected { return "mesa offline" }
        if phase.awaitingConfirmation { return "aguardando confirmação…" }
        return availability.key
    }
}
