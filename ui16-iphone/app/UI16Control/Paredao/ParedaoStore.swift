import Combine
import Foundation
import ParedaoCore
import UI16Controller

/// App-level glue for Paredão mode.
///
/// This is the **only** place the player and the Ui16 meet. `PlayerController` and
/// `UI16Store` stay unaware of each other, so audio keeps running when the mixer drops off
/// the network — which is the whole point of splitting them.
@MainActor
final class ParedaoStore: ObservableObject {

    @Published private(set) var library = MusicLibrary()
    @Published private(set) var playlists = PlaylistStore()
    @Published private(set) var sortOrder: MusicLibrary.SortOrder = .title

    /// Folder-scan progress, shown while importing.
    @Published private(set) var isScanning = false
    @Published private(set) var scanFound = 0
    @Published private(set) var scanMessage = ""

    /// Channel the Paredão phase button targets on the mixer.
    @Published var phaseChannel = ChannelRef(.input, 1)

    let player: PlayerController
    private let output: AVAudioOutput
    private let mixer: UI16Store
    private var storage: ParedaoStorage?
    private var saveTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(mixer: UI16Store) {
        self.mixer = mixer
        let engine = AVAudioOutput()
        self.output = engine
        self.player = PlayerController(output: engine)

        setupStorage()
        wirePlayer()
        observeMixerForPhase()
    }

    // MARK: Persistence

    private func setupStorage() {
        guard let url = try? ParedaoStorage.defaultURL() else { return }
        let storage = ParedaoStorage(fileURL: url)
        self.storage = storage

        let snapshot = storage.loadOrEmpty()
        library = snapshot.library
        playlists = snapshot.playlists
        sortOrder = snapshot.sortOrder
        player.setEQ(snapshot.eq)
        player.setRepeat(snapshot.repeatMode)
        player.setVolume(snapshot.volume)
        if snapshot.isShuffled != player.isShuffled { player.toggleShuffle() }
    }

    /// Debounced save — a fader drag or a rapid sequence of edits must not hammer the disk.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let storage else { return }
        var snapshot = ParedaoSnapshot()
        snapshot.library = library
        snapshot.playlists = playlists
        snapshot.eq = player.eq
        snapshot.repeatMode = player.repeatMode
        snapshot.isShuffled = player.isShuffled
        snapshot.volume = player.snapshot.volume
        snapshot.lastTrackID = player.current?.id
        snapshot.sortOrder = sortOrder
        try? storage.save(snapshot)
    }

    private func wirePlayer() {
        player.onTrackStarted = { [weak self] track in
            self?.library.recordPlay(track.id)
            self?.scheduleSave()
        }
        player.onStateChanged = { [weak self] in
            self?.scheduleSave()
        }
    }

    // MARK: Library

    var artworkDirectory: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        return base.appendingPathComponent("Paredao/Artwork", isDirectory: true)
    }

    func artworkURL(for track: Track) -> URL? {
        guard track.hasArtwork, let dir = artworkDirectory else { return nil }
        let url = LibraryScanner.artworkURL(id: track.id, directory: dir)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Import a folder the user picked in Files.
    func importFolder(_ url: URL) {
        guard !isScanning else { return }
        isScanning = true
        scanFound = 0
        scanMessage = "Lendo \(url.lastPathComponent)…"

        let artworkDir = artworkDirectory
        Task { [weak self] in
            let result = await LibraryScanner.scan(folder: url, artworkDirectory: artworkDir) { found, _ in
                Task { @MainActor [weak self] in
                    self?.scanFound = found
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.library.addRoot(result.root)
                self.library.upsert(result.tracks)
                self.isScanning = false
                self.scanMessage = result.tracks.isEmpty
                    ? "Nenhum áudio encontrado em \(result.root.name)."
                    : "\(result.tracks.count) música(s) de \(result.root.name)."
                self.saveNow()
            }
        }
    }

    /// Import individual files the user picked.
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isScanning = true
        scanMessage = "Importando \(urls.count) arquivo(s)…"
        let artworkDir = artworkDirectory

        Task { [weak self] in
            var imported: [Track] = []
            for url in urls where Track.isSupported(url) {
                let accessed = url.startAccessingSecurityScopedResource()
                let bookmark = try? url.bookmarkData(options: [],
                                                     includingResourceValuesForKeys: nil,
                                                     relativeTo: nil)
                var track = await LibraryScanner.makeTrack(from: url,
                                                           rootURL: nil,
                                                           rootBookmark: bookmark,
                                                           relativePath: "",
                                                           artworkDirectory: artworkDir)
                track.refreshSearchKey()
                imported.append(track)
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.library.upsert(imported)
                self.isScanning = false
                self.scanMessage = "\(imported.count) música(s) importada(s)."
                self.saveNow()
            }
        }
    }

    func removeRoot(_ root: LibraryRoot) {
        library.removeRoot(id: root.id)
        playlists.prune(existing: Set(library.tracks.map(\.id)))
        saveNow()
    }

    func toggleFavorite(_ track: Track) {
        library.toggleFavorite(track.id)
        scheduleSave()
    }

    func setSortOrder(_ order: MusicLibrary.SortOrder) {
        sortOrder = order
        scheduleSave()
    }

    func clearHistory() {
        library.clearHistory()
        scheduleSave()
    }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let p = playlists.create(name: name)
        saveNow()
        return p
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        playlists.rename(id: id, to: name)
        saveNow()
    }

    func deletePlaylist(_ id: UUID) {
        playlists.delete(id: id)
        saveNow()
    }

    func addToPlaylist(_ trackIDs: [UUID], playlist: UUID) {
        playlists.addTracks(trackIDs, to: playlist)
        saveNow()
    }

    func updatePlaylist(_ id: UUID, _ change: (inout Playlist) -> Void) {
        playlists.update(id: id, change)
        saveNow()
    }

    func tracks(in playlist: Playlist) -> [Track] {
        library.tracks(ids: playlist.trackIDs)
    }

    func playPlaylist(_ playlist: Playlist, shuffled: Bool = false) {
        let items = tracks(in: playlist)
        guard !items.isEmpty else { return }
        if shuffled != player.isShuffled { player.toggleShuffle() }
        player.play(tracks: items, startAt: 0)
    }

    // MARK: Phase — mixer side

    /// Whether the mixer has actually reported a polarity parameter for the selected
    /// channel. Until it does, nothing is transmitted.
    var phaseAvailability: PhaseAvailability {
        PhaseControl.resolve(channelAddress: phaseChannel.address,
                             reportedKeys: mixer.state.raw.keys)
    }

    /// Ask the mixer to change channel polarity.
    ///
    /// Refuses to send when no real address has been confirmed — this project does not
    /// guess protocol. The local player polarity still works in that case.
    func setMixerPhase(_ polarity: PhasePolarity) {
        guard let key = phaseAvailability.key else { return }
        player.noteMixerPolarityRequested(polarity)
        mixer.sendRawBool(key, polarity.isInverted)
    }

    func toggleMixerPhase() {
        setMixerPhase(player.phase.mixerPolarity.toggled)
    }

    /// Watch mixer state so the phase button reflects what the console actually reports,
    /// including changes made on the mixer itself or by another client.
    private func observeMixerForPhase() {
        mixer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                guard let key = PhaseControl.resolve(channelAddress: self.phaseChannel.address,
                                                     reportedKeys: state.raw.keys).key,
                      let value = state.raw[key]?.double else { return }
                let polarity: PhasePolarity = value != 0 ? .inverted : .normal
                if self.player.phase.mixerConfirmed != polarity {
                    self.player.noteMixerPolarityConfirmed(polarity)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Convenience for the UI

    var mixerStore: UI16Store { mixer }
    var isPolarityEngineAvailable: Bool { output.isPolarityAvailable }

    func filteredTracks(query: String, scope: MusicLibrary.SearchScope) -> [Track] {
        MusicLibrary.sort(library.search(query, scope: scope), by: sortOrder)
    }
}
