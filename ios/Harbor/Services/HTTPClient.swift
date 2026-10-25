import Foundation

private final class AccountRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct HTTPClient: Sendable {
    private static let sourceSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    private static let metadataSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    private static let accountSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: AccountRedirectPolicy(), delegateQueue: nil)
    }()
    private static let publicTVDBSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: AccountRedirectPolicy(), delegateQueue: nil)
    }()

    func post(_ value: String, body: JSONValue, timeout: TimeInterval = 30) async throws -> JSONValue {
        let allowed = ["login", "getUser", "addonCollectionGet", "addonCollectionSet", "datastoreMeta", "datastoreGet", "datastorePut"].map { "https://api.strem.io/api/\($0)" }
        guard allowed.contains(value), let url = URL(string: value) else { throw HarborError(code: "invalid-account-request") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: max(1, min(30, timeout)))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await receive(request, session: Self.accountSession)
    }

    func anilist(query: String, variables: JSONValue) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(JSONValue.object(["query": .string(query), "variables": variables]))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let result = try await receive(request, session: Self.metadataSession)
        guard result["errors"].array.isEmpty, result["data"] != .null else { throw HarborError(code: "anime-response") }
        return result["data"]
    }

    static func harborRequest(_ path: String, server: HarborIdentityServer, method: String = "GET", body: JSONValue? = nil, token: String? = nil) throws -> URLRequest {
        guard !server.retired else { throw HarborError(code: "harbor-server-retired") }
        let allowed: [String: String] = ["/identity/api/login": "POST", "/identity/api/token/refresh": "POST", "/identity/api/me": "GET", "/auth/logout": "POST", "/sync/v1/state": "GET", "/sync/v1/push": "POST", "/social/me/profile": "PATCH"]
        guard allowed[path] == method, let url = URL(string: server.base + "/themes/api" + path) else { throw HarborError(code: "invalid-account-request") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return request
    }

    func harbor(_ path: String, server: HarborIdentityServer, method: String = "GET", body: JSONValue? = nil, token: String? = nil) async throws -> JSONValue {
        let request = try Self.harborRequest(path, server: server, method: method, body: body, token: token)
        return try await receive(request, session: Self.accountSession)
    }

    func json(_ value: String, timeout: TimeInterval = 8, credentialed: Bool = false, accept: String = "application/json") async throws -> JSONValue {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme), ["application/json", "application/vnd.api+json"].contains(accept) else { throw HarborError(code: "invalid-url") }
        var request = URLRequest(url: url, cachePolicy: credentialed ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy, timeoutInterval: max(15, timeout))
        request.setValue(accept, forHTTPHeaderField: "Accept")
        for attempt in 0..<2 {
            do { return try await receive(request, session: credentialed ? Self.accountSession : Self.metadataSession) }
            catch let error as HarborError {
                guard attempt == 0, error.code == "network" || error.code == "http-429" || error.code.hasPrefix("http-5") else { throw error }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw HarborError(code: "network")
    }

    func malCatalog(path: String, parameters: [String: String], clientID: String) async throws -> JSONValue {
        let seasonal = path.range(of: #"^/anime/season/[0-9]{4}/(winter|spring|summer|fall)$"#, options: .regularExpression) != nil
        guard path == "/anime/ranking" || seasonal,
              clientID.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else { throw HarborError(code: "invalid-anime-request") }
        var components = URLComponents(string: "https://api.myanimelist.net/v2" + path)!
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue(clientID, forHTTPHeaderField: "X-MAL-CLIENT-ID")
        // Public application identity stays on MAL; this session rejects redirects and has no cookies.
        return try await receive(request, session: Self.accountSession)
    }

    static func traktListRequest(id: String, page: Int) throws -> URLRequest {
        guard id.range(of: #"^[0-9]{1,18}$"#, options: .regularExpression) != nil,
              let number = Int64(id), number > 0, (1...1_000).contains(page) else { throw HarborError(code: "custom-source-list") }
        let url = URL(string: "https://api.trakt.tv/lists/\(number)/items?page=\(page)&limit=20")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        // This public application identifier is the one shipped by Desktop 0.9.132.
        request.setValue("71ef7ea86333eab031c8830f8200df1f2f16ef9a3335a67470be4950ac80b925", forHTTPHeaderField: "trakt-api-key")
        return request
    }
    func traktList(id: String, page: Int) async throws -> JSONValue {
        // Public folders explicitly omit OAuth. The anonymous session has no
        // cookies/credential storage and rejects redirects to other origins.
        try await receive(Self.traktListRequest(id: id, page: page), session: Self.publicTVDBSession)
    }
    func sourceDocument(_ raw: String) async throws -> JSONValue {
        guard let parts = URLComponents(string: raw), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil, let url = parts.url else { throw HarborError(code: "custom-source-import") }
        return try await receive(URLRequest(url: url, timeoutInterval: 20), session: Self.sourceSession, maximumBytes: 96 * 1_024)
    }

    static func tvdbRequest(_ endpoint: TVDBRequest) throws -> URLRequest {
        let base = "https://harborcommunity.site/api/tvdb/v4"
        let path = try endpoint.path
        guard let url = URL(string: base + path) else { throw HarborError(code: "tvdb-request") }
        return URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    }

    func tvdb(_ endpoint: TVDBRequest) async throws -> JSONValue {
        let request = try Self.tvdbRequest(endpoint)
        for attempt in 0..<2 {
            do { return try await receive(request, session: Self.publicTVDBSession, requireJSON: true) }
            catch let error as HarborError {
                guard attempt == 0, error.code == "network" || error.code == "http-429" || error.code.hasPrefix("http-5") else { throw error }
                try await Task.sleep(for: .milliseconds(350))
            }
        }
        throw HarborError(code: "network")
    }

    private func receive(_ input: URLRequest, session: URLSession, requireJSON: Bool = false, maximumBytes: Int = 8 * 1024 * 1024) async throws -> JSONValue {
        var request = input
        if request.value(forHTTPHeaderField: "Accept") == nil { request.setValue("application/json", forHTTPHeaderField: "Accept") }
        request.setValue("Harbor-iOS/0.1", forHTTPHeaderField: "User-Agent")
        await Diagnostics.shared.record(.requestStarted)
        do {
            // Streaming bytes caps metadata payloads before allocating an unbounded Data.
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw HarborError(code: "invalid-http-response") }
            guard (200..<300).contains(response.statusCode) else { throw HarborError(code: "http-\(response.statusCode)") }
            if requireJSON, response.mimeType?.lowercased() != "application/json" { throw HarborError(code: "tvdb-response") }
            let limit = maximumBytes
            guard response.expectedContentLength <= Int64(limit) else { throw HarborError(code: "response-too-large") }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { throw HarborError(code: "response-too-large") }
                data.append(byte)
            }
            let json = try JSONDecoder().decode(JSONValue.self, from: data)
            await Diagnostics.shared.record(.requestCompleted, count: data.count)
            return json
        } catch let error as HarborError {
            await Diagnostics.shared.recordFailure(error)
            throw error
        }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch {
            let safe = HarborError(code: "network") // Foundation descriptions may include secret URLs.
            await Diagnostics.shared.recordFailure(safe)
            throw safe
        }
    }
}
