import Foundation

extension HTTPClient {
    static func simklArtworkRequest(_ id: Int) throws -> URLRequest {
        guard id > 0 else { throw HarborError(code: "anime-id") }
        // Public application identity shipped by Desktop, not a personal account token.
        let client = "9609ef0a6051b6fdcf3290fd962fd65e0f8e969c942555410cffd37afca91997"
        var url = URLComponents(string: "https://api.simkl.com/anime/\(id)")!
        url.queryItems = [URLQueryItem(name: "client_id", value: client), URLQueryItem(name: "app-name", value: "harbor"), URLQueryItem(name: "app-version", value: "0.9.132")]
        var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(client, forHTTPHeaderField: "simkl-api-key")
        request.setValue("Harbor-iOS/0.1 (Desktop 0.9.132)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

/// Only anonymous artwork identifiers. Share Desktop's GET spacing and app cooldown.
actor SimklArtworkCatalog {
    static let shared = SimklArtworkCatalog()
    typealias Fetch = @Sendable (Int) async throws -> JSONValue
    private let fetch: Fetch
    private var pending: [Int: Task<JSONValue, Error>] = [:]
    private var cached: [Int: (JSONValue, Date)] = [:]
    private var tail: Task<Void, Never>?
    private var lastRequest = Date.distantPast
    private var blockedUntil = Date.distantPast
    init(fetch: @escaping Fetch = { try await HTTPClient().simklArtwork($0) }) { self.fetch = fetch }
    func response(_ id: Int) async throws -> JSONValue {
        guard id > 0 else { throw HarborError(code: "anime-id") }
        if let saved = cached[id], Date().timeIntervalSince(saved.1) < 3_600 { return saved.0 }
        if let task = pending[id] { return try await task.value }
        let previous = tail
        let task = Task<JSONValue, Error> { await previous?.value; return try await self.perform(id) }
        pending[id] = task; tail = Task { _ = try? await task.value }
        defer { pending[id] = nil }
        let value = try await task.value
        if cached.count >= 300, let oldest = cached.min(by: { $0.value.1 < $1.value.1 })?.key { cached[oldest] = nil }
        cached[id] = (value, Date()); return value
    }
    private func perform(_ id: Int) async throws -> JSONValue {
        guard Date() >= blockedUntil else { throw HarborError(code: "simkl-cooldown") }
        let delay = 0.11 - Date().timeIntervalSince(lastRequest)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        lastRequest = Date()
        do { return try await fetch(id) }
        catch let error as HarborError {
            if ["http-412", "http-429", "http-500", "http-502", "http-503"].contains(error.code) { blockedUntil = Date().addingTimeInterval(60) }
            throw error
        }
    }
}
