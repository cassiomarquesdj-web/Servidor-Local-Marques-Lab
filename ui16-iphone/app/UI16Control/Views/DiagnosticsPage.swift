import SwiftUI
import UI16Controller

/// Diagnostics: every parameter the mixer has sent, live counters, and full VU metering.
/// Nothing is discarded just because there is no dedicated control for it yet.
struct DiagnosticsPage: View {
    @ObservedObject var store: UI16Store
    @State private var filter = ""
    @State private var section: Section = .meters

    enum Section: String, CaseIterable {
        case meters = "MÉTRICAS"
        case state = "ESTADO"
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.top, 8)

            switch section {
            case .meters: meters
            case .state: rawState
            }
        }
    }

    // MARK: Meters

    private var meters: some View {
        ScrollView {
            VStack(spacing: 10) {
                stats

                meterGroup("INPUTS (PRE / POST / POST-FADER)", store.state.vu.input.enumerated().map {
                    ("IN \($0.offset + 1)", [$0.element.pre, $0.element.post, $0.element.postFader])
                })
                meterGroup("LINE", store.state.vu.line.enumerated().map {
                    ("LINE \($0.offset + 1)", [$0.element.pre, $0.element.post, $0.element.postFader])
                })
                meterGroup("PLAYER", store.state.vu.player.enumerated().map {
                    ("PLAYER \($0.offset + 1)", [$0.element.pre, $0.element.post, $0.element.postFader])
                })
                meterGroup("AUX (POST / POST-FADER)", store.state.vu.aux.enumerated().map {
                    ("AUX \($0.offset + 1)", [$0.element.post, $0.element.postFader])
                })
                meterGroup("FX (L / R)", store.state.vu.fx.enumerated().map {
                    ("FX \($0.offset + 1)", [$0.element.postFaderL, $0.element.postFaderR])
                })
                meterGroup("SUB (L / R)", store.state.vu.sub.enumerated().map {
                    ("SUB \($0.offset + 1)", [$0.element.postFaderL, $0.element.postFaderR])
                })
                if let m = store.state.vu.masterPostFader {
                    meterGroup("MASTER", [("MASTER", [m.l, m.r])])
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
    }

    private var stats: some View {
        Panel {
            HStack {
                stat("MENSAGENS", "\(store.state.messageCount)")
                stat("VU FRAMES", "\(store.state.vuFrameCount)")
                stat("CHAVES", "\(store.state.raw.count)")
                stat("LINK", store.state.connected ? "OK" : "OFF")
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .heavy).monospacedDigit())
                .foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
    }

    private func meterGroup(_ title: String, _ rows: [(String, [Double])]) -> some View {
        Group {
            if !rows.isEmpty {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(Theme.label).foregroundStyle(Theme.textDim)
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 8) {
                                Text(row.0).font(.system(size: 11, weight: .semibold))
                                    .frame(width: 70, alignment: .leading)
                                ForEach(Array(row.1.enumerated()), id: \.offset) { _, level in
                                    VStack(spacing: 2) {
                                        MeterBar(level: level, vertical: false).frame(height: 9)
                                        Text(String(format: "%.0f", FaderMath.vuValueToDB(level)))
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundStyle(Theme.textDim)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Raw state

    private var rawState: some View {
        VStack(spacing: 8) {
            TextField("Filtrar chave (ex: i.0, eq, aux)", text: $filter)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 10)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(keys, id: \.self) { key in
                        HStack {
                            Text(key).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text(store.state.raw[key]?.text ?? "")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    if keys.isEmpty {
                        Text(store.state.connected
                             ? "Nenhuma chave corresponde ao filtro."
                             : "Aguardando estado da mesa…")
                            .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                            .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
    }

    private var keys: [String] {
        let all = store.state.raw.keys.sorted()
        guard !filter.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(filter) }
    }
}
