import Foundation

/// One audio file in the library.
///
/// Deliberately lightweight: the library holds thousands of these in memory, so it stores
/// only metadata and a way to reach the file — never audio data or artwork bytes.
/// Artwork is cached on disk and loaded on demand, keyed by `id`.
public struct Track: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// File name without extension, used when no title tag exists.
    public var fileName: String
    public var title: String
    public var artist: String
    public var album: String
    /// Seconds. `0` when the duration could not be read.
    public var duration: TimeInterval
    /// Container extension in lowercase (`mp3`, `wav`, `aiff`, `m4a`, `flac`).
    public var fileExtension: String
    /// Name of the folder the file sits in — the library groups by this.
    public var folder: String
    /// Security-scoped bookmark of the file (or of its root folder), so access survives
    /// relaunches without copying the file into the app.
    public var bookmark: Data?
    /// Path relative to the bookmarked root, when the bookmark points at a folder.
    public var relativePath: String
    /// Absolute path at index time. Only a fallback — bookmarks are authoritative.
    public var absolutePath: String
    public var hasArtwork: Bool
    public var addedAt: Date

    /// Lowercased haystack for search, precomputed at index time so queries stay cheap
    /// even with thousands of tracks.
    public var searchKey: String

    public init(
        id: UUID = UUID(),
        fileName: String,
        title: String = "",
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        fileExtension: String = "",
        folder: String = "",
        bookmark: Data? = nil,
        relativePath: String = "",
        absolutePath: String = "",
        hasArtwork: Bool = false,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileExtension = fileExtension
        self.folder = folder
        self.bookmark = bookmark
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.hasArtwork = hasArtwork
        self.addedAt = addedAt
        self.searchKey = Track.makeSearchKey(title: title, artist: artist,
                                             album: album, fileName: fileName, folder: folder)
    }

    /// Title to show: the tag when present, else the file name.
    public var displayTitle: String { title.isEmpty ? fileName : title }
    /// Artist to show, or a dash when unknown.
    public var displayArtist: String { artist.isEmpty ? "—" : artist }

    /// `m:ss` (or `h:mm:ss`) for the duration.
    public var durationText: String { Track.timeText(duration) }

    public static func timeText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Build the normalized search haystack. Diacritics are folded so "sertao" finds "sertão".
    public static func makeSearchKey(title: String, artist: String, album: String,
                                     fileName: String, folder: String) -> String {
        [title, artist, album, fileName, folder]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Recompute `searchKey` after metadata changes.
    public mutating func refreshSearchKey() {
        searchKey = Track.makeSearchKey(title: title, artist: artist,
                                        album: album, fileName: fileName, folder: folder)
    }

    /// Audio containers the player accepts. FLAC is decoded natively by AVFoundation on iOS 11+.
    public static let supportedExtensions: Set<String> = ["mp3", "wav", "aiff", "aif", "m4a", "aac", "flac", "caf", "alac"]

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
