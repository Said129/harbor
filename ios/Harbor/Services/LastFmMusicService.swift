import CryptoKit
import Foundation
import Observation

struct LastFmMusicAccount: Codable, Sendable {
    let apiKey: String
    let secret: String
    var sessionKey: String?
    var username: String?
}

/// Parameters and signing retain Desktop's lastfm.rs protocol. CryptoKit
/// supplies its protocol-required MD5; HTTP stays on the native Rust executor.
enum LastFmMusicProtocol {
    static func signature(_ parameters: [String: String], secret: String) -> String {
        let message = parameters.keys.sorted().filter { !["format", "callback", "api_sig"].contains($0) }
            .map { $0 + (parameters[$0] ?? "") }.joined() + secret
        return Insecure.MD5.hash(data: Data(message.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func form(_ parameters: [String: String], secret: String) throws -> Data {
        var fields = parameters
        fields["api_sig"] = signature(parameters, secret: secret); fields["format"] = "json"
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed)!.replacingOccurrences(of: "%20", with: "+")
        }
        let data = Data(fields.keys.sorted().map { encode($0) + "=" + encode(fields[$0] ?? "") }.joined(separator: "&").utf8)
        guard data.count <= 64 * 1024 else { throw HarborError(code: "music-lastfm-request") }
        return data
    }
}

@MainActor @Observable final class LastFmMusicService {
    let scope: PluginExecutionScope
    private var stored: LastFmMusicAccount?
    private(set) var authorizationURL: URL?
    private(set) var storageFailure = false
    @ObservationIgnored private let currentScope: @MainActor () -> PluginExecutionScope
    @ObservationIgnored private let network: any HarborNativeNetworkCalling
    @ObservationIgnored private var version = UUID()
    @ObservationIgnored private var disposed = false
    @ObservationIgnored private var operations: [UUID: Task<HarborNetworkResponse, Error>] = [:]
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var tokenDate: Date?
    private var key: String { "music-lastfm-account-" + EBookShelf.hash(scope.owner) }
    var connected: Bool { !disposed && scope == currentScope() && stored?.sessionKey?.isEmpty == false }
    var username: String? { connected ? stored?.username : nil }
    var hasCredentials: Bool { !disposed && scope == currentScope() && stored != nil }
    var connectionRevision: UUID { version }
    init(scope: PluginExecutionScope, network: any HarborNativeNetworkCalling = HarborNativeNetwork(),
         currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.scope = scope; self.network = network; self.currentScope = currentScope
        do { stored = try KeychainStore().read(key, as: LastFmMusicAccount.self) }
        catch { storageFailure = true }
    }
    private func validate(_ expected: UUID? = nil) throws {
        try Task.checkCancellation()
        guard !disposed, scope == currentScope(), expected == nil || expected == version else { throw CancellationError() }
    }
    private func retireRequests() {
        version = UUID(); operations.values.forEach { $0.cancel() }; operations.removeAll()
        token = nil; tokenDate = nil; authorizationURL = nil
    }
    func dispose() { disposed = true; retireRequests(); stored = nil }
    func credentials() throws -> (String, String) { try validate(); return (stored?.apiKey ?? "", stored?.secret ?? "") }
    func saveCredentials(apiKey: String, secret: String) throws {
        try validate()
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines), secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !secret.isEmpty, apiKey.utf8.count <= 128, secret.utf8.count <= 128,
              !apiKey.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !secret.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw HarborError(code: "music-lastfm-credentials") }
        var next = LastFmMusicAccount(apiKey: apiKey, secret: secret)
        if stored?.apiKey == apiKey, stored?.secret == secret { next = stored ?? next }
        do { try KeychainStore().write(next, key: key) }
        catch { storageFailure = true; throw HarborError(code: "music-lastfm-storage") }
        retireRequests(); stored = next; storageFailure = false
    }
    func disconnect() throws {
        try validate()
        // Stop in-flight account writes even if storage removal fails.
        retireRequests()
        do { try KeychainStore().remove(key) }
        catch { storageFailure = true; throw HarborError(code: "music-lastfm-storage") }
        stored = nil; storageFailure = false
    }
    private func post(_ fields: [String: String], account: LastFmMusicAccount, version: UUID) async throws -> JSONValue {
        try validate(version)
        var request = HarborNetworkRequest(url: "https://ws.audioscrobbler.com/2.0/")
        request.method = "POST"; request.headers = ["Content-Type": "application/x-www-form-urlencoded"]
        request.bodyBase64 = try LastFmMusicProtocol.form(fields, secret: account.secret).base64EncodedString()
        request.followRedirects = false; request.publicNetworkOnly = true
        request.maxResponseBytes = 512 * 1024; request.strictLimit = true
        let id = UUID(), network = network, sending = request
        let task = Task { try await network.perform(sending) }; operations[id] = task
        defer { operations[id] = nil }
        do {
            let response = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try validate(version)
            guard response.ok, response.url == sending.url else { throw HarborError(code: "music-lastfm-unavailable") }
            let result = try JSONDecoder().decode(JSONValue.self, from: response.bytes())
            guard case .object = result, result["error"].integer == nil else { throw HarborError(code: "music-lastfm-unavailable") }
            return result
        } catch {
            try validate(version)
            if error is CancellationError { throw CancellationError() }
            throw HarborError(code: "music-lastfm-unavailable")
        }
    }
    func beginAuthorization() async throws -> URL {
        try validate(); retireRequests()
        guard let account = stored else { throw HarborError(code: "music-lastfm-credentials") }
        let expected = version
        let response = try await post(["api_key": account.apiKey, "method": "auth.getToken"], account: account, version: expected)
        guard let token = response["token"].string, !token.isEmpty, token.utf8.count <= 128 else { throw HarborError(code: "music-lastfm-auth") }
        var address = URLComponents(string: "https://www.last.fm/api/auth/")!
        address.queryItems = [.init(name: "api_key", value: account.apiKey), .init(name: "token", value: token)]
        guard let url = address.url else { throw HarborError(code: "music-lastfm-auth") }
        try validate(expected)
        self.token = token; tokenDate = Date(); authorizationURL = url
        return url
    }
    func completeAuthorization() async throws {
        try validate()
        guard let account = stored, let token, let date = tokenDate,
              (0...3600).contains(Date().timeIntervalSince(date)) else { throw HarborError(code: "music-lastfm-auth") }
        let expected = version
        let response = try await post(["api_key": account.apiKey, "method": "auth.getSession", "token": token], account: account, version: expected)
        guard let username = response["session"]["name"].string, !username.isEmpty, username.utf8.count <= 512,
              let session = response["session"]["key"].string, !session.isEmpty, session.utf8.count <= 512 else { throw HarborError(code: "music-lastfm-auth") }
        let connected = LastFmMusicAccount(apiKey: account.apiKey, secret: account.secret, sessionKey: session, username: username)
        try validate(expected)
        do { try KeychainStore().write(connected, key: key) }
        catch { storageFailure = true; throw HarborError(code: "music-lastfm-storage") }
        retireRequests(); stored = connected; storageFailure = false
    }
    func scrobble(_ track: MusicTrack, startedAt: UInt64) async throws {
        try validate()
        guard let account = stored, let session = account.sessionKey, !session.isEmpty else { return }
        let expected = version
        var fields = ["api_key": account.apiKey, "method": "track.scrobble", "artist": track.artist,
                      "track": track.title, "chosenByUser": "1", "duration": String(track.durationSeconds),
                      "sk": session, "timestamp": String(startedAt)]
        if let album = track.album?.trimmingCharacters(in: .whitespacesAndNewlines), !album.isEmpty { fields["album"] = album }
        _ = try await post(fields, account: account, version: expected)
    }
    var profileURL: URL? {
        guard let username else { return nil }
        return URL(string: "https://www.last.fm/user/")?.appendingPathComponent(username)
    }
}
