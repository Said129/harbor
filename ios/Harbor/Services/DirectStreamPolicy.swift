import Foundation

enum DirectStreamPolicy {
    private static let videoExtension = #"\.(mkv|mp4|avi|mov|m4v|webm|ts|m3u8|mpd|flv|wmv|m2ts|mpg|mpeg|ogv|3gp)(\?|#|$)"#
    private static let deadline: TimeInterval = 3.5
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = deadline
        configuration.timeoutIntervalForResource = deadline
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: DirectStreamRedirects(), delegateQueue: nil)
    }()

    static func probeRequest(url: String, headers: [String: String]?, userCommitted: Bool, hasHash: Bool) -> URLRequest? {
        guard !userCommitted, !hasHash,
              url.range(of: videoExtension, options: [.regularExpression, .caseInsensitive]) == nil,
              let target = URL(string: url), allowed(target) else { return nil }
        var request = URLRequest(url: target, timeoutInterval: deadline)
        request.httpMethod = "HEAD"
        request.allHTTPHeaderFields = headers
        return request
    }

    static func isWebPage(_ request: URLRequest) async -> Bool {
        guard let (_, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse else { return false }
        return isWebPage(response)
    }

    static func isWebPage(_ response: HTTPURLResponse) -> Bool {
        guard (200..<300).contains(response.statusCode) else { return false }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return contentType.hasPrefix("text/html") || contentType.hasPrefix("application/xhtml")
    }

    static func redirect(from original: URL?, response: URL?, to request: URLRequest) -> URLRequest? {
        guard let original, let response, let target = request.url, allowed(target),
              response.scheme?.lowercased() != "https" || target.scheme?.lowercased() == "https" else { return nil }
        var next = request
        next.httpMethod = "HEAD"
        if !MangaServer.sameOrigin(original, target) || !MangaServer.sameOrigin(response, target) {
            next.allHTTPHeaderFields = [:]
        }
        return next
    }

    private static func allowed(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }
}

private final class DirectStreamRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(DirectStreamPolicy.redirect(from: task.originalRequest?.url, response: response.url, to: request))
    }
}
