import CryptoKit
import Foundation

enum HarborReadingPluginKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case manga, ebook
    var id: String { rawValue }
    var title: String { self == .manga ? "Manga" : "Books" }
}
struct HarborReadingPluginEntry: Codable, Equatable, Sendable, Identifiable {
    var raw: JSONValue
    var id: String { raw["id"].string ?? "" }
    var name: String { raw["name"].string ?? "" }
    var version: String { raw["version"].string ?? "0" }
    var language: String { raw["lang"].string ?? "en" }
    var adult: Bool { raw["nsfw"] == .bool(true) }
    var icon: String? { raw["icon"].string }
    var location: String { raw["entry"].string ?? "" }
    var mangayomi: Bool { raw["format"].string == "mangayomi" }
    var baseURL: String? { raw["baseUrl"].string }
}
struct HarborReadingPluginRepository: Codable, Equatable, Sendable, Identifiable {
    var kind: HarborReadingPluginKind
    var url: String
    var name: String
    var entries: [HarborReadingPluginEntry]
    var foreign: String?
    var checkedAt: Date
    var id: String { kind.rawValue + "|" + url }
}
struct HarborInstalledReadingPlugin: Codable, Equatable, Sendable, Identifiable {
    var kind: HarborReadingPluginKind
    var entry: HarborReadingPluginEntry
    var repository: String
    var repositoryName: String
    var source: String
    var hash: String
    var enabled = true
    var hasTags = false
    var configuration: JSONValue = .object([:])
    var id: String { kind.rawValue + "|" + entry.id }
}
struct HarborReadingPluginDocument: Codable, Equatable, Sendable {
    var schema = 1
    var revision: UInt64 = 0
    var repositories: [HarborReadingPluginRepository] = []
    var plugins: [HarborInstalledReadingPlugin] = []
}

/// Separate local databases match Desktop's Manga and Books stores; no account credentials are copied.
actor HarborReadingPluginStore {
    private let file: URL
    private var document = HarborReadingPluginDocument()
    private var ready = false
    init(file: URL? = nil) throws {
        if let file { self.file = file.resolvingSymlinksInPath().standardizedFileURL }
        else {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            self.file = support.appendingPathComponent("Harbor/Plugins/reading-v1.json").resolvingSymlinksInPath().standardizedFileURL
        }
    }
    func load() throws -> HarborReadingPluginDocument {
        ready = false
        let next: HarborReadingPluginDocument
        if FileManager.default.fileExists(atPath: file.path) {
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 64 * 1024 * 1024 else { throw HarborPluginRepositoryError("plugin-store-too-large") }
            next = try JSONDecoder().decode(HarborReadingPluginDocument.self, from: Data(contentsOf: file))
        } else { next = .init() }
        try validate(next); document = next; ready = true; return next
    }
    func commit(_ next: HarborReadingPluginDocument, expected: UInt64) throws -> HarborReadingPluginDocument {
        try Task.checkCancellation()
        guard ready, document.revision == expected, expected < UInt64.max else { throw HarborPluginRepositoryError("plugin-store-conflict") }
        var value = next; value.revision = expected + 1; try validate(value)
        let data = try JSONEncoder().encode(value)
        guard data.count <= 64 * 1024 * 1024 else { throw HarborPluginRepositoryError("plugin-store-too-large") }
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        guard folder.standardizedFileURL == folder.resolvingSymlinksInPath().standardizedFileURL,
              file.standardizedFileURL == file.resolvingSymlinksInPath().standardizedFileURL else { throw HarborPluginRepositoryError("plugin-store-path") }
        try Task.checkCancellation(); try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        document = value; return value
    }
    private func validate(_ value: HarborReadingPluginDocument) throws {
        guard value.schema == 1, value.repositories.count <= 500, value.plugins.count <= 2000,
              Set(value.repositories.map(\.id)).count == value.repositories.count,
              Set(value.plugins.map(\.id)).count == value.plugins.count else { throw HarborPluginRepositoryError("plugin-store-format") }
        for plugin in value.plugins {
            guard !plugin.entry.id.isEmpty, !plugin.entry.name.isEmpty, plugin.source.utf16.count <= 2 * 1024 * 1024,
                  Self.digest(plugin.source) == plugin.hash,
                  value.repositories.contains(where: { $0.kind == plugin.kind && $0.url == plugin.repository }) else { throw HarborPluginRepositoryError("plugin-store-format") }
        }
    }
    nonisolated static func digest(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
