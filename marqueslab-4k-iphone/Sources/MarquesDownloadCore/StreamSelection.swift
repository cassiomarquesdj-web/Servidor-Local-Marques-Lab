import Foundation

/// Picks the streams that satisfy a `MediaChoice`.
///
/// The editable profile prefers H.264 + AAC exactly like the desktop app: the
/// sources' "best" streams are usually VP9/AV1 with Opus audio, which play fine
/// but are rejected by Premiere and After Effects.
public enum StreamSelection {
    public enum Failure: LocalizedError, Equatable {
        case noStreams
        case noAudio
        case noVideo

        public var errorDescription: String? {
            switch self {
            case .noStreams: return "A fonte não ofereceu nenhum stream para download."
            case .noAudio: return "A fonte não ofereceu faixa de áudio."
            case .noVideo: return "A fonte não ofereceu faixa de vídeo."
            }
        }
    }

    public static func plan(for media: ExtractedMedia, choice: MediaChoice) throws -> DownloadPlan {
        guard !media.streams.isEmpty else { throw Failure.noStreams }

        if choice.kind == .audio {
            guard let audio = bestAudio(in: media.streams, editable: choice.editable) else {
                throw Failure.noAudio
            }
            return DownloadPlan(video: nil, audio: audio, title: media.title)
        }

        // A single stream that already carries both tracks is always preferable:
        // nothing has to be combined on the device.
        if let muxed = bestMuxed(in: media.streams, choice: choice) {
            return DownloadPlan(video: muxed, audio: nil, title: media.title)
        }

        guard let video = bestVideo(in: media.streams, choice: choice) else { throw Failure.noVideo }
        let audio = bestAudio(in: media.streams, editable: choice.editable)
        return DownloadPlan(
            video: video, audio: audio, title: media.title,
            downgradedTo: downgrade(chosen: video, media: media, choice: choice)
        )
    }

    /// The height the user could have had with the raw profile, when the
    /// editable one forced a smaller stream.
    static func downgrade(chosen: MediaStream, media: ExtractedMedia, choice: MediaChoice) -> Int? {
        guard choice.editable, let picked = chosen.height else { return nil }
        let raw = media.streams
            .filter { $0.content != .audioOnly && withinLimit($0, choice) }
            .compactMap(\.height)
            .max() ?? picked
        return raw > picked ? picked : nil
    }

    static func withinLimit(_ stream: MediaStream, _ choice: MediaChoice) -> Bool {
        guard let limit = choice.quality.maximumHeight else { return true }
        guard let height = stream.height else { return true }
        return height <= limit
    }

    static func bestMuxed(in streams: [MediaStream], choice: MediaChoice) -> MediaStream? {
        let candidates = streams.filter { $0.content == .muxed && withinLimit($0, choice) }
        let preferred = choice.editable ? candidates.filter(\.isEditableVideo) : candidates
        return rank(preferred.isEmpty ? candidates : preferred)
    }

    static func bestVideo(in streams: [MediaStream], choice: MediaChoice) -> MediaStream? {
        let candidates = streams.filter {
            ($0.content == .videoOnly || $0.content == .muxed) && withinLimit($0, choice)
        }
        let preferred = choice.editable ? candidates.filter(\.isEditableVideo) : candidates
        return rank(preferred.isEmpty ? candidates : preferred)
    }

    static func bestAudio(in streams: [MediaStream], editable: Bool) -> MediaStream? {
        let candidates = streams.filter { $0.content == .audioOnly }
        let preferred = editable ? candidates.filter(\.isEditableAudio) : candidates
        let pool = preferred.isEmpty ? candidates : preferred
        if let best = pool.max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }) { return best }
        // No audio-only stream: a muxed one still carries the audio track.
        return streams.first { $0.content == .muxed }
    }

    static func rank(_ streams: [MediaStream]) -> MediaStream? {
        streams.max { left, right in
            if (left.height ?? 0) != (right.height ?? 0) { return (left.height ?? 0) < (right.height ?? 0) }
            return (left.bitrate ?? 0) < (right.bitrate ?? 0)
        }
    }
}
