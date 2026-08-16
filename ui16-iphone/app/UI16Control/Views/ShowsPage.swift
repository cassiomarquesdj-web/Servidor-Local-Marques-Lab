import SwiftUI
import UI16Controller

/// Shows, snapshots and cues (scenes/presets).
///
/// Recall is destructive — it overwrites the live mix — so every recall asks for
/// confirmation first. During an event a mis-tap here is far more costly than one extra tap.
struct ShowsPage: View {
    @ObservedObject var store: UI16Store
    @State private var pendingRecall: Recall?

    struct Recall: Identifiable {
        let id = UUID()
        let show: String
        let name: String
        let kind: Kind
        enum Kind: String { case show, snapshot, cue }

        var title: String {
            switch kind {
            case .show: return "Carregar show \"\(name)\"?"
            case .snapshot: return "Carregar snapshot \"\(name)\"?"
            case .cue: return "Carregar cue \"\(name)\"?"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                current
                if store.state.showNames.isEmpty {
                    empty
                } else {
                    ForEach(store.state.showNames, id: \.self) { show in
                        showCard(show)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .alert(item: $pendingRecall) { recall in
            Alert(
                title: Text(recall.title),
                message: Text("Isso substitui a mistura atual da mesa."),
                primaryButton: .destructive(Text("Carregar")) { perform(recall) },
                secondaryButton: .cancel(Text("Cancelar"))
            )
        }
    }

    private var current: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CARREGADO AGORA").font(Theme.label).foregroundStyle(Theme.textDim)
                    Spacer()
                    Button {
                        store.refreshShows()
                        hapticTap()
                    } label: {
                        Label("ATUALIZAR", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
                row("SHOW", store.state.currentShow)
                row("SNAPSHOT", store.state.currentSnapshot)
                row("CUE", store.state.currentCue)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textDim)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(value.isEmpty ? Theme.textDim : Theme.accent)
        }
    }

    private var empty: some View {
        Panel {
            VStack(spacing: 6) {
                Text(store.state.connected
                     ? "Nenhum show salvo na mesa."
                     : "Conecte-se à Ui16 para ver os shows.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private func showCard(_ show: String) -> some View {
        let detail = store.state.shows[show] ?? ShowDetail()
        let isCurrent = show == store.state.currentShow

        return Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(show).font(.system(size: 16, weight: .heavy))
                        Text("\(detail.snapshots.count) snapshots · \(detail.cues.count) cues")
                            .font(Theme.label).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    if isCurrent {
                        Text("ATIVO")
                            .font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.ok).foregroundStyle(.black)
                            .clipShape(Capsule())
                    }
                }

                ConsoleButton(title: "CARREGAR SHOW", isOn: false, height: Theme.tapMin) {
                    pendingRecall = Recall(show: show, name: show, kind: .show)
                }

                if !detail.snapshots.isEmpty {
                    group("SNAPSHOTS", detail.snapshots, show: show, kind: .snapshot,
                          current: store.state.currentSnapshot, isCurrentShow: isCurrent)
                }
                if !detail.cues.isEmpty {
                    group("CUES", detail.cues, show: show, kind: .cue,
                          current: store.state.currentCue, isCurrentShow: isCurrent)
                }
            }
        }
    }

    private func group(_ title: String, _ items: [String], show: String,
                       kind: Recall.Kind, current: String, isCurrentShow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.label).foregroundStyle(Theme.textDim)
            ForEach(items, id: \.self) { item in
                let active = isCurrentShow && item == current
                Button {
                    pendingRecall = Recall(show: show, name: item, kind: kind)
                } label: {
                    HStack {
                        Image(systemName: active ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(active ? Theme.ok : Theme.textDim)
                        Text(item).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: Theme.tapMin, alignment: .leading)
                    .background(Theme.surfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func perform(_ recall: Recall) {
        switch recall.kind {
        case .show: store.loadShow(recall.show)
        case .snapshot: store.loadSnapshot(show: recall.show, snapshot: recall.name)
        case .cue: store.loadCue(show: recall.show, cue: recall.name)
        }
        hapticTap()
    }
}
