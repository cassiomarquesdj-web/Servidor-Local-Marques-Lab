import Foundation

/// Resolves a public Instagram post or reel.
///
/// Instagram serves progressive MP4s that already carry H.264 video and AAC
/// audio, so nothing has to be converted for Premiere or After Effects. What it
/// does **not** serve to an anonymous request is anything private: closed
/// accounts, restricted posts and stories simply are not returned, and there is
/// no legitimate way around that.
public struct InstagramExtractor: MediaExtractor {
    /// Public web app id the site itself sends; without it the JSON endpoint
    /// answers with an empty payload.
    static let appID = "936619743392459"
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    public let name = "Instagram"

    public init() {}

    public func canHandle(_ url: URL) -> Bool {
        url.normalizedHost == "instagram.com" && shortcode(from: url) != nil
    }

    public func shortcode(from url: URL) -> String? { Self.shortcode(from: url) }

    public static func shortcode(from url: URL) -> String? {
        let parts = Array(url.pathComponents.dropFirst())
        guard let index = parts.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }),
              let code = parts[safe: index + 1], !code.isEmpty
        else { return nil }
        return code
    }

    public func extract(_ url: URL, using fetcher: HTTPFetching) async throws -> ExtractedMedia {
        guard let code = Self.shortcode(from: url) else {
            throw ExtractorError("Não consegui identificar a publicação nesta URL do Instagram.")
        }

        let canonical = URL(string: "https://www.instagram.com/p/\(code)/")!
        // Each attempt records its own outcome. Reporting a status left over
        // from an earlier endpoint sends whoever debugs this down the wrong
        // path — the page can answer 200 and still carry no media at all.
        var servedPageWithoutMedia = false
        var lastStatus: Int?

        for candidate in [
            URL(string: "https://www.instagram.com/p/\(code)/?__a=1&__d=dis")!,
            canonical,
        ] {
            var request = URLRequest(url: candidate)
            request.setValue(Self.appID, forHTTPHeaderField: "X-IG-App-ID")
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await fetcher.data(for: request) else { continue }
            guard response.statusCode == 200 else {
                lastStatus = response.statusCode
                continue
            }
            if let media = try? Self.parse(data, webpage: canonical), !media.streams.isEmpty {
                return media
            }
            servedPageWithoutMedia = true
        }

        if servedPageWithoutMedia {
            throw ExtractorError(
                "O Instagram respondeu, mas a página pública não traz mais o endereço "
                + "da mídia: ela só é entregue a uma sessão autenticada. Contas "
                + "privadas, conteúdo restrito e stories nunca são entregues sem login."
            )
        }
        throw ExtractorError(
            (lastStatus.map { "O Instagram respondeu HTTP \($0)." } ?? "O Instagram não respondeu.")
            + " A publicação pode ter sido removida ou exigir login."
        )
    }

    /// Handles both shapes Instagram returns: the `items` payload of the web API
    /// and the older `graphql.shortcode_media`. Raw HTML is scanned for either.
    public static func parse(_ data: Data, webpage: URL) throws -> ExtractedMedia {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let media = parse(json: json, webpage: webpage) {
            return media
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ExtractorError("Resposta ilegível do Instagram.")
        }
        for key in ["\"items\":", "\"shortcode_media\":"] {
            guard let range = html.range(of: key) else { continue }
            let tail = String(html[range.lowerBound...])
            guard let object = embeddedObject(in: tail, after: key) else { continue }
            if let json = try? JSONSerialization.jsonObject(with: Data(object.utf8)) as? [String: Any],
               let media = parse(json: wrap(json, key: key), webpage: webpage) {
                return media
            }
        }
        throw ExtractorError("Não encontrei a mídia na resposta do Instagram.")
    }

    static func wrap(_ json: [String: Any], key: String) -> [String: Any] {
        key.contains("items") ? ["items": [json]] : ["graphql": ["shortcode_media": json]]
    }

    static func parse(json: [String: Any], webpage: URL) -> ExtractedMedia? {
        if let item = (json["items"] as? [[String: Any]])?.first {
            return fromItem(item, webpage: webpage)
        }
        if let node = (json["graphql"] as? [String: Any])?["shortcode_media"] as? [String: Any]
            ?? json["shortcode_media"] as? [String: Any] {
            return fromGraphQL(node, webpage: webpage)
        }
        return nil
    }

    static func fromItem(_ item: [String: Any], webpage: URL) -> ExtractedMedia? {
        let versions = item["video_versions"] as? [[String: Any]] ?? []
        // has_audio is false on genuinely silent clips; it is not proof of a
        // login wall, so it only drives the stream's audio codec.
        let hasAudio = (item["has_audio"] as? Bool) ?? true
        let streams: [MediaStream] = versions.compactMap { version in
            guard let link = version["url"] as? String, let url = URL(string: link) else { return nil }
            return MediaStream(
                url: url,
                content: .muxed,
                height: version["height"] as? Int,
                bitrate: version["bandwidth"] as? Int,
                videoCodec: "avc1",
                audioCodec: hasAudio ? "mp4a" : nil,
                fileExtension: "mp4"
            )
        }
        guard !streams.isEmpty else { return nil }

        let caption = (item["caption"] as? [String: Any])?["text"] as? String
        let user = (item["user"] as? [String: Any])?["username"] as? String
        return ExtractedMedia(
            title: MediaURL.safeFilename(caption?.components(separatedBy: "\n").first
                ?? "Instagram \(user ?? "")"),
            uploader: user,
            duration: item["video_duration"] as? Double,
            thumbnail: ((item["image_versions2"] as? [String: Any])?["candidates"] as? [[String: Any]])?
                .first.flatMap { ($0["url"] as? String).flatMap(URL.init(string:)) },
            webpage: webpage,
            streams: streams
        )
    }

    static func fromGraphQL(_ node: [String: Any], webpage: URL) -> ExtractedMedia? {
        guard let link = node["video_url"] as? String, let url = URL(string: link) else { return nil }
        let caption = ((node["edge_media_to_caption"] as? [String: Any])?["edges"] as? [[String: Any]])?
            .first.flatMap { (($0["node"] as? [String: Any])?["text"] as? String) }
        let user = (node["owner"] as? [String: Any])?["username"] as? String
        let stream = MediaStream(
            url: url,
            content: .muxed,
            height: (node["dimensions"] as? [String: Any])?["height"] as? Int,
            videoCodec: "avc1",
            audioCodec: (node["has_audio"] as? Bool) == false ? nil : "mp4a",
            fileExtension: "mp4"
        )
        return ExtractedMedia(
            title: MediaURL.safeFilename(caption?.components(separatedBy: "\n").first
                ?? "Instagram \(user ?? "")"),
            uploader: user,
            duration: node["video_duration"] as? Double,
            webpage: webpage,
            streams: [stream]
        )
    }

    /// Returns the balanced JSON object or array that follows `key`.
    static func embeddedObject(in text: String, after key: String) -> String? {
        guard let start = text.range(of: key)?.upperBound else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var result = ""
        var opener: Character?

        for character in text[start...] {
            if result.isEmpty, character == " " || character == "\n" { continue }
            if opener == nil {
                guard character == "{" || character == "[" else { return nil }
                opener = character
            }
            result.append(character)

            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "\"" { inString.toggle(); continue }
            if inString { continue }
            if character == "{" || character == "[" { depth += 1 }
            if character == "}" || character == "]" {
                depth -= 1
                if depth == 0 {
                    // An items array must be unwrapped to its first element.
                    if opener == "[", let data = result.data(using: .utf8),
                       let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
                       let first = array.first,
                       let encoded = try? JSONSerialization.data(withJSONObject: first) {
                        return String(data: encoded, encoding: .utf8)
                    }
                    return result
                }
            }
            if result.count > 4_000_000 { return nil }
        }
        return nil
    }
}
