import Foundation
import CryptoKit

enum SimklEndpoint: Sendable {
    case pin, poll(String), anime(Int), detail(SimklMediaKind, Int), settings, library(SimklLibraryEndpoint), watch(SimklWatchEndpoint), playback
    var method: String { switch self { case .settings, .watch: "POST"; case .library(let endpoint): endpoint.method; default: "GET" } }
    func request(token: String? = nil) throws -> URLRequest {
        var request = try HTTPClient.simklArtworkRequest(1)
        var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        switch self {
        case .pin: url.path = "/oauth/pin"
        case .poll(let code):
            guard code.range(of: "^[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil else { throw HarborError(code: "simkl-pin") }
            url.path = "/oauth/pin/" + code
        case .anime(let id):
            guard id > 0 else { throw HarborError(code: "anime-id") }; url.path = "/anime/\(id)"
        case .detail(let kind, let id):
            guard id > 0 else { throw HarborError(code: "simkl-id") }
            url.path = "/\(kind == .movie ? "movies" : kind == .show ? "tv" : "anime")/\(id)"
        case .settings:
            guard let token, Self.validToken(token) else { throw HarborError(code: "simkl-not-connected") }
            url.path = "/users/settings"; request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case .playback:
            guard let token, Self.validToken(token) else { throw HarborError(code: "simkl-not-connected") }
            url.path = "/sync/playback"; url.queryItems = [URLQueryItem(name: "hide_watched", value: "true"), URLQueryItem(name: "limit", value: "40")]
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        case .library(let endpoint):
            guard let token, Self.validToken(token) else { throw HarborError(code: "simkl-not-connected") }
            url.path = endpoint.path; url.queryItems = (url.queryItems ?? []) + endpoint.query
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            if let body = try endpoint.body() {
                request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        case .watch(let endpoint):
            guard let token, Self.validToken(token), case .object = endpoint.body else { throw HarborError(code: "simkl-not-connected") }
            url.path = endpoint.path; request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(endpoint.body); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.url = url.url; request.httpMethod = method
        return request
    }
    static func validToken(_ token: String) -> Bool {
        !token.isEmpty && token.utf8.count <= 16_384 && token.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
    }
}
struct SimklReply: Sendable {
    let status: Int
    let data: Data
    var retryAfter: String? = nil
}
struct SimklAPIError: Error, Sendable {
    let status: Int
    var retryAt: Date? = nil
}
struct SimklRetryPolicy: Equatable, Sendable {
    enum Cooldown: String, Sendable { case app, user }
    let delay: TimeInterval
    let cooldown: Cooldown?
    static func resolve(status: Int, body: Data, retryAfter: String?, attempt: Int, now: Date, random: Double) -> Self {
        let error = (try? JSONDecoder().decode(JSONValue.self, from: body))?["error"].string
        var serverDelay: TimeInterval?
        if let value = retryAfter?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            if value.range(of: "^[0-9]+$", options: .regularExpression) != nil { serverDelay = Double(value) }
            else {
                let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0)
                format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                serverDelay = format.date(from: value)?.timeIntervalSince(now)
            }
            if serverDelay?.isFinite != true || (serverDelay ?? 0) < 0 { serverDelay = nil }
            if let value = serverDelay { serverDelay = min(value, max(0, 9_007_199_254_740.991 - now.timeIntervalSince1970)) }
        }
        if status == 429, error == "user_limit_exceeded" || error == "app_limit_exceeded" {
            return .init(delay: max(1, serverDelay ?? 60), cooldown: error == "user_limit_exceeded" ? .user : .app)
        }
        let base = status == 429 ? 1 : min(16, pow(2, Double(max(0, attempt))))
        let delay = max(base, status == 429 ? 0 : serverDelay ?? 0)
        if delay > 30 { return .init(delay: delay, cooldown: .app) }
        return .init(delay: delay + floor(min(0.999999, max(0, random)) * 1_000) / 1_000, cooldown: nil)
    }
}

/// One serialized public/account queue. A retired profile or replaced session
/// cannot send its queued request or publish an in-flight reply.
actor SimklClient {
    static let shared = SimklClient()
    typealias Transport = @Sendable (URLRequest) async throws -> SimklReply
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    typealias Lease = @Sendable () async -> Bool
    private let transport: Transport
    private let sleep: Sleep
    private let now: @Sendable () -> Date
    private let random: @Sendable () -> Double
    private var tail: Task<Void, Never>?
    private var lastGet = Date.distantPast, lastPost = Date.distantPast
    private var appCooldown: SimklAPIError?
    private var userCooldowns: [String: SimklAPIError] = [:]
    init(transport: @escaping Transport = { try await HTTPClient().simklReply($0) },
        sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) },
        now: @escaping @Sendable () -> Date = { Date() }, random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.transport = transport; self.sleep = sleep; self.now = now; self.random = random
    }
    func response(_ endpoint: SimklEndpoint, token: String? = nil, current: @escaping Lease = { true }) async throws -> JSONValue {
        try Task.checkCancellation()
        let request = try endpoint.request(token: token), previous = tail
        let identity = SHA256.hash(data: Data((token ?? "").utf8)).map { String(format: "%02x", $0) }.joined()
        let result = Task<JSONValue, Error> {
            await previous?.value
            return try await self.perform(request, identity: identity, current: current)
        }
        tail = Task { _ = try? await result.value }
        let value = try await result.value
        try Task.checkCancellation(); guard await current() else { throw CancellationError() }; return value
    }
    private func perform(_ request: URLRequest, identity: String, current: Lease) async throws -> JSONValue {
        guard await current() else { throw CancellationError() }
        if let blocked = appCooldown, (blocked.retryAt ?? .distantPast) > now() { throw blocked }
        userCooldowns = userCooldowns.filter { ($0.value.retryAt ?? .distantPast) > now() }
        if let blocked = userCooldowns[identity] { throw blocked }
        var reply: SimklReply?
        for attempt in 0...5 {
            try Task.checkCancellation(); guard await current() else { throw CancellationError() }
            let post = request.httpMethod != "GET", gap = post ? 1.05 : 0.11
            let delay = gap - now().timeIntervalSince(post ? lastPost : lastGet)
            if delay > 0 { try await sleep(delay) }
            guard await current() else { throw CancellationError() }
            if post { lastPost = now() } else { lastGet = now() }
            let response = try await transport(request); reply = response
            guard await current() else { throw CancellationError() }
            guard [429, 500, 502, 503].contains(response.status) else { break }
            let policy = SimklRetryPolicy.resolve(status: response.status, body: response.data, retryAfter: response.retryAfter, attempt: attempt, now: now(), random: random())
            if let cooldown = policy.cooldown {
                let error = SimklAPIError(status: response.status, retryAt: now().addingTimeInterval(policy.delay))
                if cooldown == .app { appCooldown = error }
                else {
                    if userCooldowns.count >= 300, let oldest = userCooldowns.min(by: { ($0.value.retryAt ?? .distantPast) < ($1.value.retryAt ?? .distantPast) })?.key { userCooldowns[oldest] = nil }
                    userCooldowns[identity] = error
                }
                throw error
            }
            if attempt < 5 { try await sleep(policy.delay) }
        }
        guard let reply else { throw HarborError(code: "network") }
        if reply.status == 412 {
            let error = SimklAPIError(status: 412, retryAt: now().addingTimeInterval(60)); appCooldown = error; throw error
        }
        guard (200..<300).contains(reply.status) else { throw SimklAPIError(status: reply.status) }
        if reply.status == 204 { return .null }
        guard let result = try? JSONDecoder().decode(JSONValue.self, from: reply.data) else { throw HarborError(code: "simkl-response") }
        return result
    }
}
