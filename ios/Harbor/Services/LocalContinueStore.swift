import Foundation

/// Two explicit namespaces mirror Desktop's private and shared local-CW stores.
/// Keeping the cloud-only method separate prevents imports assigning ownership.
actor LocalContinueStore {
    typealias Lease = @Sendable () async -> Bool
    static let shared = LocalContinueStore()
    private let root: URL?
    private var documents: [String: LocalContinueDocument] = [:]
    private var tail: Task<Void, Never>?
    init(root: URL? = nil) { self.root = root }
    private func key(_ owner: String, personal: Bool) throws -> String {
        guard !owner.isEmpty, owner.utf8.count <= 1_024, owner.rangeOfCharacter(from: .controlCharacters) == nil else { throw HarborError(code: "local-continue-owner") }
        return (personal ? "private:" : "shared:") + owner
    }
    private func file(_ key: String) throws -> URL {
        let directory: URL
        if let root { directory = root }
        else {
            directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent("Harbor/local-continue", isDirectory: true)
        }
        return directory.appendingPathComponent(EBookShelf.hash(key) + ".json")
    }
    private func read(_ key: String) throws -> LocalContinueDocument {
        if let saved = documents[key] { return saved }
        let url = try file(key), document: LocalContinueDocument
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 4 * 1_024 * 1_024 else { throw HarborError(code: "local-continue-read") }
            let data = try Data(contentsOf: url); guard data.count <= 4 * 1_024 * 1_024 else { throw HarborError(code: "local-continue-read") }
            document = try JSONDecoder().decode(LocalContinueDocument.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { document = .init() }
        guard document.valid else { throw HarborError(code: "local-continue-read") }
        if documents.count >= 80 { documents.removeAll() }
        documents[key] = document; return document
    }
    private func write(_ value: LocalContinueDocument, key: String) throws {
        guard value.valid else { throw HarborError(code: "local-continue-entry") }
        let data = try JSONEncoder().encode(value); guard data.count <= 4 * 1_024 * 1_024 else { throw HarborError(code: "local-continue-write") }
        let url = try file(key), directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var parent = directory, values = URLResourceValues(); values.isExcludedFromBackup = true; try parent.setResourceValues(values)
        documents[key] = value
    }
    func snapshot(personalOwner: String, sharedOwner: String) throws -> LocalContinueSnapshot {
        try .init(personal: read(key(personalOwner, personal: true)), shared: read(key(sharedOwner, personal: false)))
    }
    private func enqueue<Result: Sendable>(_ work: @escaping @Sendable () async throws -> Result) async throws -> Result {
        let previous = tail
        let task = Task { await previous?.value; return try await work() }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
    func recordPlayback(_ entry: LocalContinueEntry, personalOwner: String, sharedOwner: String, includeShared: Bool = true, current: @escaping Lease) async throws -> LocalContinueSnapshot {
        try await enqueue { try await self.record(entry, personalOwner: personalOwner, sharedOwner: sharedOwner, includeShared: includeShared, current: current) }
    }
    private func record(_ entry: LocalContinueEntry, personalOwner: String, sharedOwner: String, includeShared: Bool, current: @escaping Lease) async throws -> LocalContinueSnapshot {
        guard entry.valid else { throw HarborError(code: "local-continue-entry") }
        let keys = try [key(personalOwner, personal: true)] + (includeShared ? [key(sharedOwner, personal: false)] : [])
        for key in keys {
            guard await current() else { throw CancellationError() }
            var document = try read(key); try document.save(entry); try write(document, key: key)
        }
        return try snapshot(personalOwner: personalOwner, sharedOwner: sharedOwner)
    }
    func absorbShared(_ entries: [LocalContinueEntry], sharedOwner: String, current: @escaping Lease) async throws {
        try await enqueue { try await self.absorb(entries, sharedOwner: sharedOwner, current: current) }
    }
    private func absorb(_ entries: [LocalContinueEntry], sharedOwner: String, current: @escaping Lease) async throws {
        let key = try key(sharedOwner, personal: false)
        guard await current() else { throw CancellationError() }
        var document = try read(key)
        for entry in entries { try document.save(entry) }
        try write(document, key: key)
    }
    func absorbCloudAnime(_ records: [LibraryRecord], sharedOwner: String, now: Double, current: @escaping Lease) async throws {
        try await enqueue { try await self.absorbAnime(records, sharedOwner: sharedOwner, now: now, current: current) }
    }
    private func absorbAnime(_ records: [LibraryRecord], sharedOwner: String, now: Double, current: @escaping Lease) async throws {
        let key = try key(sharedOwner, personal: false)
        guard await current() else { throw CancellationError() }
        var document = try read(key), changed = false
        for record in records {
            if let value = CloudAnimeContinueImport.entry(record, existing: document.entries[record.id], now: now) { try document.save(value); changed = true }
        }
        if changed { try write(document, key: key) }
    }
    func clear(_ id: String, personalOwner: String, sharedOwner: String, current: @escaping Lease) async throws -> LocalContinueSnapshot {
        try await enqueue { try await self.remove(id, personalOwner: personalOwner, sharedOwner: sharedOwner, current: current) }
    }
    private func remove(_ id: String, personalOwner: String, sharedOwner: String, current: @escaping Lease) async throws -> LocalContinueSnapshot {
        for key in try [key(personalOwner, personal: true), key(sharedOwner, personal: false)] {
            guard await current() else { throw CancellationError() }
            var document = try read(key)
            if document.remove(id) { try write(document, key: key) }
        }
        return try snapshot(personalOwner: personalOwner, sharedOwner: sharedOwner)
    }
}
