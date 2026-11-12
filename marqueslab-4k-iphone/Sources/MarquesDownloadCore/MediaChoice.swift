import Foundation

/// What the user asked for. The desktop app offers MP3; on iOS the system has
/// no MP3 encoder, so the audio profile produces M4A/AAC — the format Premiere,
/// After Effects, Logic and Final Cut all import natively.
public struct MediaChoice: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case video, audio }

    public enum Quality: String, CaseIterable, Codable, Sendable {
        case best, p2160, p1440, p1080, p720

        public var maximumHeight: Int? {
            switch self {
            case .best: return nil
            case .p2160: return 2160
            case .p1440: return 1440
            case .p1080: return 1080
            case .p720: return 720
            }
        }

        public var label: String {
            switch self {
            case .best: return "Melhor disponível"
            case .p2160: return "2160p • 4K"
            case .p1440: return "1440p"
            case .p1080: return "1080p"
            case .p720: return "720p"
            }
        }
    }

    public var kind: Kind
    public var quality: Quality
    /// Guarantees H.264 + AAC, the combination Premiere and After Effects open.
    public var editable: Bool

    public init(kind: Kind, quality: Quality = .best, editable: Bool = true) {
        self.kind = kind
        self.quality = quality
        self.editable = editable
    }

    public static func video(_ quality: Quality = .best, editable: Bool = true) -> MediaChoice {
        MediaChoice(kind: .video, quality: quality, editable: editable)
    }

    public static func audio() -> MediaChoice {
        MediaChoice(kind: .audio, quality: .best, editable: true)
    }

    public var fileExtension: String { kind == .audio ? "m4a" : "mp4" }

    public var label: String {
        switch kind {
        case .audio: return "M4A • AAC"
        case .video: return "MP4 • \(quality.label)\(editable ? " • H.264" : "")"
        }
    }
}
