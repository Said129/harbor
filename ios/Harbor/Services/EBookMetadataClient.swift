import CryptoKit
import Foundation
import Observation

private struct EBookMetadataTransport: HarborPluginHostTransport {
    let network: any HarborNativeNetworkCalling
    let progress: @MainActor @Sendable (String, JSONValue) -> Void
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        guard kind == .http, let raw = payload["url"].string, let url = URL(string: raw) else { throw HarborPluginRuntimeError("ebook-metadata-request") }
        if url.scheme == "harbor", url.host == "book-metadata-progress" {
            guard let body = payload["opts"]["body"].string, body.utf8.count <= 2 * 1024 * 1024 else { throw HarborPluginRuntimeError("ebook-metadata-progress") }
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(body.utf8))
            await progress(url.lastPathComponent, value)
            return .object(["ok": .bool(true), "status": .integer(204), "headers": .object([:]), "body": .string("")])
        }
        let hosts: Set<String> = ["graphql.anilist.co", "www.googleapis.com", "openlibrary.org", "query.wikidata.org", "www.wikidata.org", "api.mangadex.org"]
        let host = url.host?.lowercased() ?? ""
        guard url.scheme == "https", hosts.contains(host) || host.hasSuffix(".wikipedia.org") else { throw HarborPluginRuntimeError("ebook-metadata-host") }
        let policy = HarborPluginNetworkPolicy(sameSiteHeaders: false, publicOnly: true, openHeaders: false, baseURL: nil, blockedHosts: [])
        return try await HarborNativePluginTransport(policy: policy, network: network).perform(kind, payload: payload)
    }
}

@MainActor @Observable final class EBookMetadataClient {
    private struct Asset: Decodable {
        struct Program: Decodable { let source: String; let sha256: String }
        let schema: Int; let reference: String; let inputs: [String: String]; let program: Program
    }
    let scope: PluginExecutionScope
    private let currentScope: @MainActor () -> PluginExecutionScope
    private let network: any HarborNativeNetworkCalling
    private let cache: EBookMetadataCache
    private var runtime: HarborPluginRuntime?
    private var starting: (id: UUID, task: Task<HarborPluginRuntime, Error>)?
    private var flushing: Task<Void, Never>?
    private var callbacks: [String: @MainActor (JSONValue) async -> Void] = [:]
    private var disposed = false
    private var language: String
    private let fixedLanguage: Bool
    private(set) var googleKey: String
    private(set) var active = 0
    private(set) var revision = 0
    var busy: Bool { active > 0 }
    private var keyName: String { "ebook-google-key-" + EBookShelf.hash(scope.owner) }

    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
         network: any HarborNativeNetworkCalling = HarborNativeNetwork(), cache: EBookMetadataCache? = nil, googleKey: String? = nil, language: String? = nil) throws {
        self.scope = scope; self.currentScope = currentScope; self.network = network
        self.cache = try cache ?? EBookMetadataCache(owner: scope.owner)
        self.language = language ?? InterfaceLanguage.resolve(UserDefaults.standard.string(forKey: "uiLanguage") ?? "es")
        fixedLanguage = language != nil
        self.googleKey = try googleKey ?? KeychainStore().read("ebook-google-key-" + EBookShelf.hash(scope.owner), as: String.self) ?? ""
    }
    private func validate() throws { try Task.checkCancellation(); guard !disposed, scope == currentScope() else { throw CancellationError() } }
    private func worker() async throws -> HarborPluginRuntime {
        try validate()
        if let runtime, !runtime.isDisposed { return runtime }
        let task: Task<HarborPluginRuntime, Error>
        let ticket: UUID
        if let starting { ticket = starting.id; task = starting.task }
        else {
            ticket = UUID()
            task = Task {
                let held = (try? await self.cache.load()) ?? [:]
                try self.validate()
                guard let url = Bundle.main.url(forResource: "EBookMetadataAssets", withExtension: "json") else { throw HarborPluginRuntimeError("ebook-metadata-assets") }
                let asset = try JSONDecoder().decode(Asset.self, from: Data(contentsOf: url))
                let hash = SHA256.hash(data: Data(asset.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
                guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987", asset.inputs.count == 6,
                      hash == asset.program.sha256, hash == "6084b096042afdcf493c309b77b5885f25481478861c6981baa5afd23615f531" else { throw HarborPluginRuntimeError("ebook-metadata-assets") }
                let transport = EBookMetadataTransport(network: self.network) { [weak self] id, value in
                    Task { [weak self] in
                        guard let self else { return }
                        do { try self.validate() } catch { return }
                        guard let callback = self.callbacks[id] else { return }
                        await callback(value)
                    }
                }
                let runtime = HarborPluginRuntime(id: "trusted-ebook-metadata", name: "Harbor Books", source: asset.program.source, format: .raw,
                    configuration: .object(["language": .string(self.language), "googleKey": .string(self.googleKey), "cache": .object(held.mapValues(JSONValue.string))]),
                    scope: self.scope, currentScope: self.currentScope, transport: transport)
                do { _ = try await runtime.metadata(); try self.validate(); self.runtime = runtime; return runtime }
                catch { runtime.dispose(); throw error }
            }
            starting = (ticket, task)
        }
        defer { if starting?.id == ticket { starting = nil } }
        let result = try await task.value; try validate(); return result
    }
    func query(_ operation: String, arguments: [String: JSONValue] = [:], onPartial: (@MainActor (JSONValue) async -> Void)? = nil) async throws -> JSONValue {
        try validate()
        if !fixedLanguage {
            let selected = InterfaceLanguage.resolve(UserDefaults.standard.string(forKey: "uiLanguage") ?? "es")
            if selected != language { retireRuntime(); language = selected; revision += 1 }
        }
        let id = UUID().uuidString
        let current = try await worker()
        active += 1
        if let onPartial { callbacks[id] = onPartial }
        defer { callbacks[id] = nil; active = max(0, active - 1) }
        var input = arguments; input["operation"] = .string(operation)
        if onPartial != nil { input["requestID"] = .string(id) }
        let result = try await current.call("content", arguments: [.object(input)], timeout: 120)
        try validate()
        if operation != "snapshot" && operation != "map" && operation != "merge" { scheduleFlush() }
        return result
    }
    private func scheduleFlush() {
        guard flushing == nil else { return }
        flushing = Task {
            defer { self.flushing = nil }
            do { try await Task.sleep(for: .milliseconds(600)); try await self.flush() } catch {}
        }
    }
    func flush() async throws {
        try validate(); guard let runtime else { return }
        let result = try await runtime.call("content", arguments: [.object(["operation": .string("snapshot")])], timeout: 10)
        try validate(); try await cache.save(result.objectValue.compactMapValues(\.string)); try validate()
    }
    func saveGoogleKey(_ value: String) async throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try validate()
        if !key.isEmpty { _ = try await query("validate-key", arguments: ["key": .string(key)]) }
        retireRuntime()
        let held = (try? await cache.load()) ?? [:]
        try await cache.save(held.filter { $0.key != "harbor.ebook.metadata.v1" && !$0.key.contains(".authenticated.") })
        try validate()
        if key.isEmpty { try KeychainStore().remove(keyName) } else { try KeychainStore().write(key, key: keyName) }
        googleKey = key; revision += 1
    }
    func clearCache() async throws { try validate(); retireRuntime(); try await cache.clear(); try validate(); revision += 1 }
    private func retireRuntime() {
        starting?.task.cancel(); starting = nil; flushing?.cancel(); flushing = nil
        runtime?.dispose(); runtime = nil; callbacks = [:]
    }
    func dispose() { guard !disposed else { return }; disposed = true; retireRuntime(); active = 0 }

    func books(_ operation: String, arguments: [String: JSONValue] = [:], preserving originals: [EBook] = []) async throws -> [EBook] {
        EBookMetadataMapping.books(try await query(operation, arguments: arguments), preserving: originals)
    }
    func enrich(_ books: [EBook], onPartial: @escaping @MainActor ([EBook]) async -> Void) async throws -> [EBook] {
        let arguments: [String: JSONValue] = ["books": .array(books.map(EBookMetadataMapping.raw))]
        let cached = try await self.books("cached", arguments: arguments, preserving: books)
        try validate(); await onPartial(cached)
        let result = try await query("enrich", arguments: arguments) { value in
            await onPartial(EBookMetadataMapping.books(value, preserving: books))
        }
        return EBookMetadataMapping.books(result, preserving: books)
    }
}
