import Foundation

private final class AccountRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct HTTPClient: Sendable {
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

    func post(_ value: String, body: JSONValue) async throws -> JSONValue {
        let allowed = ["login", "getUser", "addonCollectionGet", "addonCollectionSet", "datastoreMeta", "datastoreGet", "datastorePut"].map { "https://api.strem.io/api/\($0)" }
        guard allowed.contains(value), let url = URL(string: value) else { throw HarborError(code: "invalid-account-request") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
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

    func harbor(_ path: String, method: String = "GET", body: JSONValue? = nil, token: String? = nil) async throws -> JSONValue {
        let allowed: [String: String] = ["/identity/api/login": "POST", "/identity/api/token/refresh": "POST", "/identity/api/me": "GET", "/auth/logout": "POST", "/sync/v1/state": "GET", "/sync/v1/push": "POST", "/social/me/profile": "PATCH"]
        guard allowed[path] == method, let url = URL(string: "https://harbor.site/themes/api" + path) else { throw HarborError(code: "invalid-account-request") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return try await receive(request, session: Self.accountSession)
    }

    func json(_ value: String, timeout: TimeInterval = 8, credentialed: Bool = false) async throws -> JSONValue {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme) else { throw HarborError(code: "invalid-url") }
        let request = URLRequest(url: url, cachePolicy: credentialed ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy, timeoutInterval: max(15, timeout))
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

    private func receive(_ input: URLRequest, session: URLSession) async throws -> JSONValue {
        var request = input
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Harbor-iOS/0.1", forHTTPHeaderField: "User-Agent")
        await Diagnostics.shared.record(.requestStarted)
        do {
            // Streaming bytes caps metadata payloads before allocating an unbounded Data.
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw HarborError(code: "invalid-http-response") }
            guard (200..<300).contains(response.statusCode) else { throw HarborError(code: "http-\(response.statusCode)") }
            let limit = 8 * 1024 * 1024
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
