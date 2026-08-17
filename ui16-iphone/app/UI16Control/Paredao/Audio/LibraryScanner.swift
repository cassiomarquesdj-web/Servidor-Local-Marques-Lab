import AVFoundation
import Foundation
import ParedaoCore

#if canImport(UIKit)
import UIKit
#endif

/// Indexes audio files from a folder the user picked in Files.
///
/// The folder is **not** copied into the app. A security-scoped bookmark is stored instead,
/// so a 200 GB music drive stays where it is and still works after a relaunch.
/// Only metadata is read; audio data is never loaded here.
enum LibraryScanner {

    struct ScanResult {
        var root: LibraryRoot
        var tracks: [Track]
        var skipped: Int
    }

    /// Walk a folder (including subfolders) and build tracks for every supported file.
    ///
    /// - Parameter progress: called with (found, scanned) so a big drive can show movement.
    static func scan(folder url: URL,
                     artworkDirectory: URL?,
                     progress: (@Sendable (Int, Int) -> Void)? = nil) async -> ScanResult {

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        // Bookmark the folder so access survives relaunches.
        let bookmark = try? url.bookmarkData(options: [],
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil)

        var root = LibraryRoot(name: url.lastPathComponent,
                               path: url.path,
                               bookmark: bookmark)

        var tracks: [Track] = []
        var skipped = 0
        var scanned = 0

        let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
        guard let walker = FileManager.default.enumerator(at: url,
                                                          includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else {
            return ScanResult(root: root, tracks: [], skipped: 0)
        }

        for case let fileURL as URL in walker {
            scanned += 1
            guard Track.isSupported(fileURL) else {
                if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    skipped += 1
                }
                continue
            }

            let relative = relativePath(of: fileURL, from: url)
            var track = await makeTrack(from: fileURL,
                                        rootURL: url,
                                        rootBookmark: bookmark,
                                        relativePath: relative,
                                        artworkDirectory: artworkDirectory)
            track.refreshSearchKey()
            tracks.append(track)

            if tracks.count % 25 == 0 { progress?(tracks.count, scanned) }
        }

        progress?(tracks.count, scanned)
        root.trackCount = tracks.count
        return ScanResult(root: root, tracks: tracks, skipped: skipped)
    }

    /// Build a track for a single file, reading tags and caching artwork.
    static func makeTrack(from fileURL: URL,
                          rootURL: URL?,
                          rootBookmark: Data?,
                          relativePath: String,
                          artworkDirectory: URL?) async -> Track {

        let asset = AVURLAsset(url: fileURL)
        var title = "", artist = "", album = ""
        var duration: TimeInterval = 0
        var artwork: Data?

        if let loadedDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(loadedDuration)
            if seconds.isFinite, seconds > 0 { duration = seconds }
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    title = (try? await item.load(.stringValue)) ?? ""
                case .commonKeyArtist, .commonKeyAuthor:
                    if artist.isEmpty { artist = (try? await item.load(.stringValue)) ?? "" }
                case .commonKeyAlbumName:
                    album = (try? await item.load(.stringValue)) ?? ""
                case .commonKeyArtwork:
                    if artwork == nil { artwork = try? await item.load(.dataValue) }
                default:
                    break
                }
            }
        }

        let id = UUID()
        var hasArtwork = false
        if let artwork, let artworkDirectory {
            hasArtwork = saveArtwork(artwork, id: id, directory: artworkDirectory)
        }

        let folderName = fileURL.deletingLastPathComponent().lastPathComponent

        return Track(
            id: id,
            fileName: fileURL.deletingPathExtension().lastPathComponent,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            album: album.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration,
            fileExtension: fileURL.pathExtension.lowercased(),
            folder: folderName,
            bookmark: rootBookmark,
            relativePath: relativePath,
            absolutePath: fileURL.path,
            hasArtwork: hasArtwork
        )
    }

    static func relativePath(of fileURL: URL, from root: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return "" }
        var relative = String(filePath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    // MARK: Artwork cache

    /// Downscale and cache cover art on disk. Full-size art from thousands of tracks would
    /// not fit in memory, so only a thumbnail is kept and it is loaded on demand.
    @discardableResult
    static func saveArtwork(_ data: Data, id: UUID, directory: URL) -> Bool {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return false }
        let side: CGFloat = 300
        let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1), 1)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return false }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: artworkURL(id: id, directory: directory), options: .atomic)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    static func artworkURL(id: UUID, directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }
}
