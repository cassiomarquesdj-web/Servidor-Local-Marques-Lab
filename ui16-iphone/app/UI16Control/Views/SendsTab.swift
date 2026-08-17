import SwiftUI
import UI16Controller

/// Sends for one channel, as a compact matrix of knobs.
///
/// Six full-width sliders stacked vertically would fill the screen and still show one
/// channel; a knob grid shows every destination at once and leaves room for detail.
/// Tapping a send opens its detailed control.
struct SendsTab: View {
    @ObservedObject var store: UI16Store
    let ref: ChannelRef

    @State private var detail: SendTarget?

    struct SendTarget: Identifiable {
        let bus: BusKind
        let number: Int
        var id: String { "\(bus.rawValue).\(number)" }
        var label: String { "\(bus == .aux ? "AUX" : "FX") \(number)" }
    }

    private var strip: StripState { store.state.strip(ref) }

    var body: some View {
        VStack(spacing: 10) {
            SectionPanel(title: "AUX SENDS") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                          spacing: 12) {
                    ForEach(1...UI16Model.auxCount, id: \.self) { n in
                        sendCell(bus: .aux, number: n, tint: Theme.ok)
                    }
                }
            }

            SectionPanel(title: "FX SENDS") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                          spacing: 12) {
                    ForEach(1...UI16Model.fxCount, id: \.self) { n in
                        sendCell(bus: .fx, number: n,
                                 tint: Color(red: 1.0, green: 0.55, blue: 0.85))
                    }
                }
            }
        }
        .sheet(item: $detail) { target in
            SendDetailSheet(store: store, ref: ref, bus: target.bus, number: target.number)
        }
    }

    private func sendCell(bus: BusKind, number: Int, tint: Color) -> some View {
        let key = "\(bus.rawValue).\(number - 1)"
        let value = strip.sends[key] ?? 0
        let post = strip.sendPost[key] ?? false

        return VStack(spacing: 4) {
            // The knob is the level control: drag it. Tapping the label opens the detail.
            Knob(value: Binding(get: { value },
                                set: { store.setSend(ref, to: bus, number, $0) }),
                 tint: tint, size: 50)

            Button {
                detail = SendTarget(bus: bus, number: number)
                hapticTap(.light)
            } label: {
                HStack(spacing: 3) {
                    Text("\(bus == .aux ? "AUX" : "FX") \(number)")
                        .font(Theme.label)
                    Image(systemName: "slider.horizontal.3").font(.system(size: 8))
                }
                .foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)

            Text(FaderMath.dbString(value))
                .font(Theme.readout(10))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)

            if bus == .aux {
                // PRE/POST is a one-tap switch, not a caption. It decides whether the
                // musician's monitor follows the channel fader, so it has to be both
                // obvious and reachable without a hidden gesture.
                PrePostToggle(post: post, enabled: store.state.connected) {
                    store.setSendPost(ref, to: bus, number, !post)
                }
            }
        }
    }
}

/// PRE/POST switch: shows both options, lights the active one, toggles on a normal tap.
struct PrePostToggle: View {
    let post: Bool
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            guard enabled else { return }
            action()
            hapticTap()
        } label: {
            HStack(spacing: 0) {
                segment("PRE", active: !post)
                segment("POST", active: post)
            }
            .frame(height: 26)
            .background(Theme.well)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .animation(.easeOut(duration: 0.12), value: post)
    }

    private func segment(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .heavy))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(active ? .black : Theme.textFaint)
            .background(active ? Theme.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Detailed control for one send, opened from the matrix.
struct SendDetailSheet: View {
    @ObservedObject var store: UI16Store
    let ref: ChannelRef
    let bus: BusKind
    let number: Int
    @Environment(\.dismiss) private var dismiss

    private var key: String { "\(bus.rawValue).\(number - 1)" }

    var body: some View {
        let strip = store.state.strip(ref)
        let value = strip.sends[key] ?? 0
        let post = strip.sendPost[key] ?? false

        NavigationStack {
            VStack(spacing: 16) {
                Panel {
                    VStack(spacing: 16) {
                        HStack {
                            Text(store.state.label(ref))
                                .font(.system(size: 15, weight: .heavy))
                            Spacer()
                            Text(FaderMath.dbString(value))
                                .font(Theme.bigReadout(20))
                                .foregroundStyle(Theme.accent)
                        }

                        SliderTrack(value: Binding(get: { value },
                                                   set: { store.setSend(ref, to: bus, number, $0) }))
                            .frame(height: 30)

                        if bus == .aux {
                            VStack(spacing: 6) {
                                PrePostToggle(post: post, enabled: store.state.connected) {
                                    store.setSendPost(ref, to: bus, number, !post)
                                }
                                .frame(height: 46)
                                Text(post ? "O envio segue o fader do canal."
                                          : "O envio é independente do fader do canal.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("\(bus == .aux ? "AUX" : "FX") \(number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(bus == .aux ? 300 : 230)])
    }
}

/// EQ / dynamics parameters rendered from the mixer's own reported state.
///
/// The Ui16's EQ and dynamics write addresses are not publicly confirmed, so nothing is
/// invented here: whatever the console reports under this channel is shown with its real
/// key and made editable. Connect to the mixer and the controls appear by themselves.
struct ProcessingTab: View {
    @ObservedObject var store: UI16Store
    let ref: ChannelRef
    let group: Group

    enum Group {
        case eq, dyn
        var prefixes: [String] {
            switch self {
            case .eq: return ["eq", "hpf", "lpf", "filter"]
            case .dyn: return ["gate", "dyn", "comp", "expander", "limiter"]
            }
        }
        var title: String { self == .eq ? "EQUALIZADOR DO CANAL" : "GATE / COMPRESSOR" }
    }

    private var keys: [String] {
        let prefix = ref.address + "."
        return store.state.rawKeys(withPrefix: prefix).filter { key in
            let tail = String(key.dropFirst(prefix.count)).lowercased()
            return group.prefixes.contains { tail == $0 || tail.hasPrefix($0 + ".") }
        }
    }

    var body: some View {
        SectionPanel(title: group.title) {
            if keys.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 26)).foregroundStyle(Theme.textFaint)
                    Text(store.state.connected
                         ? "A mesa não reportou parâmetros deste bloco para o canal."
                         : "Conecte-se à Ui16 para ver os parâmetros reais.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)
                    Text("Nenhum endereço é inventado: os controles aparecem sozinhos quando a mesa informar as chaves.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textFaint)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                          spacing: 14) {
                    ForEach(keys, id: \.self) { key in
                        RawParamKnob(store: store, fullKey: key, channelPrefix: ref.address + ".")
                    }
                }
            }
        }
    }
}

/// One mixer-reported parameter as a knob (or a switch when it reads as a boolean).
struct RawParamKnob: View {
    @ObservedObject var store: UI16Store
    let fullKey: String
    let channelPrefix: String

    private var shortName: String {
        String(fullKey.dropFirst(channelPrefix.count))
            .replacingOccurrences(of: ".", with: " ")
            .uppercased()
    }

    var body: some View {
        let raw = store.state.raw[fullKey]
        let value = raw?.double ?? 0
        // A parameter that only ever reads 0 or 1 is a switch, not a continuous control.
        let looksBoolean = value == 0 || value == 1

        VStack(spacing: 4) {
            if looksBoolean, shortName.hasSuffix("ON") {
                ConsoleButton(title: shortName, isOn: value != 0,
                              onColor: Theme.ok, height: 50, compact: true,
                              enabled: store.state.connected) {
                    store.sendRawBool(fullKey, value == 0)
                }
            } else {
                Knob(value: Binding(get: { value },
                                    set: { store.sendRawNumber(fullKey, $0) }),
                     tint: Theme.accent, size: 50)
                Text(shortName)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(raw?.text ?? "—")
                    .font(Theme.readout(10)).foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
        }
    }
}
