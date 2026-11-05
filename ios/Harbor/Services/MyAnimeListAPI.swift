import Foundation

typealias TrackerUserError = AniListUserError

/// Desktop's MyAnimeList session (`lib/mal/types.ts`), kept in the Keychain for each profile.
/// Times are milliseconds since 1970, as on Desktop.
struct MALSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var createdAt: Double
    var expiresAt: Double
    var userName: String
    var valid: Bool {
        !accessToken.isEmpty && accessToken.utf8.count <= 8_192 && refreshToken.utf8.count <= 8_192 && !userName.isEmpty
            && createdAt.isFinite && expiresAt.isFinite
    }
    /// Desktop's `isAuthenticated`: an access token counts until its expiry, after which it is refreshed.
    func isActive(at now: Date = Date()) -> Bool { now.timeIntervalSince1970 * 1_000 < expiresAt }
}

protocol MALTransport: Sendable {
    func send(_ request: URLRequest) async throws -> AniListReply
}

struct MALHTTPTransport: MALTransport {
    func send(_ request: URLRequest) async throws -> AniListReply { try await HTTPClient().malReply(request) }
}

struct MALAPIError: Error, Equatable, Sendable {
    let status: Int
    let body: String
}

/// Desktop's `malRequest` (`lib/mal/client.ts`): form-encoded writes, `/v2` paths.
struct MALClient: Sendable {
    static let apiBase = "https://api.myanimelist.net/v2"
    let transport: any MALTransport

    /// Desktop's `resolveMalRequestUrl`: a path already under the base is left as it is.
    static func resolve(_ path: String) -> String { path.hasPrefix(apiBase) ? path : apiBase + path }

    static func formBody(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._*"))
        func encode(_ text: String) -> String { (text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text).replacingOccurrences(of: "%20", with: "+") }
        return Data(fields.map { encode($0.0) + "=" + encode($0.1) }.joined(separator: "&").utf8)
    }

    func request(_ path: String, method: String = "GET", form: [(String, String)] = [], token: String) async throws -> JSONValue {
        guard let url = URL(string: Self.resolve(path)) else { throw MALAPIError(status: 0, body: "Invalid address") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if !form.isEmpty {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody(form)
        }
        let reply = try await transport.send(request)
        guard (200..<300).contains(reply.status) else {
            throw MALAPIError(status: reply.status, body: String(decoding: reply.data.prefix(2_000), as: UTF8.self))
        }
        return (try? JSONDecoder().decode(JSONValue.self, from: reply.data)) ?? .null
    }

    func userName(token: String) async -> String {
        let name = (try? await request("/users/@me", token: token))?["name"].string
        return name ?? "unknown"
    }
}

/// Desktop's MyAnimeList sign-in (`lib/mal/auth.ts`): authorization code with a plain PKCE challenge,
/// shown on Harbor's page and traded for tokens by Harbor's server.
enum MALAuth {
    static let clientID = "879be1ac300dc70611e5c828fec7bc18"
    static let authorizeBase = "https://myanimelist.net/v1/oauth2/authorize"
    static let tokenProxy = URL(string: "https://harbor.site/api/mal/token")!
    static let siteURL = URL(string: "https://myanimelist.net")!
    /// A month, when the server does not say.
    static let defaultTokenSeconds: Double = 2_678_400

    static func makeVerifier() -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<64).map { _ in characters[Int(generator.next() % UInt64(characters.count))] })
    }

    static func authorizeURL(verifier: String) -> URL? {
        var parts = URLComponents(string: authorizeBase)
        parts?.queryItems = [URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: clientID),
                             URLQueryItem(name: "code_challenge", value: verifier), URLQueryItem(name: "code_challenge_method", value: "plain")]
        return parts?.url
    }

    static func extractCode(_ input: String) -> String { AniListAuth.extractCode(input) }

    private static func post(_ fields: [String: String], transport: any MALTransport) async throws -> AniListReply {
        var request = URLRequest(url: tokenProxy, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(fields)
        return try await transport.send(request)
    }

    private static func session(from reply: AniListReply, userName: String, now: Date) -> MALSession? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: reply.data), let access = json["access_token"].string, !access.isEmpty else { return nil }
        let seconds = json["expires_in"].textValue.flatMap(Double.init).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? defaultTokenSeconds
        let created = now.timeIntervalSince1970 * 1_000
        return MALSession(accessToken: access, refreshToken: json["refresh_token"].string ?? "", createdAt: created, expiresAt: created + seconds * 1_000, userName: userName)
    }

    /// Trades a pasted code (or the page address that carries it) for a session, as `completeAuthorization` does.
    static func session(from pasted: String, verifier: String?, transport: any MALTransport, now: Date = Date()) async throws -> MALSession {
        let code = extractCode(pasted)
        guard !code.isEmpty else { throw TrackerUserError(message: "Paste the code from MyAnimeList to continue") }
        guard let verifier, !verifier.isEmpty else { throw TrackerUserError(message: "Session expired. Start over and authorize again.") }
        let reply = try await post(["grant_type": "authorization_code", "code": code, "code_verifier": verifier], transport: transport)
        guard (200..<300).contains(reply.status) else {
            throw TrackerUserError(message: "MAL rejected that code (HTTP \(reply.status)): \(String(decoding: reply.data.prefix(200), as: UTF8.self))")
        }
        guard let access = (try? JSONDecoder().decode(JSONValue.self, from: reply.data))?["access_token"].string, !access.isEmpty else {
            throw TrackerUserError(message: "MAL did not return a token. Try authorizing again.")
        }
        let name = await MALClient(transport: transport).userName(token: access)
        guard let made = session(from: reply, userName: name, now: now) else { throw TrackerUserError(message: "MAL did not return a token. Try authorizing again.") }
        return made
    }

    /// Desktop's `refreshAccessToken`: nil when MyAnimeList no longer accepts the refresh token; a thrown error
    /// means the server could not be reached and the session should be kept.
    static func refreshed(_ current: MALSession, transport: any MALTransport, now: Date = Date()) async throws -> MALSession? {
        guard !current.refreshToken.isEmpty else { return nil }
        let reply = try await post(["grant_type": "refresh_token", "refresh_token": current.refreshToken], transport: transport)
        guard (200..<300).contains(reply.status), var next = session(from: reply, userName: current.userName, now: now) else { return nil }
        if next.refreshToken.isEmpty { next.refreshToken = current.refreshToken }
        return next
    }
}

/// What to do with the list entry once a watched episode number is known (Desktop's `syncMalProgress`).
enum MALSyncPlan: Equatable, Sendable {
    case skip
    case remember(Int)
    case save(watched: Int, status: String)

    static func progress(status: String?, isRewatching: Bool, current: Int, total: Int, target: Int) -> MALSyncPlan {
        if status == "completed" || isRewatching { return .skip }
        if total > 0 && target > total { return .skip }
        if target <= current { return .remember(current) }
        return .save(watched: target, status: total > 0 && target >= total ? "completed" : "watching")
    }

    /// A Plan to watch entry moves to Watching; anything already under way is left alone.
    static func marksWatching(hasEntry: Bool, status: String?, watched: Int, total: Int) -> Bool {
        guard hasEntry else { return true }
        if status != "plan_to_watch" { return false }
        return !(total > 0 && watched >= total)
    }
}
