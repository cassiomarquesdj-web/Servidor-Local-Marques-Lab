import ParedaoCore
import SwiftUI
import UniformTypeIdentifiers

/// Library: instant search, folders, favourites, history and playlists.
struct LibraryPage: View {
    @ObservedObject var paredao: ParedaoStore

    @State private var query = ""
    @State private var tab: Tab = .songs
    @State private var selectedFolder: String?
    /// A single importer, switched by mode. Two `.fileImporter` modifiers on the same
    /// view conflict in SwiftUI and neither presents, so they are merged into one.
    @State private var importMode: ImportMode?

    enum ImportMode: Identifiable {
        case folder, files
        var id: Int { self == .folder ? 0 : 1 }
        var types: [UTType] {
            switch self {
            case .folder: return [.folder]
            case .files: return [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
            }
        }
        var allowsMultiple: Bool { self == .files }
    }
    @State private var addingToPlaylist: Track?
    @State private var newPlaylistName = ""
    @State private var showNewPlaylist = false
    @State private var openPlaylist: Playlist?

    enum Tab: String, CaseIterable {
        case songs = "MÚSICAS"
        case folders = "PASTAS"
        case playlists = "PLAYLISTS"
        case favorites = "FAVORITOS"
        case history = "HISTÓRICO"
    }

    var body: some View {
        VStack(spacing: 8) {
            searchField
            tabPicker

            if paredao.isScanning { scanBanner }

            Group {
                switch tab {
                case .songs: songList(paredao.filteredTracks(query: query, scope: .all))
                case .folders: folderBrowser
                case .playlists: playlistList
                case .favorites: songList(paredao.filteredTracks(query: query, scope: .favorites))
                case .history: songList(historyResults)
                }
            }
        }
        .padding(.top, 8)
        .fileImporter(
            isPresented: Binding(get: { importMode != nil },
                                 set: { if !$0 { importMode = nil } }),
            allowedContentTypes: importMode?.types ?? [.folder],
            allowsMultipleSelection: importMode?.allowsMultiple ?? false
        ) { result in
            let mode = importMode
            importMode = nil
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            if mode == .files {
                paredao.importFiles(urls)
            } else if let first = urls.first {
                paredao.importFolder(first)
            }
        }
        .alert("Nova playlist", isPresented: $showNewPlaylist) {
            TextField("Nome", text: $newPlaylistName)
            Button("Criar") {
                paredao.createPlaylist(name: newPlaylistName)
                newPlaylistName = ""
            }
            Button("Cancelar", role: .cancel) { newPlaylistName = "" }
        }
        .sheet(item: $addingToPlaylist) { track in
            AddToPlaylistSheet(paredao: paredao, track: track)
        }
        .sheet(item: $openPlaylist) { playlist in
            PlaylistDetailSheet(paredao: paredao, playlistID: playlist.id)
        }
    }

    // MARK: Search + tabs

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textDim)
                TextField("Buscar música, artista, pasta…", text: $query)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Theme.tapMin)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Menu {
                Button { importMode = .folder } label: { Label("Importar pasta", systemImage: "folder.badge.plus") }
                Button { importMode = .files } label: { Label("Importar arquivos", systemImage: "doc.badge.plus") }
                Divider()
                Picker("Ordenar", selection: Binding(get: { paredao.sortOrder },
                                                     set: { paredao.setSortOrder($0) })) {
                    ForEach(MusicLibrary.SortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if tab == .history {
                    Button(role: .destructive) { paredao.clearHistory() } label: {
                        Label("Limpar histórico", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 20))
                    .frame(width: Theme.tapMin, height: Theme.tapMin)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 10)
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                        selectedFolder = nil
                        hapticTap()
                    } label: {
                        Text(t.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .foregroundStyle(tab == t ? .black : Theme.textDim)
                            .background(tab == t ? Theme.accent : Theme.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private var scanBanner: some View {
        HStack(spacing: 8) {
            ProgressView().tint(.black)
            Text(paredao.scanFound > 0
                 ? "Indexando… \(paredao.scanFound) música(s)"
                 : paredao.scanMessage)
                .font(.system(size: 12, weight: .bold))
            Spacer()
        }
        .padding(10)
        .background(Theme.accent)
        .foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 10)
    }

    // MARK: Lists

    private var historyResults: [Track] {
        let history = paredao.library.historyTracks
        guard !query.isEmpty else { return history }
        let hits = Set(paredao.library.search(query).map(\.id))
        return history.filter { hits.contains($0.id) }
    }

    private func songList(_ tracks: [Track]) -> some View {
        Group {
            if tracks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                track: track,
                                artwork: paredao.artworkURL(for: track),
                                isCurrent: paredao.player.current?.id == track.id,
                                isFavorite: paredao.library.isFavorite(track.id),
                                onPlay: { paredao.player.play(tracks: tracks, startAt: index) },
                                onFavorite: { paredao.toggleFavorite(track) },
                                onQueue: { paredao.player.enqueue(track) },
                                onPlayNext: { paredao.player.playNext(track) },
                                onAddToPlaylist: { addingToPlaylist = track }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 42)).foregroundStyle(Theme.textDim)
            Text(paredao.library.tracks.isEmpty
                 ? "Nenhuma música importada ainda."
                 : "Nada encontrado para \"\(query)\".")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
            if paredao.library.tracks.isEmpty {
                Text("Importe uma pasta do Files. Os arquivos ficam onde estão — nada é copiado para dentro do app.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                ConsoleButton(title: "IMPORTAR PASTA", isOn: false) { importMode = .folder }
                    .frame(width: 220)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: Folders

    private var folderBrowser: some View {
        Group {
            if let folder = selectedFolder {
                VStack(spacing: 6) {
                    HStack {
                        Button {
                            selectedFolder = nil
                        } label: {
                            Label("PASTAS", systemImage: "chevron.left")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        Spacer()
                        Text(folder).font(.system(size: 12, weight: .heavy))
                    }
                    .padding(.horizontal, 12)
                    songList(MusicLibrary.sort(paredao.library.tracks(inFolder: folder),
                                               by: paredao.sortOrder))
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(paredao.library.folders, id: \.name) { folder in
                            Button {
                                selectedFolder = folder.name
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                                    Text(folder.name).font(.system(size: 14, weight: .semibold))
                                    Spacer()
                                    Text("\(folder.count)")
                                        .font(.system(size: 12).monospacedDigit())
                                        .foregroundStyle(Theme.textDim)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 52)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        if !paredao.library.roots.isEmpty {
                            Text("PASTAS IMPORTADAS")
                                .font(Theme.label).foregroundStyle(Theme.textDim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 12)
                            ForEach(paredao.library.roots) { root in
                                HStack {
                                    Image(systemName: "externaldrive.fill").foregroundStyle(Theme.textDim)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(root.name).font(.system(size: 13, weight: .semibold))
                                        Text("\(root.trackCount) música(s)")
                                            .font(.system(size: 10)).foregroundStyle(Theme.textDim)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        paredao.removeRoot(root)
                                    } label: {
                                        Image(systemName: "trash").foregroundStyle(Theme.mute)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 52)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: Playlists

    private var playlistList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                Button {
                    showNewPlaylist = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                        Text("NOVA PLAYLIST").font(.system(size: 13, weight: .bold))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: Theme.tapBig)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                ForEach(paredao.playlists.playlists) { playlist in
                    HStack(spacing: 10) {
                        Image(systemName: "music.note.list").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(playlist.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                            Text("\(playlist.count) música(s)")
                                .font(.system(size: 10)).foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        Button {
                            paredao.playPlaylist(playlist)
                            hapticTap()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 26)).foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        Button {
                            openPlaylist = playlist
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                                .frame(width: 34, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 62)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
    }

    // MARK: Import handling

    private func handleImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let url = urls.first {
            paredao.importFolder(url)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            paredao.importFiles(urls)
        }
    }
}

/// One row in a track list, with the actions an operator needs mid-set.
struct TrackRow: View {
    let track: Track
    let artwork: URL?
    let isCurrent: Bool
    let isFavorite: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void
    let onQueue: () -> Void
    let onPlayNext: () -> Void
    let onAddToPlaylist: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Artwork(url: artwork, size: 44, corner: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.system(size: 14, weight: isCurrent ? .heavy : .semibold))
                    .foregroundStyle(isCurrent ? Theme.accent : Theme.text)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(track.displayArtist).lineLimit(1)
                    if !track.folder.isEmpty {
                        Text("·")
                        Text(track.folder).lineLimit(1)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textDim)
            }

            Spacer(minLength: 4)

            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 11)).foregroundStyle(Theme.solo)
            }
            Text(track.durationText)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.textDim)

            Menu {
                Button { onPlayNext() } label: { Label("Tocar em seguida", systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { onQueue() } label: { Label("Adicionar à fila", systemImage: "text.append") }
                Button { onAddToPlaylist() } label: { Label("Adicionar a playlist", systemImage: "music.note.list") }
                Button { onFavorite() } label: {
                    Label(isFavorite ? "Remover dos favoritos" : "Favoritar",
                          systemImage: isFavorite ? "star.slash" : "star")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15))
                    .frame(width: 36, height: 48)
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 62)
        .background(isCurrent ? Theme.accent.opacity(0.14) : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay()
            hapticTap()
        }
    }
}

/// Pick a playlist to add a track to.
struct AddToPlaylistSheet: View {
    @ObservedObject var paredao: ParedaoStore
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("NOVA") {
                    HStack {
                        TextField("Nome da playlist", text: $newName)
                        Button("Criar") {
                            let p = paredao.createPlaylist(name: newName)
                            paredao.addToPlaylist([track.id], playlist: p.id)
                            dismiss()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("EXISTENTES") {
                    if paredao.playlists.playlists.isEmpty {
                        Text("Nenhuma playlist ainda.").foregroundStyle(.secondary)
                    }
                    ForEach(paredao.playlists.playlists) { playlist in
                        Button {
                            paredao.addToPlaylist([track.id], playlist: playlist.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(playlist.name)
                                Spacer()
                                Text("\(playlist.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(track.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}

/// Playlist contents: reorder, remove, play.
struct PlaylistDetailSheet: View {
    @ObservedObject var paredao: ParedaoStore
    let playlistID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var draftName = ""

    private var playlist: Playlist? { paredao.playlists.playlist(id: playlistID) }

    var body: some View {
        NavigationStack {
            Group {
                if let playlist {
                    List {
                        Section {
                            Button {
                                paredao.playPlaylist(playlist)
                                dismiss()
                            } label: { Label("Tocar", systemImage: "play.fill") }
                            Button {
                                paredao.playPlaylist(playlist, shuffled: true)
                                dismiss()
                            } label: { Label("Tocar embaralhado", systemImage: "shuffle") }
                        }
                        Section("MÚSICAS · \(playlist.count)") {
                            ForEach(Array(paredao.tracks(in: playlist).enumerated()), id: \.offset) { index, track in
                                HStack {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11).monospacedDigit())
                                        .foregroundStyle(.secondary).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(track.displayTitle).lineLimit(1)
                                        Text(track.displayArtist)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(track.durationText)
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    paredao.player.play(tracks: paredao.tracks(in: playlist), startAt: index)
                                    dismiss()
                                }
                            }
                            .onDelete { offsets in
                                paredao.updatePlaylist(playlistID) { p in
                                    for i in offsets.sorted(by: >) { p.remove(at: i) }
                                }
                            }
                            .onMove { source, destination in
                                paredao.updatePlaylist(playlistID) { $0.move(from: source, to: destination) }
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                } else {
                    Text("Playlist removida.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(playlist?.name ?? "Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            draftName = playlist?.name ?? ""
                            renaming = true
                        } label: { Label("Renomear", systemImage: "pencil") }
                        Button(role: .destructive) {
                            paredao.deletePlaylist(playlistID)
                            dismiss()
                        } label: { Label("Excluir", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .alert("Renomear playlist", isPresented: $renaming) {
                TextField("Nome", text: $draftName)
                Button("Salvar") { paredao.renamePlaylist(playlistID, to: draftName) }
                Button("Cancelar", role: .cancel) { }
            }
        }
    }
}
