import Foundation

/// Any URL that already points at a media file. This is the fallback and also
/// the path used by the offline tests, which serve a real MP4 over loopback.
public struct DirectMediaExtractor: MediaExtractor {
    public static let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mov", "m4a", "mp3", "aac", "wav", "webm", "mkv", "flac", "ogg", "opus",
    ]

    public let name = "Mídia direta"

    public init() {}

    public func canHandle(_ url: URL) -> Bool { true }

    public func extract(_ url: URL, using fetcher: HTTPFetching) async throws -> ExtractedMedia {
        let fileExtension = url.pathExtension.lowercased()
        var isAudio = ["m4a", "mp3", "aac", "wav", "flac", "ogg", "opus"].contains(fileExtension)
        var looksLikeMedia = Self.mediaExtensions.contains(fileExtension)

        if !looksLikeMedia {
            // No useful extension: ask the server what it is before giving up.
            var head = URLRequest(url: url)
            head.httpMethod = "HEAD"
            if let (_, response) = try? await fetcher.data(for: head),
               let type = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                looksLikeMedia = type.hasPrefix("video/") || type.hasPrefix("audio/")
                isAudio = type.hasPrefix("audio/")
            }
        }

        guard looksLikeMedia else {
            throw ExtractorError(
                "O endereço não aponta para um arquivo de mídia e o site não é "
                + "reconhecido pelo extrator embarcado."
            )
        }

        let title = MediaURL.safeFilename(
            url.deletingPathExtension().lastPathComponent.removingPercentEncoding
                ?? url.lastPathComponent
        )
        let stream = MediaStream(
            url: url,
            content: isAudio ? .audioOnly : .muxed,
            videoCodec: isAudio ? nil : "unknown",
            audioCodec: "unknown",
            fileExtension: fileExtension.isEmpty ? "mp4" : fileExtension
        )
        return ExtractedMedia(title: title, webpage: url, streams: [stream])
    }
}
