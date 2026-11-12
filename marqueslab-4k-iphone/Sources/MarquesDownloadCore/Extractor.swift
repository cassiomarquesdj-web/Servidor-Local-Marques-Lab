import Foundation

/// The HTTP surface an extractor is allowed to use. Injecting it keeps every
/// parser test deterministic and offline: the fixtures are real responses
/// captured from the services, replayed without touching the network.
public protocol HTTPFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct ExtractorError: LocalizedError, Equatable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var errorDescription: String? { reason }
}

public protocol MediaExtractor: Sendable {
    /// Shown in diagnostics so a failure names the parser that produced it.
    var name: String { get }
    func canHandle(_ url: URL) -> Bool
    func extract(_ url: URL, using fetcher: HTTPFetching) async throws -> ExtractedMedia
}

/// Picks the first extractor that claims a URL. Order matters: the direct-media
/// fallback must come last, since it accepts almost anything.
public struct ExtractorRegistry: Sendable {
    public let extractors: [any MediaExtractor]

    public init(extractors: [any MediaExtractor]) {
        self.extractors = extractors
    }

    public static func standard() -> ExtractorRegistry {
        ExtractorRegistry(extractors: [
            YouTubeExtractor(),
            InstagramExtractor(),
            DirectMediaExtractor(),
        ])
    }

    public func extractor(for url: URL) throws -> any MediaExtractor {
        guard let match = extractors.first(where: { $0.canHandle(url) }) else {
            throw ExtractorError("Este site não é reconhecido pelo extrator embarcado.")
        }
        return match
    }

    public func extract(_ url: URL, using fetcher: HTTPFetching) async throws -> ExtractedMedia {
        try await extractor(for: url).extract(url, using: fetcher)
    }
}

extension URL {
    var normalizedHost: String {
        var host = self.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("m.") { host.removeFirst(2) }
        return host
    }
}
