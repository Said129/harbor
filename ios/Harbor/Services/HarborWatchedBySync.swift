import Foundation
import Observation

struct WatchedBySyncRecord: Codable, Equatable, Sendable {
    var version = 1
    var value: JSONValue = .object([:])
    var shadow: HarborLayoutDocument?
}
@MainActor protocol WatchedByPersistence {
    func readWatchedBy(_ key: String) throws -> WatchedBySyncRecord?
    func writeWatchedBy(_ value: WatchedBySyncRecord, key: String) throws
}
@MainActor private struct KeychainWatchedBy: WatchedByPersistence {
    func readWatchedBy(_ key: String) throws -> WatchedBySyncRecord? { try KeychainStore().read(key, as: WatchedBySyncRecord.self) }
    func writeWatchedBy(_ value: WatchedBySyncRecord, key: String) throws { try KeychainStore().write(value, key: key) }
}

/// One fixed account bucket also holds offline watches and unacknowledged edits.
/// A response can acknowledge the sent snapshot without discarding newer watches.
@MainActor @Observable final class HarborWatchedBySync {
    private static var shared: [String: HarborWatchedBySync] = [:]
    static func forOwner(_ owner: String, account: String?) -> HarborWatchedBySync {
        let bucket = HouseholdProfileScope.hash([owner, account == nil ? "local" : "harbor", account ?? ""])
        if let value = shared[bucket] { return value }
        let value = HarborWatchedBySync(owner: owner, account: account); shared[bucket] = value; return value
    }
    static let documentKey = "account:watchedby"
    let account: String?
    private let key: String
    private let persistence: any WatchedByPersistence
    private var stored = WatchedBySyncRecord()
    private(set) var ready = false
    private(set) var busy = false
    private(set) var error: String?
    @ObservationIgnored var requestSync: (() -> Void)?
    private(set) var value = DesktopWatchedBy(.null)
    var hasPendingChanges: Bool {
        ready && account != nil && !value.entries.isEmpty && value != DesktopWatchedBy(stored.shadow?.value ?? .null)
    }
    init(owner: String, account: String?, persistence: (any WatchedByPersistence)? = nil) {
        self.account = account; self.persistence = persistence ?? KeychainWatchedBy()
        key = "watched-by-" + HouseholdProfileScope.hash([owner, account == nil ? "local" : "harbor", account ?? ""])
        do {
            let loaded = try self.persistence.readWatchedBy(key) ?? WatchedBySyncRecord()
            try Self.validate(loaded); stored = loaded; value = DesktopWatchedBy(loaded.value); ready = true
        } catch { self.error = "Could not load watch attribution. Saved data is kept." }
    }
    private static func validate(_ value: WatchedBySyncRecord) throws {
        guard value.version == 1, case .object = value.value,
              DesktopWatchedBy(value.value).entries.count <= DesktopWatchedBy.maximum,
              try JSONEncoder().encode(value).count <= 384 * 1_024 else { throw HarborError(code: "watched-by-store") }
        if let shadow = value.shadow {
            guard shadow.key == documentKey, shadow.rev >= 0, shadow.rev <= HarborLayoutDocument.maximumRevision else { throw HarborError(code: "watched-by-store") }
        }
    }
    private func save(_ next: WatchedBySyncRecord) throws {
        guard ready else { throw HarborError(code: "watched-by-store") }
        try Self.validate(next)
        if next != stored { try persistence.writeWatchedBy(next, key: key); stored = next; value = DesktopWatchedBy(next.value) }
    }
    func record(mediaID: String, profileID: String, at timestamp: Double = Date().timeIntervalSince1970 * 1_000) throws {
        do {
            let updated = try value.recording(mediaID: mediaID, profileID: profileID, at: timestamp)
            guard updated != value else { return }
            var next = stored; next.value = try JSONValue.encoded(updated.raw)
            guard try JSONEncoder().encode(next.value).count <= 96 * 1_024 else { throw HarborError(code: "watched-by-record") }
            try save(next); error = nil
            if account != nil { requestSync?() }
        } catch {
            self.error = "Could not save watch attribution. Previous watches are kept."
            throw error
        }
    }
    func synchronize(state: JSONValue, send: @MainActor (JSONValue) async throws -> JSONValue, check: @MainActor () throws -> Void) async throws {
        guard ready, account != nil else { throw HarborError(code: "watched-by-account") }
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            try check(); try Task.checkCancellation()
            let incoming = try HarborLayoutDocument.state(state, key: Self.documentKey)
            if let incoming, let previous = stored.shadow {
                guard incoming.rev >= previous.rev, incoming.rev != previous.rev || incoming.value == previous.value else { throw HarborError(code: "watched-by-revision") }
            }
            var next = stored
            next.value = try JSONValue.encoded(value.merging(DesktopWatchedBy(incoming?.value ?? .null)).raw)
            next.shadow = incoming
            try check(); try save(next)
            guard hasPendingChanges else { error = nil; return }
            let sent = stored.value
            let base = HarborLayoutDocument(key: Self.documentKey, rev: incoming?.rev ?? 0, value: sent)
            let response = try await send(base.write(sent))
            try Task.checkCancellation(); try check()
            next = stored
            switch try base.result(response) {
            case .accepted(let revision):
                next.shadow = HarborLayoutDocument(key: Self.documentKey, rev: revision, value: sent)
            case .rejected(let current):
                next.shadow = current
                next.value = try JSONValue.encoded(value.merging(DesktopWatchedBy(current.value)).raw)
            }
            try save(next); error = nil
            if hasPendingChanges { requestSync?() }
        } catch {
            self.error = "Watch attribution is kept on this device. Synchronization will retry."
            throw error
        }
    }
}
