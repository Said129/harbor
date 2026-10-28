import Foundation
import Observation

protocol TraktLibraryPersistence: Sendable {
    func read(owner: String, fingerprint: String) async throws -> TraktLibrarySnapshot?
    func write(_ value: TraktLibrarySnapshot, owner: String, fingerprint: String) async throws
}
actor TraktLibraryDisk: TraktLibraryPersistence {
    static let shared = TraktLibraryDisk()
    private struct Document: Codable { let version: Int; let fingerprint: String; let snapshot: TraktLibrarySnapshot }
    private let root: URL
    init(root: URL? = nil) { self.root = root ?? URL.applicationSupportDirectory.appendingPathComponent("HarborTraktLibrary", isDirectory: true) }
    private func url(_ owner: String) -> URL { root.appendingPathComponent(EBookShelf.hash(owner) + ".json") }
    func read(owner: String, fingerprint: String) throws -> TraktLibrarySnapshot? {
        let file = url(owner); guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1_024 * 1_024 else { throw HarborError(code: "trakt-cache") }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file))
        guard document.version == 1, document.snapshot.watchlist.count <= 20_000, document.snapshot.history.count <= 20_000 else { throw HarborError(code: "trakt-cache") }
        return document.fingerprint == fingerprint ? document.snapshot : nil
    }
    func write(_ value: TraktLibrarySnapshot, owner: String, fingerprint: String) throws {
        guard value.watchlist.count <= 20_000, value.history.count <= 20_000 else { throw HarborError(code: "trakt-cache") }
        let data = try JSONEncoder().encode(Document(version: 1, fingerprint: fingerprint, snapshot: value))
        guard data.count <= 16 * 1_024 * 1_024 else { throw HarborError(code: "trakt-cache") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: url(owner), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var directory = root, values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
    }
}

@MainActor @Observable final class TraktLibraryStore {
    private static var stores: [String: TraktLibraryStore] = [:]
    static func forOwner(_ owner: String) -> TraktLibraryStore {
        if let value = stores[owner] { return value }; let value = TraktLibraryStore(owner: owner); stores[owner] = value; return value
    }
    let owner: String
    private let disk: any TraktLibraryPersistence
    private(set) var snapshot = TraktLibrarySnapshot()
    private(set) var fingerprint: String?
    private(set) var revision = 0
    private(set) var restored = false
    private(set) var refreshedAt: Date?
    private var writer: UUID?
    var updating: Bool { writer != nil }
    init(owner: String, disk: any TraktLibraryPersistence = TraktLibraryDisk.shared) { self.owner = owner; self.disk = disk }
    func bind(_ trackingID: UUID?) {
        let next = trackingID.map { EBookShelf.hash($0.uuidString) }; guard next != fingerprint else { return }
        fingerprint = next; snapshot = .init(); revision &+= 1; restored = false; refreshedAt = nil; writer = nil
    }
    func restore() async throws {
        guard !restored, let fingerprint else { return }; let revision = revision
        let saved = try await disk.read(owner: owner, fingerprint: fingerprint)
        guard self.fingerprint == fingerprint, self.revision == revision else { throw CancellationError() }
        if let saved { snapshot = saved; self.revision &+= 1 }; restored = true
    }
    func commit(_ value: TraktLibrarySnapshot, fingerprint: String, revision: Int) async throws {
        guard self.fingerprint == fingerprint, self.revision == revision else { throw CancellationError() }
        snapshot = value; self.revision &+= 1; restored = true; refreshedAt = Date()
        try await disk.write(value, owner: owner, fingerprint: fingerprint)
    }
    func invalidate() { refreshedAt = nil; revision &+= 1 }
    func beginUpdate() -> UUID? { guard !updating, fingerprint != nil else { return nil }; let id = UUID(); writer = id; return id }
    func endUpdate(_ id: UUID) { if writer == id { writer = nil } }
}
