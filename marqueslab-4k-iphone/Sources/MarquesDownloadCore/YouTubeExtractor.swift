import Foundation

/// Resolves a YouTube watch page through the InnerTube player endpoint.
///
/// This is the fragile part of the product and it is deliberately structured to
/// be repaired quickly: the clients are a list, tried in order, and a broken one
/// is replaced by editing `clients` alone. YouTube changes which clients return
/// playable URLs every few weeks — the desktop app follows yt-dlp's nightly
/// channel for exactly this reason, and here that maintenance is ours.
public struct YouTubeExtractor: MediaExtractor {
    public struct Client: Sendable {
        public let name: String
        public let clientName: String
        public let clientVersion: String
        public let userAgent: String
        public let extra: [String: Any]

        public init(
            name: String, clientName: String, clientVersion: String,
            userAgent: String, extra: [String: Any] = [:]
        ) {
            self.name = name
            self.clientName = clientName
            self.clientVersion = clientVersion
            self.userAgent = userAgent
            self.extra = extra
        }
    }

    /// Clients whose streaming URLs come back usable without solving the player
    /// JavaScript challenge. First one that yields streams wins.
    public static let clients: [Client] = [
        Client(
            name: "visionos",
            clientName: "VISIONOS",
            clientVersion: "0.1",
            userAgent: "com.google.ios.youtube/19.36.4 (realityOS)",
            extra: ["deviceMake": "Apple", "deviceModel": "RealityDevice14,1", "osName": "visionOS", "osVersion": "1.3"]
        ),
        Client(
            name: "android_vr",
            clientName: "ANDROID_VR",
            clientVersion: "1.60.19",
            userAgent: "com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12)",
            extra: ["deviceMake": "Oculus", "deviceModel": "Quest 3", "osName": "Android", "osVersion": "12", "androidSdkVersion": 32]
        ),
        Client(
            name: "ios",
            clientName: "IOS",
            clientVersion: "20.03.02",
            userAgent: "com.google.ios.youtube/20.03.02 (iPhone16,2; U; CPU iOS 18_2_1 like Mac OS X)",
            extra: ["deviceMake": "Apple", "deviceModel": "iPhone16,2", "osName": "iPhone", "osVersion": "18.2.1.22C161"]
        ),
    ]

    static let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player")!

    public let name = "YouTube"

    public init() {}

    public func canHandle(_ url: URL) -> Bool {
        let host = url.normalizedHost
        return host == "youtube.com" || host == "youtu.be" || host == "youtube-nocookie.com"
    }

    /// Accepts watch?v=, youtu.be/ID, /shorts/ID, /embed/ID and /live/ID.
    public static func videoID(from url: URL) -> String? {
        if url.normalizedHost == "youtu.be" {
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : id
        }
        if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let value = query.first(where: { $0.name == "v" })?.value, !value.isEmpty {
            return value
        }
        let parts = url.pathComponents.dropFirst()
        for (index, part) in parts.enumerated() where ["shorts", "embed", "live", "v"].contains(part) {
            let next = Array(parts)[safe: index + 1]
            if let next, !next.isEmpty { return next }
        }
        return nil
    }

    public func extract(_ url: URL, using fetcher: HTTPFetching) async throws -> ExtractedMedia {
        guard let videoID = Self.videoID(from: url) else {
            throw ExtractorError("Não consegui identificar o vídeo nesta URL do YouTube.")
        }

        var lastProblem = "A fonte não devolveu nenhum stream."
        for client in Self.clients {
            do {
                let payload = try await request(videoID: videoID, client: client, fetcher: fetcher)
                let media = try Self.parse(payload, videoID: videoID, webpage: url)
                if !media.streams.isEmpty { return media }
            } catch let error as ExtractorError {
                lastProblem = error.reason
            }
        }
        throw ExtractorError(
            lastProblem + " O YouTube muda a entrega com frequência; "
            + "atualize o aplicativo para a versão mais recente."
        )
    }

    func request(videoID: String, client: Client, fetcher: HTTPFetching) async throws -> [String: Any] {
        var context: [String: Any] = [
            "clientName": client.clientName,
            "clientVersion": client.clientVersion,
            "hl": "pt-BR",
            "gl": "BR",
        ]
        context.merge(client.extra) { current, _ in current }

        let body: [String: Any] = [
            "videoId": videoID,
            "context": ["client": context],
            "contentCheckOk": true,
            "racyCheckOk": true,
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(client.clientName, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")

        let (data, response) = try await fetcher.data(for: request)
        guard response.statusCode == 200 else {
            throw ExtractorError("O YouTube respondeu HTTP \(response.statusCode).")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractorError("Resposta inesperada do YouTube.")
        }
        return json
    }

    public static func parse(_ json: [String: Any], videoID: String, webpage: URL) throws -> ExtractedMedia {
        if let status = (json["playabilityStatus"] as? [String: Any]),
           let state = status["status"] as? String, state != "OK" {
            let reason = (status["reason"] as? String) ?? state
            throw ExtractorError("O YouTube recusou a reprodução: \(reason)")
        }

        let details = json["videoDetails"] as? [String: Any] ?? [:]
        let streaming = json["streamingData"] as? [String: Any] ?? [:]
        let raw = ((streaming["formats"] as? [[String: Any]]) ?? [])
            + ((streaming["adaptiveFormats"] as? [[String: Any]]) ?? [])

        let streams = raw.compactMap(stream(from:))
        let thumbnails = (details["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]

        return ExtractedMedia(
            title: (details["title"] as? String) ?? "Vídeo do YouTube",
            uploader: details["author"] as? String,
            duration: Double((details["lengthSeconds"] as? String) ?? ""),
            thumbnail: (thumbnails?.last?["url"] as? String).flatMap(URL.init(string:)),
            webpage: webpage,
            streams: streams
        )
    }

    static func stream(from format: [String: Any]) -> MediaStream? {
        // A ciphered format carries signatureCipher instead of url: solving it
        // needs the player JavaScript, which this extractor deliberately avoids.
        guard let link = format["url"] as? String, let url = URL(string: link) else { return nil }

        let mime = (format["mimeType"] as? String) ?? ""
        let codecs = Self.codecs(in: mime)
        let isVideo = mime.hasPrefix("video/")
        let isAudio = mime.hasPrefix("audio/")
        let hasBoth = isVideo && codecs.count > 1

        let content: MediaStream.Content = hasBoth ? .muxed : (isAudio ? .audioOnly : .videoOnly)
        return MediaStream(
            url: url,
            content: content,
            height: format["height"] as? Int,
            bitrate: (format["bitrate"] as? Int).map { $0 / 1000 },
            videoCodec: isVideo ? codecs.first : nil,
            audioCodec: isAudio ? codecs.first : (hasBoth ? codecs.last : nil),
            fileExtension: mime.contains("webm") ? "webm" : (isAudio ? "m4a" : "mp4")
        )
    }

    static func codecs(in mimeType: String) -> [String] {
        guard let range = mimeType.range(of: "codecs=") else { return [] }
        return mimeType[range.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
            .filter { !$0.isEmpty }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
