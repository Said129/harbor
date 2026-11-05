import Foundation

/// Desktop's AniList session (`lib/anilist/types.ts`), kept in the Keychain for each profile.
/// Times are milliseconds since 1970, as on Desktop.
struct AniListSession: Codable, Equatable, Sendable {
    var accessToken: String
    var createdAt: Double
    var expiresAt: Double
    var userId: Int
    var userName: String
    var avatar: String?
    var valid: Bool {
        !accessToken.isEmpty && accessToken.utf8.count <= 8_192 && userId > 0 && !userName.isEmpty && createdAt.isFinite && expiresAt.isFinite
    }
    /// Desktop's `isAuthenticated`: a session counts until its expiry.
    func isActive(at now: Date = Date()) -> Bool { now.timeIntervalSince1970 * 1_000 < expiresAt }
}

struct AniListViewer: Equatable, Sendable {
    let id: Int
    let name: String
    let avatar: String?
    let siteURL: String?
}

struct AniListReply: Sendable {
    let status: Int
    let data: Data
    let retryAfter: String?
}

protocol AniListTransport: Sendable {
    func send(_ request: URLRequest) async throws -> AniListReply
}

struct AniListHTTPTransport: AniListTransport {
    func send(_ request: URLRequest) async throws -> AniListReply { try await HTTPClient().anilistReply(request) }
}

/// Desktop's `AnilistApiError`: an HTTP failure, or GraphQL errors reduced to their messages with status 200.
struct AniListAPIError: Error, Equatable, Sendable {
    let status: Int
    let body: String

    var isAuthenticationError: Bool {
        if status == 401 { return true }
        guard status == 400 || status == 200 else { return false }
        var messages = [body]
        if let data = body.data(using: .utf8), let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) {
            messages = parsed["errors"].array.map { $0["message"].string ?? "" }
        }
        return messages.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .range(of: #"^(invalid token|token (?:has )?expired|unauthenticated)\.?$"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

/// A message for the person connecting; Desktop shows these as the thrown text.
struct AniListUserError: Error, Equatable, Sendable {
    let message: String
}

/// Desktop's `anilistRequest` (`lib/anilist/client.ts`): one retry after a 429, GraphQL errors as failures.
struct AniListClient: Sendable {
    static let graphQLURL = URL(string: "https://graphql.anilist.co")!
    let transport: any AniListTransport
    var pause: @Sendable (TimeInterval) async -> Void = { seconds in _ = try? await Task.sleep(for: .seconds(seconds)) }

    func request(_ query: String, variables: [String: JSONValue] = [:], token: String?) async throws -> JSONValue {
        var request = URLRequest(url: Self.graphQLURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(["query": .string(query), "variables": .object(variables)]))

        var reply = try await transport.send(request)
        if reply.status == 429 {
            let advised = reply.retryAfter.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? 1
            await pause(advised.isFinite ? min(max(advised, 1), 30) : 1)
            reply = try await transport.send(request)
        }
        guard (200..<300).contains(reply.status) else {
            throw AniListAPIError(status: reply.status, body: String(decoding: reply.data.prefix(2_000), as: UTF8.self))
        }
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: reply.data) else {
            throw AniListAPIError(status: 200, body: "Missing GraphQL data")
        }
        let errors = json["errors"].array
        if !errors.isEmpty { throw AniListAPIError(status: 200, body: errors.map { $0["message"].string ?? "" }.joined(separator: "; ")) }
        guard json["data"] != .null else { throw AniListAPIError(status: 200, body: "Missing GraphQL data") }
        return json["data"]
    }

    func viewer(token: String) async throws -> AniListViewer {
        let data = try await request("query { Viewer { id name avatar { large medium } siteUrl } }", token: token)
        let viewer = data["Viewer"]
        guard let id = viewer["id"].integer, id > 0, let name = viewer["name"].string, !name.isEmpty else {
            throw AniListAPIError(status: 200, body: "Missing GraphQL data")
        }
        return AniListViewer(id: id, name: name, avatar: viewer["avatar"]["large"].string ?? viewer["avatar"]["medium"].string, siteURL: viewer["siteUrl"].string)
    }
}

/// Desktop's PIN-code sign-in (`lib/anilist/auth.ts`): AniList shows a code that Harbor's server trades for a token.
enum AniListAuth {
    static let clientID = "42941"
    static let authorizeBase = "https://anilist.co/api/v2/oauth/authorize"
    static let pinRedirect = "https://anilist.co/api/v2/oauth/pin"
    static let tokenExchange = URL(string: "https://bugs.harbor.site/v1/anilist/token")!
    static let siteURL = URL(string: "https://anilist.co")!
    /// Desktop assumes a year when the exchange does not say.
    static let defaultTokenSeconds: Double = 31_536_000

    static func authorizeURL() -> URL? {
        var parts = URLComponents(string: authorizeBase)
        parts?.queryItems = [URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "redirect_uri", value: pinRedirect),
                             URLQueryItem(name: "response_type", value: "code")]
        return parts?.url
    }

    /// The code from a pasted address (`?code=`) or the bare text, without surrounding quotes or spaces.
    static func extractCode(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let found = trimmed.range(of: #"[?&#]code=([^&\s#]+)"#, options: .regularExpression) {
            let raw = String(trimmed[found].dropFirst(6))
            return (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespacesAndNewlines))
    }

    static func exchange(_ code: String, transport: any AniListTransport) async throws -> String {
        var request = URLRequest(url: tokenExchange, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["code": code])
        let reply = try await transport.send(request)
        guard (200..<300).contains(reply.status) else {
            throw AniListUserError(message: "AniList rejected that code. Authorize again and paste the newest one.")
        }
        guard let token = (try? JSONDecoder().decode(JSONValue.self, from: reply.data))?["access_token"].string, !token.isEmpty else {
            throw AniListUserError(message: "AniList did not return a token. Try authorizing again.")
        }
        return token
    }

    /// Trades a pasted code for a session, as `completeAuthorization` does.
    static func session(from pasted: String, transport: any AniListTransport, now: Date = Date()) async throws -> AniListSession {
        let code = extractCode(pasted)
        guard !code.isEmpty else { throw AniListUserError(message: "Paste the code from AniList to continue") }
        let token = try await exchange(code, transport: transport)
        let viewer = try await AniListClient(transport: transport).viewer(token: token)
        let created = now.timeIntervalSince1970 * 1_000
        return AniListSession(accessToken: token, createdAt: created, expiresAt: created + defaultTokenSeconds * 1_000,
                              userId: viewer.id, userName: viewer.name, avatar: viewer.avatar)
    }
}
