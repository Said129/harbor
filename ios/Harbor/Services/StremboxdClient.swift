import Foundation

/// Desktop's Stremboxd client (`lib/stremboxd/client.ts`). Every request goes through `StremboxdTransport`, so tests use canned replies.

struct StremboxdReply: Sendable {
    let status: Int
    let data: Data
}

protocol StremboxdTransport: Sendable {
    func send(_ request: URLRequest) async throws -> StremboxdReply
}

/// A Stremboxd failure. `status` 0 means no answer from the server; `code` is the server's machine code, such as `2FA_REQUIRED`.
struct StremboxdError: Error, Equatable, Sendable {
    let status: Int
    let code: String?
    let message: String

    static let unreachable = StremboxdError(status: 0, code: nil, message: "Could not reach Stremboxd. Check your connection.")
    static let unexpected = StremboxdError(status: 200, code: nil, message: "Unexpected response from Stremboxd.")
}

/// The live transport: ephemeral, no cookies, no cache, and only `https://api.stremboxd.com`.
struct StremboxdHTTPTransport: StremboxdTransport {
    static let maximumBytes = 8 * 1_024 * 1_024

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func send(_ request: URLRequest) async throws -> StremboxdReply {
        guard let url = request.url, StremboxdURL.allowed(url) else { throw StremboxdError.unreachable }
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse, data.count <= Self.maximumBytes else {
                throw StremboxdError.unreachable
            }
            return StremboxdReply(status: http.statusCode, data: data)
        } catch let error as StremboxdError {
            throw error
        } catch {
            throw StremboxdError.unreachable
        }
    }
}

struct StremboxdClient: Sendable {
    let transport: any StremboxdTransport

    func manifest(_ source: StremboxdSource) async throws -> JSONValue {
        guard let url = StremboxdURL.manifest(source) else { throw StremboxdError.unexpected }
        return try await getJSON(url)
    }

    /// One page of a catalog. Desktop's `skip` is `(page - 1) * 100`.
    func catalog(_ source: StremboxdSource, catalogID: String, skip: Int) async throws -> [Media] {
        guard let url = StremboxdURL.catalog(source, catalogID: catalogID, skip: skip) else { throw StremboxdError.unexpected }
        return StremboxdMapping.catalog(try await getJSON(url))
    }

    /// Desktop's `loginLetterboxd`. A second step shows up as the `2FA_REQUIRED` code on the error.
    func login(username: String, password: String, totp: String?, loginAt: Double) async throws -> StremboxdSession {
        guard let url = StremboxdURL.endpoint("/auth/login") else { throw StremboxdError.unexpected }
        let body = StremboxdMapping.loginBody(username: username, password: password, totp: totp)
        let value = try await postJSON(url, body: body)
        guard let session = StremboxdMapping.session(fromLogin: value, loginAt: loginAt) else { throw StremboxdError.unexpected }
        return session
    }

    /// Desktop's `updateLetterboxdPreferences`.
    func updatePreferences(token: String, preferences: JSONValue) async throws {
        guard let url = StremboxdURL.endpoint("/auth/preferences") else { throw StremboxdError.unexpected }
        _ = try await postJSON(url, body: .object(["userToken": .string(token), "preferences": preferences]))
    }

    /// Desktop's `resolveLetterboxdListPublic`: a public list address becomes a list reference.
    func resolveList(_ address: String) async throws -> StremboxdListRef {
        guard let url = StremboxdURL.endpoint("/auth/resolve-list-public") else { throw StremboxdError.unexpected }
        let value = try await postJSON(url, body: .object(["url": .string(address)]))
        guard let ref = StremboxdMapping.listRef(value) else { throw StremboxdError.unexpected }
        return ref
    }

    private func getJSON(_ url: URL) async throws -> JSONValue {
        try Self.json(try await transport.send(URLRequest(url: url)))
    }

    private func postJSON(_ url: URL, body: JSONValue) async throws -> JSONValue {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try Self.json(try await transport.send(request))
    }

    static func json(_ reply: StremboxdReply) throws -> JSONValue {
        guard (200..<300).contains(reply.status) else { throw failure(reply) }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: reply.data) else { throw StremboxdError.unexpected }
        return value
    }

    /// Desktop's `StremboxdApiError`, plus the `error` and `code` fields of Stremboxd's error body.
    static func failure(_ reply: StremboxdReply) -> StremboxdError {
        let parsed = (try? JSONDecoder().decode(JSONValue.self, from: reply.data)) ?? .null
        let text = String(decoding: reply.data.prefix(2_000), as: UTF8.self)
        let serverMessage = parsed["error"].string ?? ""
        let message = serverMessage.isEmpty ? text : serverMessage
        return StremboxdError(status: reply.status, code: parsed["code"].string, message: message)
    }
}

/// Where the Letterboxd session is kept. The Keychain holds the token only, never the password.
protocol StremboxdSessionPersistence: Sendable {
    func readSession() throws -> StremboxdSession?
    func writeSession(_ session: StremboxdSession?) throws
}

struct KeychainStremboxdSession: StremboxdSessionPersistence {
    let key: String

    /// One Keychain entry per profile, keyed by a hash of the owner as AniList does.
    init(owner: String) {
        key = "native-letterboxd-session-v1-" + EBookShelf.hash(owner)
    }

    func readSession() throws -> StremboxdSession? {
        try KeychainStore().read(key, as: StremboxdSession.self)
    }

    func writeSession(_ session: StremboxdSession?) throws {
        if let session {
            try KeychainStore().write(session, key: key)
        } else {
            try KeychainStore().remove(key)
        }
    }
}
