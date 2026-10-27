import Foundation
import Observation

protocol SimklLibraryPersistence: Sendable {
    func read(owner: String, fingerprint: String) async throws -> SimklLibrarySnapshot?
    func write(_ value: SimklLibrarySnapshot, owner: String, fingerprint: String) async throws
    func remove(owner: String) async throws
}
actor SimklLibraryDisk: SimklLibraryPersistence {
    static let shared = SimklLibraryDisk()
    private struct Document: Codable {
        var version = 1
        let fingerprint: String
        let snapshot: SimklLibrarySnapshot
    }
    private let root: URL
    init(root: URL? = nil) {
        self.root = root ?? URL.applicationSupportDirectory.appendingPathComponent("HarborSimklLibrary", isDirectory: true)
    }
    private func url(_ owner: String) -> URL { root.appendingPathComponent(EBookShelf.hash(owner) + ".json") }
    func read(owner: String, fingerprint: String) throws -> SimklLibrarySnapshot? {
        let file = url(owner)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 16 * 1_024 * 1_024 else { throw HarborError(code: "simkl-cache") }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file))
        guard document.version == 1, document.snapshot.items.count <= 20_000 else { throw HarborError(code: "simkl-cache") }
        guard document.fingerprint == fingerprint else { return nil }
        return document.snapshot
    }
    func write(_ value: SimklLibrarySnapshot, owner: String, fingerprint: String) throws {
        guard value.items.count <= 20_000 else { throw HarborError(code: "simkl-cache") }
        let data = try JSONEncoder().encode(Document(fingerprint: fingerprint, snapshot: value))
        guard data.count <= 16 * 1_024 * 1_024 else { throw HarborError(code: "simkl-cache") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: url(owner), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var directory = root, values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }
    func remove(owner: String) throws {
        let file = url(owner); if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

/// One observable projection per personal profile. The fingerprint also prevents
/// a different Simkl account on that profile from inheriting the previous list.
@MainActor @Observable final class SimklLibraryStore {
    private static var stores: [String: SimklLibraryStore] = [:]
    static func forOwner(_ owner: String) -> SimklLibraryStore {
        if let saved = stores[owner] { return saved }
        let store = SimklLibraryStore(owner: owner); stores[owner] = store; return store
    }
    let owner: String
    private let disk: any SimklLibraryPersistence
    private(set) var snapshot = SimklLibrarySnapshot()
    private(set) var fingerprint: String?
    private(set) var restored = false
    private(set) var revision = 0
    private(set) var refreshedAt: Date?
    var updating = false
    init(owner: String, disk: any SimklLibraryPersistence = SimklLibraryDisk.shared) { self.owner = owner; self.disk = disk }
    func bind(_ token: String?) {
        let next = token.map { EBookShelf.hash($0) }
        guard next != fingerprint else { return }
        fingerprint = next; snapshot = .init(); restored = false; refreshedAt = nil; revision &+= 1
    }
    func restore() async throws {
        guard !restored, let fingerprint else { return }
        let revision = revision
        let saved = try await disk.read(owner: owner, fingerprint: fingerprint)
        guard self.fingerprint == fingerprint, self.revision == revision else { throw CancellationError() }
        if let saved { snapshot = saved; self.revision &+= 1 }; restored = true
    }
    func commit(_ value: SimklLibrarySnapshot, fingerprint: String, expectedRevision: Int) async throws {
        guard self.fingerprint == fingerprint, revision == expectedRevision else { throw CancellationError() }
        snapshot = value; revision &+= 1; refreshedAt = Date(); restored = true
        try await disk.write(value, owner: owner, fingerprint: fingerprint)
    }
    func clear() async throws {
        guard fingerprint == nil else { return }
        snapshot = .init(); restored = false; refreshedAt = nil; revision &+= 1
        try await disk.remove(owner: owner)
    }
    func invalidate() { refreshedAt = nil; revision &+= 1 }
}
