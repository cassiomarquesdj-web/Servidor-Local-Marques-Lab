import SwiftUI
import UI16Controller

/// Per-channel detail: preamp, pan, aux/fx sends, and any processing parameters the
/// mixer actually reports. Processing keys are rendered from live state rather than
/// hardcoded, so nothing is invented and nothing is hidden.
struct ChannelPage: View {
    @ObservedObject var store: UI16Store
    let ref: ChannelRef
    let onSelect: (ChannelRef) -> Void

    private var strip: StripState { store.state.strip(ref) }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ChannelRail(store: store, selected: Binding(get: { ref }, set: onSelect))

                header

                if ref.kind == .input {
                    preamp
                }

                panPanel
                sendsPanel(bus: .aux, count: UI16Model.auxCount, title: "AUX SENDS")
                sendsPanel(bus: .fx, count: UI16Model.fxCount, title: "FX SENDS")
                processingPanel
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
    }

    private var header: some View {
        Panel {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.state.label(ref)).font(.system(size: 18, weight: .heavy))
                    Text("\(ref.kind.displayName) \(ref.number) · \(ref.address)")
                        .font(Theme.label).foregroundStyle(Theme.textDim)
                }
                Spacer()
                Text(FaderMath.dbString(strip.level))
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var preamp: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("PREAMP").font(Theme.label).foregroundStyle(Theme.textDim)

                ParamSlider(
                    title: "GAIN",
                    value: Binding(get: { strip.gain }, set: { store.setGain(ref, $0) }),
                    readout: String(format: "%+.1f dB", FaderMath.gainValueToDB(strip.gain))
                )

                ConsoleButton(
                    title: "48V PHANTOM",
                    subtitle: strip.phantom ? "LIGADO" : "DESLIGADO",
                    isOn: strip.phantom,
                    onColor: Theme.mute
                ) {
                    store.setPhantom(ref, !strip.phantom)
                }
            }
        }
    }

    private var panPanel: some View {
        Panel {
            ParamSlider(
                title: "PAN",
                value: Binding(get: { strip.pan }, set: { store.setPan(ref, $0) }),
                readout: panText(strip.pan)
            )
        }
    }

    private func sendsPanel(bus: BusKind, count: Int, title: String) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(Theme.label).foregroundStyle(Theme.textDim)
                ForEach(1...count, id: \.self) { n in
                    let key = "\(bus.rawValue).\(n - 1)"
                    let value = strip.sends[key] ?? 0
                    VStack(alignment: .leading, spacing: 4) {
                        ParamSlider(
                            title: "\(bus == .aux ? "AUX" : "FX") \(n)",
                            value: Binding(
                                get: { value },
                                set: { store.setSend(ref, to: bus, n, $0) }
                            ),
                            readout: FaderMath.dbString(value)
                        )
                        if bus == .aux {
                            let post = strip.sendPost[key] ?? false
                            Button {
                                store.setSendPost(ref, to: bus, n, !post)
                                hapticTap()
                            } label: {
                                Text(post ? "POST-FADER" : "PRE-FADER")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(post ? Theme.accent : Theme.textDim)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Renders EQ / gate / dynamics parameters straight from live mixer state.
    ///
    /// The publicly-documented reference implementation does not expose write keys for
    /// these blocks, so the app does not invent command names. Instead it lists whatever
    /// the hardware reports under this channel and lets the operator adjust it by its real
    /// key. See docs/protocol.md.
    private var processingPanel: some View {
        let known: Set<String> = ["mix", "mute", "solo", "pan", "gain", "phantom", "name", "stereoIndex"]
        let prefix = UI16Key.processingPrefix(ref)
        let keys = store.state.rawKeys(withPrefix: prefix).filter { key in
            let tail = String(key.dropFirst(prefix.count))
            // hide plain params already shown above and send values shown in their own panel
            if known.contains(tail) { return false }
            if tail.hasPrefix("aux.") || tail.hasPrefix("fx.") || tail.hasPrefix("mtx.") { return false }
            return true
        }

        return Panel {
            VStack(alignment: .leading, spacing: 10) {
                Text("PROCESSAMENTO (EQ / GATE / COMP)")
                    .font(Theme.label).foregroundStyle(Theme.textDim)

                if keys.isEmpty {
                    Text("Nenhum parâmetro de processamento recebido da mesa ainda. Conecte-se à Ui16 — todos os parâmetros que ela enviar aparecem aqui automaticamente.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                } else {
                    ForEach(keys, id: \.self) { key in
                        RawParamRow(store: store, key: key)
                    }
                }
            }
        }
    }

    private func panText(_ v: Double) -> String {
        let p = (v * 2 - 1) * 100
        if abs(p) < 1 { return "C" }
        return p < 0 ? String(format: "L %.0f", -p) : String(format: "R %.0f", p)
    }
}

/// An editable row for any raw mixer parameter, addressed by its exact wire key.
struct RawParamRow: View {
    @ObservedObject var store: UI16Store
    let key: String

    var body: some View {
        let raw = store.state.raw[key]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(shortName).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(raw?.text ?? "—")
                    .font(Theme.value).foregroundStyle(Theme.accent)
            }
            Text(key).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.textDim)

            if let value = raw?.double, isUnitRange(value) {
                Slider(
                    value: Binding(
                        get: { value },
                        set: { store.sendRawNumber(key, $0) }
                    ),
                    in: 0...1
                )
                .tint(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private var shortName: String {
        key.split(separator: ".").dropFirst(2).joined(separator: " ").uppercased()
    }

    /// Only offer a 0...1 slider for values that actually look normalized.
    private func isUnitRange(_ v: Double) -> Bool { v >= 0 && v <= 1 }
}
