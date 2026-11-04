import Foundation
import Observation

/// The only network path debrid keys can travel: HTTPS to the five provider API
/// hosts, no port or URL credentials, GET/POST/DELETE. Authorization is passed
/// through here and nowhere else; every other host is refused before connecting.
struct DebridTransport: HarborPluginHostTransport {
    var network: any HarborNativeNetworkCalling = HarborNativeNetwork()
    static let hosts = Set(DebridProvider.allCases.map(\.host))
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        guard kind == .http, let raw = payload["url"].string, let url = URL(string: raw), url.scheme == "https",
              Self.hosts.contains(url.host?.lowercased() ?? ""), url.port == nil, url.user == nil, url.password == nil,
              ["GET", "POST", "DELETE"].contains((payload["opts"]["method"].string ?? "GET").uppercased()) else { throw HarborError(code: "debrid-host") }
        let policy = HarborPluginNetworkPolicy(sameSiteHeaders: false, publicOnly: true, openHeaders: true, baseURL: nil, blockedHosts: [])
        return try await HarborNativePluginTransport(policy: policy, network: network).perform(kind, payload: payload)
    }
}

/// Profile-scoped access to the pinned original debrid clients. Keys live in the
/// Keychain per profile owner, are never synced, and are sent only to their own
/// provider host.
@MainActor @Observable final class DebridClient {
    let scope: PluginExecutionScope
    private(set) var keyFailure = false
    /// Changes whenever a key is saved or removed.
    private(set) var revision = UUID()
    @ObservationIgnored private let currentScope: @MainActor () -> PluginExecutionScope
    @ObservationIgnored private let transport: any HarborPluginHostTransport
    @ObservationIgnored private var keys: [DebridProvider: String] = [:]
    @ObservationIgnored private var runtime: HarborPluginRuntime?
    @ObservationIgnored private var disposed = false

    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope, transport: any HarborPluginHostTransport = DebridTransport()) {
        self.scope = scope; self.currentScope = currentScope; self.transport = transport
        for provider in DebridProvider.allCases {
            do { if let value = try KeychainStore().read(Self.keyName(provider, scope.owner), as: String.self), !value.isEmpty { keys[provider] = value } }
            catch { keyFailure = true }
        }
    }
    private static func keyName(_ provider: DebridProvider, _ owner: String) -> String { "debrid-key-" + provider.rawValue + "-" + EBookShelf.hash(owner) }

    var isDisposed: Bool { disposed }
    /// Providers with a saved key, in Desktop's order.
    var providers: [DebridProvider] { DebridProvider.allCases.filter { keys[$0] != nil } }
    func hasKey(_ provider: DebridProvider) -> Bool { keys[provider] != nil }

    func saveKey(_ supplied: String, for provider: DebridProvider) throws {
        try validate()
        let value = supplied.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 200,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else {
            throw HarborError(code: "debrid-key")
        }
        let name = Self.keyName(provider, scope.owner)
        if value.isEmpty { try KeychainStore().remove(name); keys[provider] = nil }
        else { try KeychainStore().write(value, key: name); keys[provider] = value }
        keyFailure = false; revision = UUID()
    }

    func account(_ provider: DebridProvider) async throws -> DebridOutcome<DebridAccount> {
        try await call("account", provider, as: DebridOutcome<DebridAccount>.self)
    }
    /// Desktop's cacheCheck; Real-Debrid and AllDebrid answer an empty map by design.
    func cacheCheck(_ provider: DebridProvider, hashes: [String]) async throws -> DebridOutcome<[String: Bool]> {
        guard hashes.count <= 200, hashes.allSatisfy({ $0.count <= 100 }) else { throw HarborError(code: "debrid-request") }
        return try await call("cacheCheck", provider, ["hashes": .array(hashes.map(JSONValue.string))], as: DebridOutcome<[String: Bool]>.self)
    }
    func playableURL(_ provider: DebridProvider, magnet: String, fileIdx: Int?, season: Int? = nil, episode: Int? = nil) async throws -> DebridOutcome<DebridLink> {
        guard !magnet.isEmpty, magnet.count <= 4_096 else { throw HarborError(code: "debrid-request") }
        let index: JSONValue = fileIdx.map { JSONValue.number(Double($0)) } ?? JSONValue.null
        var arguments: [String: JSONValue] = ["magnet": .string(magnet), "fileIdx": index]
        if let season, let episode { arguments["hint"] = .object(["season": .number(Double(season)), "episode": .number(Double(episode))]) }
        return try await call("playableUrl", provider, arguments, as: DebridOutcome<DebridLink>.self)
    }
    func queueCache(_ provider: DebridProvider, magnet: String) async throws -> DebridOutcome<DebridQueued> {
        guard !magnet.isEmpty, magnet.count <= 4_096 else { throw HarborError(code: "debrid-request") }
        return try await call("queueCache", provider, ["magnet": .string(magnet)], as: DebridOutcome<DebridQueued>.self)
    }
    func listLibrary(_ provider: DebridProvider) async throws -> DebridOutcome<[DebridLibraryEntry]> {
        try await call("listLibrary", provider, as: DebridOutcome<[DebridLibraryEntry]>.self)
    }

    private func call<T: Decodable & Sendable>(_ operation: String, _ provider: DebridProvider, _ arguments: [String: JSONValue] = [:], as type: T.Type) async throws -> T {
        try validate()
        guard let key = keys[provider] else { throw HarborError(code: "debrid-key-missing") }
        if runtime == nil {
            let asset = try DebridAsset.read()
            runtime = HarborPluginRuntime(id: "trusted-debrid", name: "Harbor Debrid", source: asset.program.source, format: .raw,
                                          scope: scope, currentScope: currentScope, transport: transport)
        }
        guard let runtime else { throw CancellationError() }
        let id = UUID().uuidString, version = revision
        var input = arguments
        input["operation"] = .string(operation); input["slug"] = .string(provider.rawValue); input["key"] = .string(key); input["requestId"] = .string(id)
        let result: JSONValue = try await withTaskCancellationHandler {
            do { return try await runtime.call("content", arguments: [.object(input)], timeout: 90) }
            catch { try validate(version); throw error }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, !self.disposed, self.scope == self.currentScope(), let runtime = self.runtime else { return }
                _ = try? await runtime.call("content", arguments: [.object(["operation": .string("cancel"), "requestId": .string(id)])], timeout: 10)
            }
        }
        try validate(version)
        return try JSONDecoder().decode(type, from: JSONEncoder().encode(result))
    }
    private func validate(_ version: UUID? = nil) throws {
        try Task.checkCancellation()
        guard !disposed, scope == currentScope() else { dispose(); throw CancellationError() }
        if let version, version != revision { throw CancellationError() }
    }
    func dispose() { guard !disposed else { return }; disposed = true; runtime?.dispose(); runtime = nil; keys = [:] }
}

/// One client per active profile, shared by Settings and the stream pipeline so a
/// key saved on the settings page is used by the next playback. A new profile
/// scope retires the previous client and its keys.
@MainActor final class DebridClientCache {
    static let shared = DebridClientCache()
    private var current: DebridClient?
    func client(for scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope) -> DebridClient {
        if let current, current.scope == scope, !current.isDisposed { return current }
        current?.dispose()
        let client = DebridClient(scope: scope, currentScope: currentScope)
        current = client
        return client
    }
}

extension AppModel {
    /// The active profile's debrid client, or nil while the app is locked.
    func debridClient() -> DebridClient? {
        guard let scope = pluginExecutionScope else { return nil }
        return DebridClientCache.shared.client(for: scope) { [weak self] in
            self?.pluginExecutionScope ?? PluginExecutionScope(owner: "locked", activation: scope.activation)
        }
    }
}