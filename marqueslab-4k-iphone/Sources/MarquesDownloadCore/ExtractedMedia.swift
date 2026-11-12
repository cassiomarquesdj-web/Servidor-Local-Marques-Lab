import Foundation

/// One downloadable stream offered by a source.
public struct MediaStream: Equatable, Sendable {
    public enum Content: String, Sendable { case videoOnly, audioOnly, muxed }

    public var url: URL
    public var content: Content
    public var height: Int?
    public var bitrate: Int?
    public var videoCodec: String?
    public var audioCodec: String?
    public var fileExtension: String

    public init(
        url: URL, content: Content, height: Int? = nil, bitrate: Int? = nil,
        videoCodec: String? = nil, audioCodec: String? = nil, fileExtension: String = "mp4"
    ) {
        self.url = url
        self.content = content
        self.height = height
        self.bitrate = bitrate
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.fileExtension = fileExtension
    }

    /// H.264 is what Premiere and After Effects open without transcoding.
    public var isEditableVideo: Bool {
        guard let codec = videoCodec?.lowercased() else { return false }
        return codec.hasPrefix("avc1") || codec.hasPrefix("h264")
    }

    public var isEditableAudio: Bool {
        guard let codec = audioCodec?.lowercased() else { return false }
        return codec.hasPrefix("mp4a") || codec.hasPrefix("aac")
    }
}

/// Everything an extractor could learn about one media item.
public struct ExtractedMedia: Equatable, Sendable {
    public var title: String
    public var uploader: String?
    public var duration: Double?
    public var thumbnail: URL?
    public var webpage: URL
    public var streams: [MediaStream]

    public init(
        title: String, uploader: String? = nil, duration: Double? = nil,
        thumbnail: URL? = nil, webpage: URL, streams: [MediaStream]
    ) {
        self.title = title
        self.uploader = uploader
        self.duration = duration
        self.thumbnail = thumbnail
        self.webpage = webpage
        self.streams = streams
    }

    public var maximumHeight: Int? { streams.compactMap(\.height).max() }
    public var hasAudio: Bool { streams.contains { $0.content != .videoOnly } }
}

/// What the downloader must fetch to satisfy a choice: one muxed stream, or a
/// video and an audio stream that have to be combined on the device.
public struct DownloadPlan: Equatable, Sendable {
    public var video: MediaStream?
    public var audio: MediaStream?
    public var title: String
    /// Set when the editable profile had to take a shorter stream than asked
    /// for, because the source offers no H.264 at the requested size. Silently
    /// handing back 1080p when the user picked 4K is how a download manager
    /// loses trust.
    public var downgradedTo: Int?
    public var needsMuxing: Bool { video != nil && audio != nil }

    public init(video: MediaStream?, audio: MediaStream?, title: String, downgradedTo: Int? = nil) {
        self.video = video
        self.audio = audio
        self.title = title
        self.downgradedTo = downgradedTo
    }

    public var notice: String? {
        guard let height = downgradedTo else { return nil }
        return "Esta fonte não oferece H.264 acima de \(height)p. Baixando em \(height)p "
            + "para abrir no Premiere e no After Effects. Desmarque \"Compatível com "
            + "Premiere\" para receber a resolução maior em AV1/VP9."
    }

    public var streams: [MediaStream] { [video, audio].compactMap { $0 } }
}
