import Foundation

/// Input handling, mirrored from the desktop engine so both products accept
/// exactly the same things: one URL per line, duplicates collapsed, order kept.
public enum MediaURL {
    public enum Failure: LocalizedError, Equatable {
        case empty
        case notHTTP(String)

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "Cole pelo menos uma URL."
            case .notHTTP(let value):
                return "\"\(value)\" não é uma URL HTTP/HTTPS válida."
            }
        }
    }

    /// Trims and validates a single URL.
    public static func normalize(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty
        else { throw Failure.notHTTP(trimmed) }
        return url
    }

    /// Splits pasted text into URLs, preserving order and dropping repeats.
    public static func split(_ text: String) throws -> [URL] {
        let candidates = text
            .components(separatedBy: CharacterSet(charactersIn: "\n\r\t"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !candidates.isEmpty else { throw Failure.empty }

        var seen = Set<String>()
        var urls: [URL] = []
        for candidate in candidates {
            let url = try normalize(candidate)
            if seen.insert(url.absoluteString).inserted { urls.append(url) }
        }
        return urls
    }

    /// A file name the Files app and Photos will accept.
    public static func safeFilename(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = name
            .components(separatedBy: forbidden)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        let limited = String(cleaned.prefix(120))
        return limited.isEmpty ? "Marques Lab Mídia" : limited
    }
}
