import CryptoKit
import Foundation

/// Pending library changes contain no credentials. A signed-in session may
/// flush only its own protected document, including after an app restart.
actor LibraryWriteQueue {
    typealias Lease = @Sendable () async -> Bool
    private struct Document: Codable {
        var version = 1
        var entries: [String: JSONValue] = [:]
        var valid: Bool {
            version == 1 && entries.count <= 2_000 && entries.allSatisfy { id, record in
                !id.isEmpty && id.utf8.count <= 4_096 && record["_id"].string == id
            }
        }
    }
    private let service: any LibraryServing
    private let directory: URL?
    private var documents: [String: Document] = [:]
    private var flushing: Set<String> = []
    private let limit = 8 * 1_024 * 1_024
    init(service: any LibraryServing = LibraryService(), directory: URL? = nil) { self.service = service; self.directory = directory }

    func pending(owner: String) throws -> [JSONValue] { Array(try load(owner).entries.values) }

    /// The immediate attempt matches Desktop. A failed request is accepted only
    /// after the newest intent has been durably saved; disk failures propagate.
    @discardableResult
    func put(_ record: JSONValue, session: AccountSession, current: @escaping Lease = { true }) async throws -> Bool {
        let owner = session.user.id
        _ = try identifier(record)
        _ = try load(owner)
        guard await current() else { throw CancellationError() }
        do {
            if Self.cloudWritable(record) { try await service.save(record, session: session) }
        } catch is CancellationError { throw CancellationError() }
        catch {
            guard await current() else { throw CancellationError() }
            var next = try load(owner)
            let id = try identifier(record)
            if next.entries[id].map({ Self.mtime($0) <= Self.mtime(record) }) ?? true {
                next.entries[id] = record; try commit(next, owner: owner)
            }
            return false
        }
        try drop(record, owner: owner)
        return true
    }

    @discardableResult
    func flush(_ session: AccountSession, current: @escaping Lease = { true }) async throws -> [JSONValue] {
        let owner = session.user.id
        guard !flushing.contains(owner) else { return [] }
        let pending = try load(owner).entries.values.sorted { ($0["_id"].string ?? "") < ($1["_id"].string ?? "") }
        guard !pending.isEmpty else { return [] }
        flushing.insert(owner); defer { flushing.remove(owner) }
        var reconciled: [JSONValue] = []
        for record in pending {
            guard await current(), !Task.isCancelled else { throw CancellationError() }
            let id = try identifier(record)
            // Another in-flight write may already have replaced this snapshot.
            guard try load(owner).entries[id] == record else { continue }
            let remote: JSONValue?
            do { remote = try await service.record(id, session: session) }
            catch is CancellationError { throw CancellationError() }
            catch { continue }
            guard await current() else { throw CancellationError() }
            // Stremio stores modification times at second precision.
            if floor((remote.map(Self.mtime) ?? 0) / 1_000) >= floor(Self.mtime(record) / 1_000) {
                try drop(record, owner: owner)
                if let remote { reconciled.append(remote) }; continue
            }
            guard try load(owner).entries[id] == record else { continue }
            do { if Self.cloudWritable(record) { try await service.save(record, session: session) } }
            catch is CancellationError { throw CancellationError() }
            catch { continue }
            try drop(record, owner: owner)
            reconciled.append(record)
        }
        return reconciled
    }

    static func merging(_ records: [JSONValue], pending: [JSONValue]) -> [JSONValue] {
        var values = records
        for record in pending {
            guard let id = record["_id"].string else { continue }
            if let index = values.firstIndex(where: { $0["_id"].string == id }) {
                if mtime(values[index]) <= mtime(record) { values[index] = record }
            } else { values.append(record) }
        }
        return values
    }
    static func cloudWritable(_ record: JSONValue) -> Bool {
        !CloudAnimeContinueImport.owns(record["_id"].string ?? "") || record["removed"] == .bool(true)
    }
    private static func mtime(_ record: JSONValue) -> Double { LibraryRecord.timestamp(record["_mtime"]) ?? 0 }
    private func identifier(_ record: JSONValue) throws -> String {
        guard let id = record["_id"].string, !id.isEmpty, id.utf8.count <= 4_096 else { throw HarborError(code: "library-queue-record") }; return id
    }
    private func drop(_ record: JSONValue, owner: String) throws {
        var next = try load(owner); let id = try identifier(record)
        guard let held = next.entries[id], Self.mtime(held) <= Self.mtime(record) else { return }
        next.entries.removeValue(forKey: id); try commit(next, owner: owner)
    }
    private func load(_ owner: String) throws -> Document {
        if let saved = documents[owner] { return saved }
        let url = try location(owner); let value: Document
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= limit else { throw HarborError(code: "library-queue-too-large") }
            let data = try Data(contentsOf: url)
            guard data.count <= limit else { throw HarborError(code: "library-queue-too-large") }
            value = try JSONDecoder().decode(Document.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { value = .init() }
        catch { throw HarborError(code: "library-queue-read") }
        guard value.valid else { throw HarborError(code: "library-queue-read") }
        if documents.count >= 8 { documents.removeAll() }
        documents[owner] = value; return value
    }
    private func commit(_ value: Document, owner: String) throws {
        guard value.valid else { throw HarborError(code: "library-queue-record") }
        do {
            let data = try JSONEncoder().encode(value)
            guard data.count <= limit else { throw HarborError(code: "library-queue-too-large") }
            let url = try location(owner)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            documents[owner] = value
        } catch { throw HarborError(code: "library-queue-write") }
    }
    private func location(_ owner: String) throws -> URL {
        guard !owner.isEmpty, owner.utf8.count <= 4_096 else { throw HarborError(code: "library-queue-owner") }
        let base = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Harbor", isDirectory: true)
        let hash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        return base.appendingPathComponent("library-write-queue-\(hash).json")
    }
}
