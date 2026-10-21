import CryptoKit
import Foundation

struct HarborStreamRepositoryRecord: Codable, Equatable, Sendable {
    var url: String
    var manifest: HarborParsedStreamRepository
    var checkedAt: Double
    var error: String?
}

struct HarborPluginPrevious: Codable, Equatable, Sendable {
    var version: String
    var code: String
    var hash: String
    var etag: String?
    var sha256: String?
}

struct HarborInstalledStreamPlugin: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var repoURL: String
    var repoName: String
    var entry: HarborStreamPluginEntry
    var code: String
    var hash: String
    var etag: String?
    var enabled = true
    var repoDisabled = false
    var verified = false
    var installedAt: Double
    var updatedAt: Double
    var previous: HarborPluginPrevious?
    var learnedHosts: [String] = []
    var limitHosts = false
    // Password values live in the owner-bound Keychain, never this document.
    var settingsValues: [String: JSONValue] = [:]
    var secretKeys: [String] = []
    var secretRevision: String? = nil
    var autoPaused = false
    var failures = 0
    var listed = true
    var filesChanged = false
    var updateVersion: String?

    var runnable: Bool { enabled && !repoDisabled && !autoPaused && listed && entry.format != .androidExtension }
}

struct HarborPluginCatalogDocument: Codable, Equatable, Sendable {
    var schema = 1
    var namespace: String
    var revision: UInt64 = 0
    var repositories: [HarborStreamRepositoryRecord] = []
    var plugins: [HarborInstalledStreamPlugin] = []
}

/// Local installation data, equivalent to Desktop's local IndexedDB, not cloud preferences.
/// The caller chooses the namespace deliberately; profile/household binding is not inferred.
actor HarborPluginCatalogStore {
    private let namespace: String
    private let file: URL
    private let write: @Sendable (Data, URL) throws -> Void
    private var document: HarborPluginCatalogDocument
    private var ready = false
    private let limit = 64 * 1024 * 1024

    init(namespace: String, file: URL? = nil, write: (@Sendable (Data, URL) throws -> Void)? = nil) throws {
        guard !namespace.isEmpty else { throw HarborPluginRepositoryError("plugin-store-namespace") }
        self.namespace = namespace; self.write = write ?? { data, target in try HarborPluginCatalogStore.writeFile(data, target) }
        document = .init(namespace: namespace)
        if let file { self.file = file }
        else {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            self.file = directory.appendingPathComponent("Harbor/Plugins", isDirectory: true).appendingPathComponent(Self.digest(namespace) + ".json")
        }
    }

    func load() throws {
        ready = false
        do {
            var next = HarborPluginCatalogDocument(namespace: namespace)
            do {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= limit else { throw HarborPluginRepositoryError("plugin-store-too-large") }
                let data = try Data(contentsOf: file)
                guard data.count <= limit else { throw HarborPluginRepositoryError("plugin-store-too-large") }
                next = try JSONDecoder().decode(HarborPluginCatalogDocument.self, from: data)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
            try validate(next); document = next; ready = true
        } catch let error as HarborPluginRepositoryError { throw error }
        catch { throw HarborPluginRepositoryError("plugin-store-read") }
    }

    func snapshot() throws -> HarborPluginCatalogDocument {
        guard ready else { throw HarborPluginRepositoryError("plugin-store-unavailable") }
        return document
    }

    func saveRepository(_ record: HarborStreamRepositoryRecord, revision: UInt64) throws {
        var next = try current(revision)
        next.repositories.removeAll { $0.url == record.url }; next.repositories.append(record)
        for index in next.plugins.indices where next.plugins[index].repoURL == record.url {
            let entry = record.manifest.entries.first { $0.id == next.plugins[index].entry.id }
            next.plugins[index].repoName = record.manifest.name
            next.plugins[index].listed = entry != nil
            if let entry { next.plugins[index].repoDisabled = !entry.enabled }
            next.plugins[index].updateVersion = entry.flatMap { $0.version == next.plugins[index].entry.version ? nil : $0.version }
        }
        try commit(next)
    }

    /// A refresh failure retains the last usable entries and installed code.
    func recordRepositoryFailure(_ url: String, code: String, time: Double, revision: UInt64) throws {
        var next = try current(revision)
        guard let index = next.repositories.firstIndex(where: { $0.url == url }) else { throw HarborPluginRepositoryError("not-a-repo") }
        next.repositories[index].error = code; next.repositories[index].checkedAt = time
        try commit(next)
    }

    /// Called only after fetching and successfully probing the candidate in its scoped worker.
    func install(repository url: String, entry: HarborStreamPluginEntry, code: String, etag: String?, methods: [String], time: Double, revision: UInt64) throws {
        var next = try current(revision)
        guard entry.format != .androidExtension else { throw HarborPluginRepositoryError("android-extensions") }
        guard methods.contains("streams") else { throw HarborPluginRepositoryError("not-stream-plugin") }
        guard code.utf16.count <= 2 * 1024 * 1024 else { throw HarborPluginRepositoryError("too-large") }
        let hash = Self.digest(code)
        if let expected = entry.sha256, expected != hash { throw HarborPluginRepositoryError("checksum") }
        guard let repository = next.repositories.first(where: { $0.url == url }) else { throw HarborPluginRepositoryError("not-a-repo") }
        let id = HarborPluginManifest.pluginID(repository: url, entry: entry.id)
        let prior = next.plugins.first { $0.id == id }
        var installed = HarborInstalledStreamPlugin(id: id, repoURL: url, repoName: repository.manifest.name, entry: entry, code: code, hash: hash, etag: etag,
            installedAt: prior?.installedAt ?? time, updatedAt: time)
        installed.enabled = prior?.enabled ?? true; installed.repoDisabled = !entry.enabled; installed.verified = entry.sha256 != nil
        installed.previous = prior.map { .init(version: $0.entry.version, code: $0.code, hash: $0.hash, etag: $0.etag, sha256: $0.entry.sha256) }
        installed.learnedHosts = prior?.learnedHosts ?? []; installed.limitHosts = prior?.limitHosts ?? false
        installed.settingsValues = prior?.settingsValues ?? [:]; installed.secretKeys = prior?.secretKeys ?? []
        installed.secretRevision = prior?.secretRevision
        if installed.entry.icon == nil { installed.entry.icon = prior?.entry.icon }
        next.plugins.removeAll { $0.id == id }; next.plugins.append(installed)
        try commit(next)
    }

    func revert(_ id: String, time: Double, revision: UInt64) throws {
        var next = try current(revision)
        guard let index = next.plugins.firstIndex(where: { $0.id == id }), let previous = next.plugins[index].previous else { return }
        next.plugins[index].updateVersion = next.plugins[index].entry.version
        next.plugins[index].entry.version = previous.version; next.plugins[index].code = previous.code
        next.plugins[index].hash = previous.hash; next.plugins[index].etag = previous.etag
        next.plugins[index].entry.sha256 = previous.sha256; next.plugins[index].verified = previous.sha256 == previous.hash
        next.plugins[index].previous = nil; next.plugins[index].updatedAt = time
        next.plugins[index].autoPaused = false; next.plugins[index].failures = 0
        try commit(next)
    }

    func setEnabled(_ id: String, enabled: Bool, revision: UInt64) throws {
        var next = try current(revision)
        guard let index = next.plugins.firstIndex(where: { $0.id == id }) else { return }
        next.plugins[index].enabled = enabled; next.plugins[index].autoPaused = false; next.plugins[index].failures = 0
        try commit(next)
    }

    func removePlugin(_ id: String, revision: UInt64) throws {
        var next = try current(revision); next.plugins.removeAll { $0.id == id }; try commit(next)
    }

    func recordRuntimeOutcome(_ id: String, expected: HarborInstalledStreamPlugin, succeeded: Bool, revision: UInt64) throws {
        var next = try current(revision)
        guard let index = next.plugins.firstIndex(where: { $0.id == id }) else { return }
        let value = next.plugins[index]
        guard value.hash == expected.hash, value.secretRevision == expected.secretRevision, value.settingsValues == expected.settingsValues,
              value.entry == expected.entry, value.enabled, !value.repoDisabled, value.listed else { return }
        if succeeded {
            guard value.failures != 0 || value.autoPaused else { return }
            next.plugins[index].failures = 0; next.plugins[index].autoPaused = false
        } else {
            next.plugins[index].failures = value.failures == Int.max ? Int.max : max(0, value.failures) + 1
            next.plugins[index].autoPaused = next.plugins[index].failures >= 3
        }
        try commit(next)
    }

    func saveSettings(_ id: String, values: [String: JSONValue], secretKeys: [String], secretRevision: String?, revision: UInt64) throws {
        var next = try current(revision)
        guard let index = next.plugins.firstIndex(where: { $0.id == id }) else { throw HarborPluginRepositoryError("plugin-not-installed") }
        guard Set(secretKeys).count == secretKeys.count, secretKeys.allSatisfy({ values[$0] == nil }),
              secretKeys.isEmpty || !(secretRevision ?? "").isEmpty else { throw HarborPluginRepositoryError("plugin-settings") }
        next.plugins[index].settingsValues = values; next.plugins[index].secretKeys = secretKeys
        next.plugins[index].secretRevision = secretRevision
        try commit(next)
    }

    func removeRepository(_ url: String, revision: UInt64) throws {
        var next = try current(revision)
        next.repositories.removeAll { $0.url == url }; next.plugins.removeAll { $0.repoURL == url }
        try commit(next)
    }

    private func current(_ revision: UInt64) throws -> HarborPluginCatalogDocument {
        let value = try snapshot()
        guard value.revision == revision else { throw HarborPluginRepositoryError("plugin-store-changed") }
        return value
    }

    private func commit(_ value: HarborPluginCatalogDocument) throws {
        var next = value
        guard next.revision < UInt64.max else { throw HarborPluginRepositoryError("plugin-store-revision") }
        next.revision += 1; try validate(next)
        do {
            let data = try JSONEncoder().encode(next)
            guard data.count <= limit else { throw HarborPluginRepositoryError("plugin-store-too-large") }
            try write(data, file); document = next
        } catch let error as HarborPluginRepositoryError { throw error }
        catch { throw HarborPluginRepositoryError("plugin-store-write") }
    }

    private func validate(_ value: HarborPluginCatalogDocument) throws {
        guard value.schema == 1, value.namespace == namespace,
              Set(value.repositories.map(\.url)).count == value.repositories.count,
              Set(value.plugins.map(\.id)).count == value.plugins.count,
              value.repositories.allSatisfy({ $0.checkedAt.isFinite }) else { throw HarborPluginRepositoryError("plugin-store-invalid") }
        let repos = Set(value.repositories.map(\.url))
        for plugin in value.plugins {
            guard repos.contains(plugin.repoURL), plugin.id == HarborPluginManifest.pluginID(repository: plugin.repoURL, entry: plugin.entry.id),
                  plugin.entry.format != .androidExtension, Self.digest(plugin.code) == plugin.hash,
                  plugin.code.utf16.count <= 2 * 1024 * 1024, plugin.installedAt.isFinite, plugin.updatedAt.isFinite,
                  plugin.settingsValues.values.allSatisfy({ value in if case .string = value { return true }; if case .bool = value { return true }; return false }) else { throw HarborPluginRepositoryError("plugin-store-invalid") }
            if let previous = plugin.previous {
                guard previous.code.utf16.count <= 2 * 1024 * 1024, Self.digest(previous.code) == previous.hash else { throw HarborPluginRepositoryError("plugin-store-invalid") }
            }
        }
    }

    private static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

    private static func writeFile(_ data: Data, _ target: URL) throws {
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var directory = target.deletingLastPathComponent(); var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
        try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
