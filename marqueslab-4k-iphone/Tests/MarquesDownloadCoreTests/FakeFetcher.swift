import Foundation
@testable import MarquesDownloadCore

/// Replays captured responses so parser tests never touch the network.
final class FakeFetcher: HTTPFetching, @unchecked Sendable {
    struct Reply { let status: Int; let body: Data; let headers: [String: String] }

    private(set) var requests: [URLRequest] = []
    var replies: [Reply]
    var error: Error?

    init(json: String, status: Int = 200) {
        replies = [Reply(status: status, body: Data(json.utf8), headers: ["Content-Type": "application/json"])]
    }

    init(replies: [Reply]) { self.replies = replies }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let error { throw error }
        let reply = replies.count > 1 ? replies.removeFirst() : (replies.first ?? Reply(status: 404, body: Data(), headers: [:]))
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status,
            httpVersion: "HTTP/1.1", headerFields: reply.headers
        )!
        return (reply.body, response)
    }
}
