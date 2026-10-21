import CryptoKit
import Foundation
import Observation

@MainActor protocol HarborStreamPluginProbing {
    func methods(id: String, entry: HarborStreamPluginEntry, source: String, settings: [String: JSONValue],
        scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
        transport: any HarborPluginHostTransport) async throws -> [String]
}

@MainActor struct HarborNativeStreamPluginProbe: HarborStreamPluginProbing {
    func methods(id: String, entry: HarborStreamPluginEntry, source: String, settings: [String: JSONValue],
        scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
        transport: any HarborPluginHostTransport) async throws -> [String] {
        let runtime = HarborPluginRuntime(id: id, name: entry.name, source: source,
            format: entry.format == .providerScript ? .providerScript : .harbor, configuration: .object(settings),
            scope: scope, currentScope: currentScope, transport: transport, sourceID: entry.id)
        defer { runtime.dispose() }
        let metadata = try await runtime.metadata()
        return metadata["methods"].array.compactMap(\.string)
    }
}

/// Owns the asynchronous fetch/probe/commit sequence for one explicit local catalog.
/// Scope activation protects its UI and workers; the namespace selects its on-device data.
@MainActor @Observable final class HarborStreamPluginManager {
    let scope: PluginExecutionScope
    private let currentScope: @MainActor () -> PluginExecutionScope
    private let store: HarborPluginCatalogStore
    private let client: HarborPluginRepositoryClient
    private let secrets: any HarborPluginSecrets
    private let probe: any HarborStreamPluginProbing
    private let namespace: String
    private var operations: [String: @Sendable () -> Void] = [:]
    private var disposed = false
    private(set) var document: HarborPluginCatalogDocument
    private(set) var ready = false
    private(set) var secretCleanupPending = false
    var busy: Set<String> { Set(operations.keys) }
    var invalidateRuntime: @MainActor (String) -> Void = { _ in }

    init(namespace: String, scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
        store: HarborPluginCatalogStore, client: HarborPluginRepositoryClient = .init(),
        secrets: (any HarborPluginSecrets)? = nil, probe: (any HarborStreamPluginProbing)? = nil) {
        self.namespace = namespace; self.scope = scope; self.currentScope = currentScope
        self.store = store; self.client = client; self.secrets = secrets ?? HarborPluginSecretVault(namespace: namespace)
        self.probe = probe ?? HarborNativeStreamPluginProbe(); document = .init(namespace: namespace)
    }

    func load() async throws {
        try validate(); guard operations.isEmpty else { throw HarborPluginRepositoryError("plugin-busy") }; ready = false
        try await store.load(); try await publish(); ready = true
    }

    func dispose() {
        guard !disposed else { return }; disposed = true
        operations.values.forEach { $0() }; operations = [:]
        document.plugins.forEach { invalidateRuntime($0.id) }
        document = .init(namespace: namespace); ready = false
    }

    func addRepository(_ rawURL: String) async throws {
        try await perform("add-repository") {
            let initial = try await self.snapshot()
            let record = try await self.client.add(rawURL, existingURLs: Set(initial.repositories.map(\.url)))
            try await self.commit { current in
                guard !current.repositories.contains(where: { $0.url == record.url }) else { throw HarborPluginRepositoryError("already-added") }
                try await self.store.saveRepository(record, revision: current.revision)
            }
        }
    }

    func refreshRepository(_ url: String) async throws {
        try await perform("repo:" + url) {
            guard try await self.snapshot().repositories.contains(where: { $0.url == url }) else { throw HarborPluginRepositoryError("not-a-repo") }
            let record: HarborStreamRepositoryRecord
            do {
                let manifest = try await self.client.fetchManifest(url)
                record = .init(url: url, manifest: manifest, checkedAt: Date().timeIntervalSince1970 * 1000)
            } catch is CancellationError { throw CancellationError() }
            catch {
                let code = (error as? HarborPluginRepositoryError)?.code ?? "no-answer"
                try await self.commit { current in try await self.store.recordRepositoryFailure(url, code: code, time: Date().timeIntervalSince1970 * 1000, revision: current.revision) }
                return
            }
            try await self.commit { current in
                guard current.repositories.contains(where: { $0.url == url }) else { throw HarborPluginRepositoryError("not-a-repo") }
                try await self.store.saveRepository(record, revision: current.revision)
            }
        }
    }

    func install(repository url: String, entryID: String) async throws {
        let id = HarborPluginManifest.pluginID(repository: url, entry: entryID)
        try await perform("plugin:" + id) {
            let initial = try await self.snapshot()
            guard let repo = initial.repositories.first(where: { $0.url == url }),
                  let entry = repo.manifest.entries.first(where: { $0.id == entryID }) else { throw HarborPluginRepositoryError("not-a-repo") }
            let prior = initial.plugins.first { $0.id == id }
            let source = try await self.client.fetchSource(entry)
            try self.validate()
            let hash = SHA256.hash(data: Data(source.code.utf8)).map { String(format: "%02x", $0) }.joined()
            if let expected = entry.sha256, expected != hash { throw HarborPluginRepositoryError("checksum") }
            let settings = try await self.configuration(prior)
            let methods: [String]
            do {
                methods = try await self.probe.methods(id: id, entry: entry, source: source.code, settings: settings,
                    scope: self.scope, currentScope: self.currentScope,
                    transport: HarborNativePluginTransport(policy: .stream(installing: true, blockedHosts: self.client.blockedHosts), network: self.client.network))
            } catch is CancellationError { throw CancellationError() }
            catch let error as HarborPluginRuntimeError where error.detail.contains("not-stream-plugin") || error.code == "not-stream-plugin" {
                throw HarborPluginRepositoryError("not-stream-plugin")
            }
            catch { throw HarborPluginRepositoryError("start-failed") }
            guard methods.contains("streams") else { throw HarborPluginRepositoryError("not-stream-plugin") }
            var candidate = entry
            candidate.icon = try await self.client.fetchIcon(entry.icon) ?? entry.icon
            try self.validate()
            try await self.commit { current in
                guard current.repositories.first(where: { $0.url == url })?.manifest.entries.first(where: { $0.id == entryID }) == entry,
                      current.plugins.first(where: { $0.id == id }) == prior else { throw HarborPluginRepositoryError("plugin-candidate-changed") }
                try await self.store.install(repository: url, entry: candidate, code: source.code, etag: source.etag, methods: methods,
                    time: Date().timeIntervalSince1970 * 1000, revision: current.revision)
            }
            self.invalidateRuntime(id)
        }
    }

    func revert(_ id: String) async throws {
        try await perform("plugin:" + id) {
            try await self.commit { current in try await self.store.revert(id, time: Date().timeIntervalSince1970 * 1000, revision: current.revision) }
            self.invalidateRuntime(id)
        }
    }
    func setEnabled(_ id: String, _ enabled: Bool) async throws {
        try await perform("plugin:" + id) {
            try await self.commit { current in try await self.store.setEnabled(id, enabled: enabled, revision: current.revision) }
            self.invalidateRuntime(id)
        }
    }

    func uninstall(_ id: String) async throws {
        try await perform("plugin:" + id) {
            let prior = try await self.snapshot().plugins.first { $0.id == id }
            try await self.commit { current in
                guard current.plugins.first(where: { $0.id == id }) == prior else { throw HarborPluginRepositoryError("plugin-candidate-changed") }
                try await self.store.removePlugin(id, revision: current.revision)
            }
            self.invalidateRuntime(id)
            if let revision = prior?.secretRevision { await self.cleanSecret(id, revision) }
        }
    }

    func removeRepository(_ url: String) async throws {
        try await perform("repo:" + url) {
            let plugins = try await self.snapshot().plugins.filter { $0.repoURL == url }
            try await self.commit { current in
                guard current.plugins.filter({ $0.repoURL == url }) == plugins else { throw HarborPluginRepositoryError("plugin-candidate-changed") }
                try await self.store.removeRepository(url, revision: current.revision)
            }
            for plugin in plugins {
                self.invalidateRuntime(plugin.id)
                if let revision = plugin.secretRevision { await self.cleanSecret(plugin.id, revision) }
            }
        }
    }

    func saveSettings(_ id: String, values: [String: JSONValue], passwordKeys: Set<String>) async throws {
        try await perform("plugin:" + id) {
            guard let prior = try await self.snapshot().plugins.first(where: { $0.id == id }) else { throw HarborPluginRepositoryError("plugin-not-installed") }
            guard values.values.allSatisfy({ if case .string = $0 { return true }; if case .bool = $0 { return true }; return false }) else { throw HarborPluginRepositoryError("plugin-settings") }
            var secretValues: [String: String] = [:]
            if let revision = prior.secretRevision { secretValues = try await self.secrets.read(plugin: id, revision: revision) }
            else if !prior.secretKeys.isEmpty { throw HarborPluginRepositoryError("plugin-secrets-missing") }
            var plain: [String: JSONValue] = [:]
            for (key, value) in values {
                if passwordKeys.contains(key) {
                    if let text = value.string, !text.isEmpty { secretValues[key] = text } else { secretValues.removeValue(forKey: key) }
                } else { plain[key] = value; secretValues.removeValue(forKey: key) }
            }
            let keys = secretValues.keys.sorted()
            let revision: String?
            if keys.isEmpty { revision = nil }
            else { revision = try await self.secrets.stage(plugin: id, values: secretValues) }
            var saved = false
            do {
                try await self.commit { current in
                    guard current.plugins.first(where: { $0.id == id }) == prior else { throw HarborPluginRepositoryError("plugin-candidate-changed") }
                    try await self.store.saveSettings(id, values: plain, secretKeys: keys, secretRevision: revision, revision: current.revision)
                    saved = true
                }
            } catch {
                if !saved, let revision { await self.cleanSecret(id, revision) }
                throw error
            }
            self.invalidateRuntime(id)
            if let old = prior.secretRevision { await self.cleanSecret(id, old) }
        }
    }

    func configuration(_ id: String) async throws -> [String: JSONValue] {
        guard let plugin = try await snapshot().plugins.first(where: { $0.id == id }) else { throw HarborPluginRepositoryError("plugin-not-installed") }
        return try await configuration(plugin)
    }

    func settingsFields(_ id: String) async throws -> [HarborPluginSettingsField] {
        try await perform("settings:" + id) {
            guard let plugin = try await self.snapshot().plugins.first(where: { $0.id == id }) else { throw HarborPluginRepositoryError("plugin-not-installed") }
            let settings = try await self.configuration(plugin)
            let transport = HarborPluginSettingsTransport(wrapped: HarborNativePluginTransport(
                policy: .reading(baseURL: nil, blockedHosts: self.client.blockedHosts), network: self.client.network))
            let runtime = HarborPluginRuntime(id: id, name: plugin.entry.name, source: plugin.code,
                format: plugin.entry.format == .providerScript ? .providerScript : .harbor, configuration: .object(settings),
                scope: self.scope, currentScope: self.currentScope, transport: transport, sourceID: plugin.entry.id)
            defer { runtime.dispose() }
            let metadata = try await runtime.metadata()
            guard metadata["methods"].array.compactMap(\.string).contains("settings") else { return [] }
            let raw = try await runtime.call("settings", timeout: 10)
            let fields = try await HarborPluginSettings.fields(raw)
            try self.validate()
            guard try await self.snapshot().plugins.first(where: { $0.id == id }) == plugin else { throw HarborPluginRepositoryError("plugin-candidate-changed") }
            return fields
        }
    }

    private func configuration(_ plugin: HarborInstalledStreamPlugin?) async throws -> [String: JSONValue] {
        try validate(); guard let plugin else { return [:] }
        var values = plugin.settingsValues
        if !plugin.secretKeys.isEmpty {
            guard let revision = plugin.secretRevision else { throw HarborPluginRepositoryError("plugin-secrets-missing") }
            let secret = try await secrets.read(plugin: plugin.id, revision: revision)
            try validate()
            for key in plugin.secretKeys {
                guard let value = secret[key] else { throw HarborPluginRepositoryError("plugin-secrets-missing") }
                values[key] = .string(value)
            }
            guard try await snapshot().plugins.first(where: { $0.id == plugin.id }) == plugin else { throw HarborPluginRepositoryError("plugin-candidate-changed") }
        }
        return values
    }

    private func cleanSecret(_ id: String, _ revision: String) async {
        do { try await secrets.remove(plugin: id, revision: revision) }
        catch { secretCleanupPending = true }
    }
    private func validate() throws {
        guard !disposed, !namespace.isEmpty else { throw HarborPluginRepositoryError("plugin-scope") }
        guard currentScope() == scope else { dispose(); throw HarborPluginRepositoryError("plugin-scope") }
        try Task.checkCancellation()
    }
    private func snapshot() async throws -> HarborPluginCatalogDocument {
        try validate(); let value = try await store.snapshot(); try validate()
        guard value.namespace == namespace else { throw HarborPluginRepositoryError("plugin-store-namespace") }
        return value
    }
    private func publish() async throws { document = try await snapshot() }
    private func commit(_ change: @MainActor (HarborPluginCatalogDocument) async throws -> Void) async throws {
        for attempt in 0..<4 {
            let value = try await snapshot()
            do { try await change(value); try await publish(); return }
            catch let error as HarborPluginRepositoryError where error.code == "plugin-store-changed" && attempt < 3 { continue }
        }
    }
    private func perform<Value: Sendable>(_ key: String, operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        try validate(); guard ready else { throw HarborPluginRepositoryError("plugin-store-unavailable") }
        guard operations[key] == nil else { throw HarborPluginRepositoryError("plugin-busy") }
        let task = Task { let value = try await operation(); try self.validate(); return value }
        operations[key] = { task.cancel() }; defer { operations.removeValue(forKey: key) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
