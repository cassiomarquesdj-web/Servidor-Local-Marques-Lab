import ParedaoCore
import SwiftUI

/// The Paredão equalizer.
///
/// This EQ runs on the **player output, inside the phone** — not on the Ui16. The mixer's
/// EQ write addresses are not publicly confirmed, and this project does not invent
/// protocol, so the header says plainly where the processing happens.
struct EQPage: View {
    @ObservedObject var paredao: ParedaoStore
    @State private var selectedBand = 0

    private var player: PlayerController { paredao.player }
    private var eq: EQSettings { player.eq }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                curve
                bandStrip
                bandDetail
                presets
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    // MARK: Header

    private var header: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EQUALIZADOR").font(.system(size: 16, weight: .heavy))
                        // Being explicit here matters: the operator must never think the
                        // mixer is doing this.
                        Text("Processado no player (dentro do iPhone), não na Ui16")
                            .font(.system(size: 10)).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    ConsoleButton(title: eq.bypassed ? "BYPASS" : "ATIVO",
                                  isOn: !eq.bypassed,
                                  onColor: Theme.ok, height: Theme.tapMin) {
                        player.updateEQ { $0.bypassed.toggle() }
                    }
                    .frame(width: 110)
                }

                HStack {
                    Text("PREAMP").font(Theme.label).foregroundStyle(Theme.textDim)
                    Slider(value: Binding(get: { eq.preamp },
                                          set: { v in player.updateEQ { $0.preamp = v } }),
                           in: -24...12)
                        .tint(Theme.accent)
                    Text(String(format: "%+.1f dB", eq.preamp))
                        .font(Theme.readout(12)).foregroundStyle(Theme.accent)
                        .frame(width: 74, alignment: .trailing)
                }
            }
        }
    }

    // MARK: Curve

    private var curve: some View {
        Panel {
            VStack(spacing: 6) {
                EQCurveView(settings: eq,
                            selectedBand: $selectedBand,
                            onDrag: { index, freq, gain in
                                player.updateEQ {
                                    $0.setFrequency(freq, forBandAt: index)
                                    $0.setGain(gain, forBandAt: index)
                                }
                            })
                    .equatable()
                    .frame(height: 210)

                HStack {
                    ForEach([30, 100, 300, 1_000, 3_000, 10_000], id: \.self) { hz in
                        Text(hz >= 1_000 ? "\(hz / 1_000)k" : "\(hz)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: Band strip

    private var bandStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(eq.bands.enumerated()), id: \.element.id) { index, band in
                Button {
                    selectedBand = index
                    hapticTap()
                } label: {
                    VStack(spacing: 3) {
                        Text(band.name)
                            .font(.system(size: 9, weight: .bold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(String(format: "%+.1f", band.gain))
                            .font(.system(size: 13, weight: .heavy).monospacedDigit())
                        Text(freqText(band.frequency))
                            .font(.system(size: 8, design: .monospaced))
                            .opacity(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .foregroundStyle(index == selectedBand ? .black
                                     : (band.bypassed ? Theme.textDim : Theme.text))
                    .background(index == selectedBand ? Theme.accent : Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(band.bypassed ? Theme.mute : .clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Selected band controls

    private var bandDetail: some View {
        let band = eq.bands.indices.contains(selectedBand) ? eq.bands[selectedBand] : eq.bands[0]
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(band.name).font(.system(size: 15, weight: .heavy))
                    Spacer()
                    ConsoleButton(title: band.bypassed ? "BYPASS" : "ON",
                                  isOn: !band.bypassed, onColor: Theme.ok, height: 38) {
                        player.updateEQ { $0.toggleBypass(bandAt: selectedBand) }
                    }
                    .frame(width: 96)
                }

                paramRow("GANHO", value: band.gain, range: EQBand.gainRange,
                         text: String(format: "%+.1f dB", band.gain)) { v in
                    player.updateEQ { $0.setGain(v, forBandAt: selectedBand) }
                }

                // Frequency is edited on a log scale — that is how hearing works, and a
                // linear slider would make everything below 1 kHz unusable.
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("FREQUÊNCIA").font(Theme.label).foregroundStyle(Theme.textDim)
                        Spacer()
                        Text(freqText(band.frequency)).font(Theme.readout(12)).foregroundStyle(Theme.accent)
                    }
                    Slider(value: Binding(
                        get: { logPosition(band.frequency) },
                        set: { pos in
                            player.updateEQ { $0.setFrequency(frequency(fromLog: pos), forBandAt: selectedBand) }
                        }), in: 0...1)
                        .tint(Theme.accent)
                }

                paramRow("Q / LARGURA", value: band.q, range: EQBand.qRange,
                         text: String(format: "%.2f", band.q)) { v in
                    player.updateEQ { $0.setQ(v, forBandAt: selectedBand) }
                }

                Button {
                    player.updateEQ {
                        $0.setGain(0, forBandAt: selectedBand)
                    }
                    hapticTap()
                } label: {
                    Text("ZERAR ESTA BANDA")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: Theme.tapMin)
                        .foregroundStyle(Theme.textDim)
                        .background(Theme.surfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func paramRow(_ title: String, value: Double, range: ClosedRange<Double>,
                          text: String, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Theme.label).foregroundStyle(Theme.textDim)
                Spacer()
                Text(text).font(Theme.readout(12)).foregroundStyle(Theme.accent)
            }
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .tint(Theme.accent)
        }
    }

    // MARK: Presets

    private var presets: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PRESETS").font(Theme.label).foregroundStyle(Theme.textDim)
                    Spacer()
                    Button {
                        player.resetEQ()
                        hapticTap()
                    } label: {
                        Label("FLAT / RESET", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(EQPreset.builtIn) { preset in
                        Button {
                            player.applyEQPreset(preset)
                            hapticTap()
                        } label: {
                            Text(preset.name)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: Theme.tapMin)
                                .foregroundStyle(eq.presetName == preset.name ? .black : Theme.text)
                                .background(eq.presetName == preset.name ? Theme.accent : Theme.surfaceHigh)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Frequency helpers

    private func freqText(_ hz: Double) -> String {
        hz >= 1_000
            ? String(format: "%.1f kHz", hz / 1_000)
            : String(format: "%.0f Hz", hz)
    }

    private func logPosition(_ hz: Double) -> Double {
        let lo = log10(EQBand.freqRange.lowerBound), hi = log10(EQBand.freqRange.upperBound)
        return (log10(max(hz, EQBand.freqRange.lowerBound)) - lo) / (hi - lo)
    }

    private func frequency(fromLog pos: Double) -> Double {
        let lo = log10(EQBand.freqRange.lowerBound), hi = log10(EQBand.freqRange.upperBound)
        return pow(10, lo + min(max(pos, 0), 1) * (hi - lo))
    }
}

/// The EQ curve with draggable band handles.
/// Equatable so SwiftUI can skip re-evaluating it when unrelated state (meters, transport)
/// publishes. Recomputing the 120-point biquad response 20 times a second was burning CPU
/// for a curve that had not changed.
struct EQCurveView: View, Equatable {
    static func == (a: EQCurveView, b: EQCurveView) -> Bool {
        a.settings == b.settings && a.selectedBand == b.selectedBand && a.interactive == b.interactive
    }

    let settings: EQSettings
    @Binding var selectedBand: Int
    /// When false the curve is a read-only summary (used on the Paredão dashboard).
    var interactive: Bool = true
    /// (band index, new frequency, new gain)
    let onDrag: (Int, Double, Double) -> Void

    private let dbRange: Double = 24

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height

            ZStack {
                grid(w: w, h: h)

                // The combined response.
                Path { path in
                    let steps = 120
                    for i in 0...steps {
                        let x = Double(i) / Double(steps)
                        let hz = frequency(fromNormalized: x)
                        let db = settings.responseDB(at: hz)
                        let point = CGPoint(x: x * w, y: yFor(db: db, height: h))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(settings.bypassed ? Theme.textDim : Theme.accent,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // Filled area under the curve, for readability at a glance.
                Path { path in
                    let steps = 120
                    path.move(to: CGPoint(x: 0, y: h / 2))
                    for i in 0...steps {
                        let x = Double(i) / Double(steps)
                        let db = settings.responseDB(at: frequency(fromNormalized: x))
                        path.addLine(to: CGPoint(x: x * w, y: yFor(db: db, height: h)))
                    }
                    path.addLine(to: CGPoint(x: w, y: h / 2))
                    path.closeSubpath()
                }
                .fill(Theme.accent.opacity(settings.bypassed ? 0.04 : 0.16))

                // Draggable handles.
                ForEach(interactive ? Array(settings.bands.enumerated()) : [], id: \.element.id) { index, band in
                    let x = normalized(frequency: band.frequency) * w
                    let y = yFor(db: band.gain, height: h)
                    Circle()
                        .fill(index == selectedBand ? Theme.accent : Theme.surfaceHigh)
                        .overlay(Circle().stroke(band.bypassed ? Theme.mute : Theme.accent, lineWidth: 2))
                        .frame(width: index == selectedBand ? 26 : 20,
                               height: index == selectedBand ? 26 : 20)
                        .position(x: x, y: y)
                        // Named coordinate space: without it the drag reports coordinates
                        // local to the handle itself, so dragging did nothing.
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("eqCurve"))
                                .onChanged { g in
                                    selectedBand = index
                                    let nx = min(max(g.location.x / w, 0), 1)
                                    let ny = min(max(g.location.y / h, 0), 1)
                                    let hz = frequency(fromNormalized: Double(nx))
                                    let db = (0.5 - Double(ny)) * 2 * dbRange
                                    onDrag(index, hz, db)
                                }
                        )
                }
            }
            .coordinateSpace(name: "eqCurve")
        }
    }

    private func grid(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35))
            // 0 dB line
            Path { p in
                p.move(to: CGPoint(x: 0, y: h / 2))
                p.addLine(to: CGPoint(x: w, y: h / 2))
            }
            .stroke(Theme.stroke, lineWidth: 1)
            // ±12 dB
            ForEach([-12.0, 12.0], id: \.self) { db in
                Path { p in
                    let y = yFor(db: db, height: h)
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(Theme.stroke.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            // decade lines
            ForEach([100.0, 1_000.0, 10_000.0], id: \.self) { hz in
                Path { p in
                    let x = normalized(frequency: hz) * w
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: h))
                }
                .stroke(Theme.stroke.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
        }
    }

    private func yFor(db: Double, height: CGFloat) -> CGFloat {
        let clamped = min(max(db, -dbRange), dbRange)
        return height * (0.5 - clamped / (2 * dbRange))
    }

    private func normalized(frequency hz: Double) -> Double {
        let lo = log10(EQBand.freqRange.lowerBound), hi = log10(EQBand.freqRange.upperBound)
        return (log10(min(max(hz, EQBand.freqRange.lowerBound), EQBand.freqRange.upperBound)) - lo) / (hi - lo)
    }

    private func frequency(fromNormalized x: Double) -> Double {
        let lo = log10(EQBand.freqRange.lowerBound), hi = log10(EQBand.freqRange.upperBound)
        return pow(10, lo + x * (hi - lo))
    }
}
