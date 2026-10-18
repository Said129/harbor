import Foundation
import Observation

struct DesktopStreamingSelection: Sendable {
    let raw: JSONValue
    init(_ raw: JSONValue) throws {
        guard case .object(let fields) = raw, fields.count <= 128,
              fields.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
              try JSONEncoder().encode(raw).count <= 96 * 1_024 else { throw HarborError(code: "streaming-sync-value") }
        for service in StreamingServiceDefinition.all {
            if let value = fields[service.key], case .bool = value { continue }
            if fields[service.key] != nil { throw HarborError(code: "streaming-sync-value") }
        }
        self.raw = raw
    }
    var selection: [String: Bool] {
        Dictionary(uniqueKeysWithValues: StreamingServiceDefinition.all.map { service in
            if case .bool(let enabled) = raw[service.key] { return (service.key, enabled) }
            return (service.key, service.enabledByDefault)
        })
    }
    func applying(_ selection: [String: Bool]) throws -> Self {
        guard Set(selection.keys) == Set(StreamingServiceDefinition.all.map(\.key)) else { throw HarborError(code: "streaming-sync-value") }
        var fields = raw.objectValue
        for (key, enabled) in selection { fields[key] = .bool(enabled) }
        return try Self(.object(fields))
    }
}

struct StreamingSyncRecord: Codable, Sendable {
    struct Pending: Codable, Sendable { let version: UUID; var baseRev: Int64; let value: JSONValue }
    struct Parked: Codable, Sendable { let value: JSONValue; let lostToRev: Int64 }
    struct Adoption: Codable, Sendable { let previous: [String: Bool]; let next: [String: Bool] }
    var version = 1
    var shadow: HarborLayoutDocument?
    var appliedLocal: [String: Bool]?
    var pending: Pending?
    var parked: Parked?
    var adoption: Adoption?
}
@MainActor protocol StreamingSyncPersistence {
    func readSync(_ key: String) throws -> StreamingSyncRecord?
    func writeSync(_ value: StreamingSyncRecord, key: String) throws
}
@MainActor private struct KeychainStreamingSync: StreamingSyncPersistence {
    func readSync(_ key: String) throws -> StreamingSyncRecord? { try KeychainStore().read(key, as: StreamingSyncRecord.self) }
    func writeSync(_ value: StreamingSyncRecord, key: String) throws { try KeychainStore().write(value, key: key) }
}

/// The services document is replaced whole, matching Desktop's layout adapter.
/// Unknown Desktop fields remain in the shadow when a mobile checkbox changes.
@MainActor @Observable final class HarborStreamingSync {
    private let owner: String
    private let preferences: StreamingPreferences
    private let persistence: any StreamingSyncPersistence
    private var scope: NavigationScope?
    private var documentKey = ""
    private var stored = StreamingSyncRecord()
    private var hydrated = false
    private(set) var error: String?
    @ObservationIgnored var requestSync: (() -> Void)?
    var hasPendingChanges: Bool { scope != nil && (stored.pending != nil || stored.adoption != nil) }
    var hasParkedVersion: Bool { scope != nil && stored.parked != nil }

    init(owner: String, preferences: StreamingPreferences, persistence: (any StreamingSyncPersistence)? = nil) {
        self.owner = owner; self.preferences = preferences; self.persistence = persistence ?? KeychainStreamingSync()
    }
    func unbind() {
        if let scope, preferences.scope == scope { preferences.onEdit = nil; preferences.holdCloudWrite(false, in: scope) }
        scope = nil; documentKey = ""; stored = StreamingSyncRecord(); hydrated = false; error = nil
    }
    private func check(_ expected: NavigationScope) throws {
        try Task.checkCancellation()
        guard scope == expected, preferences.scope == expected, preferences.ready else { throw HarborError(code: "account-changed") }
    }
    private func storageKey(_ scope: NavigationScope, document: String) -> String {
        let data = try! JSONEncoder().encode([scope.key, document])
        return "streaming-sync-" + EBookShelf.hash(String(decoding: data, as: UTF8.self))
    }
    private func save(_ next: StreamingSyncRecord) throws {
        guard let scope, !documentKey.isEmpty, next.version == 1,
              try JSONEncoder().encode(next).count <= 384 * 1_024 else { throw HarborError(code: "streaming-sync-store") }
        try persistence.writeSync(next, key: storageKey(scope, document: documentKey)); stored = next
    }
    private func codec(_ value: JSONValue? = nil) throws -> DesktopStreamingSelection {
        try DesktopStreamingSelection(value ?? stored.shadow?.value ?? .object([:]))
    }
    private func adopt(_ next: StreamingSyncRecord, selection: [String: Bool], in expected: NavigationScope) throws {
        var next = next
        if preferences.selection == selection { next.appliedLocal = selection; try save(next); return }
        // Persist the conflict backup and the application intent before
        // replacing preferences. A second Keychain write is recoverable.
        next.adoption = StreamingSyncRecord.Adoption(previous: preferences.selection, next: selection)
        try save(next)
        try completeAdoption(in: expected)
    }
    private func completeAdoption(in expected: NavigationScope) throws {
        guard let adoption = stored.adoption else { return }
        try check(expected)
        preferences.holdCloudWrite(true, in: expected)
        let current = preferences.selection
        if current != adoption.previous, current != adoption.next {
            // Another linked profile may have saved newer local settings
            // while this process was stopped. Keep that explicit choice.
            var next = stored; next.adoption = nil; next.appliedLocal = adoption.next
            try save(next); preferences.holdCloudWrite(false, in: expected)
            hydrated = true; try enqueue(current)
            return
        }
        try preferences.apply(adoption.next, to: expected)
        var next = stored; next.adoption = nil; next.appliedLocal = adoption.next
        try save(next); preferences.holdCloudWrite(false, in: expected)
    }
    private func enqueue(_ selection: [String: Bool], force: Bool = false) throws {
        guard hydrated, let scope else { return }
        try check(scope)
        if !force {
            if let pending = stored.pending, try codec(pending.value).selection == selection { return }
            if stored.pending == nil, stored.appliedLocal == selection { return }
        }
        var next = stored
        next.pending = StreamingSyncRecord.Pending(version: UUID(), baseRev: stored.shadow?.rev ?? 0, value: try codec().applying(selection).raw)
        try save(next); error = nil; requestSync?()
    }
    func restoreMyVersion() {
        guard let scope, let parked = stored.parked, !preferences.cloudWritePending else { return }
        do {
            try check(scope)
            let selection = try codec(parked.value).selection
            try preferences.apply(selection, to: scope)
            try enqueue(selection, force: true)
        } catch { self.error = "Could not restore your services. The saved version is kept." }
    }
    private func validate(_ record: StreamingSyncRecord, key: String) throws {
        guard record.version == 1 else { throw HarborError(code: "streaming-sync-store") }
        if let shadow = record.shadow {
            guard shadow.key == key, shadow.rev >= 0, shadow.rev <= HarborLayoutDocument.maximumRevision else { throw HarborError(code: "streaming-sync-store") }
            _ = try codec(shadow.value)
        }
        if let pending = record.pending {
            guard pending.baseRev >= 0, pending.baseRev <= HarborLayoutDocument.maximumRevision else { throw HarborError(code: "streaming-sync-store") }
            _ = try codec(pending.value)
        }
        if let parked = record.parked {
            guard parked.lostToRev >= 0, parked.lostToRev <= HarborLayoutDocument.maximumRevision else { throw HarborError(code: "streaming-sync-store") }
            _ = try codec(parked.value)
        }
        if let applied = record.appliedLocal { _ = try DesktopStreamingSelection(.object([:])).applying(applied) }
        if let adoption = record.adoption {
            _ = try DesktopStreamingSelection(.object([:])).applying(adoption.previous)
            _ = try DesktopStreamingSelection(.object([:])).applying(adoption.next)
        }
    }

    func synchronize(state: JSONValue, account: String, profile: JSONValue, send: @MainActor (JSONValue) async throws -> JSONValue) async throws {
        try Task.checkCancellation()
        guard preferences.owner == owner, !account.isEmpty, account.utf8.count <= 256,
              let id = profile["syncId"].string, !id.isEmpty, id != "account", id.utf8.count <= 256 else { throw HarborError(code: "streaming-sync-target") }
        let expected = NavigationScope.harbor(owner: owner, account: account, profile: id, linked: profile["settingsLinked"] != .bool(false))
        let key = id + ":services", incoming = try HarborLayoutDocument.state(state, key: id + ":services")
        if let incoming { _ = try codec(incoming.value) }
        if scope != expected || preferences.scope != expected {
            preferences.bind(expected)
            guard preferences.ready else { throw HarborError(code: "streaming-sync-store") }
            scope = nil; documentKey = ""; hydrated = false; stored = StreamingSyncRecord()
            let loaded = try persistence.readSync(storageKey(expected, document: key)) ?? StreamingSyncRecord()
            try validate(loaded, key: key)
            scope = expected; documentKey = key; stored = loaded
        }
        try check(expected)
        try completeAdoption(in: expected)
        // Recover a locally saved checkbox if persisting its queue failed.
        // Also preserve a newer local edit when an older pending edit exists.
        if let pending = stored.pending {
            if try codec(pending.value).selection != preferences.selection { hydrated = true; try enqueue(preferences.selection) }
        } else if let previous = stored.appliedLocal, previous != preferences.selection {
            hydrated = true; try enqueue(preferences.selection)
        }
        let baseRev = stored.pending?.baseRev ?? stored.shadow?.rev ?? 0
        if let incoming, incoming.rev < baseRev { throw HarborError(code: "layout-sync-response") }
        if let incoming, let shadow = stored.shadow, incoming.rev == shadow.rev, incoming.value != shadow.value { throw HarborError(code: "layout-sync-response") }
        hydrated = true
        preferences.onEdit = { [weak self] selection in
            guard let self, self.scope == expected else { return }
            do { try self.enqueue(selection) }
            catch { self.error = "Your services are saved locally. Cloud sync will retry." }
        }
        if let pending = stored.pending, let incoming, incoming.value == pending.value {
            var next = stored; next.shadow = incoming; next.pending = nil; next.parked = nil
            next.appliedLocal = preferences.selection; try save(next); error = nil; return
        }
        if let pending = stored.pending, (incoming == nil && pending.baseRev > 0) || (incoming?.rev ?? 0) > pending.baseRev {
            var next = stored
            next.parked = StreamingSyncRecord.Parked(value: pending.value, lostToRev: incoming?.rev ?? 0)
            next.pending = nil; next.shadow = incoming
            if let incoming { try adopt(next, selection: codec(incoming.value).selection, in: expected) }
            else { next.appliedLocal = preferences.selection; try save(next) }
            error = nil; return
        }
        if stored.pending == nil {
            var next = stored
            if let incoming {
                let adopted = try codec(incoming.value).selection
                if stored.appliedLocal == nil, !preferences.values.isEmpty, preferences.selection != adopted {
                    next.parked = StreamingSyncRecord.Parked(value: try codec(incoming.value).applying(preferences.selection).raw, lostToRev: incoming.rev)
                }
                next.shadow = incoming
                try adopt(next, selection: adopted, in: expected); error = nil; return
            }
            next.appliedLocal = preferences.selection; next.shadow = incoming; try save(next); error = nil; return
        }
        guard let pending = stored.pending else { return }
        let base = HarborLayoutDocument(key: key, rev: pending.baseRev, value: pending.value)
        let response = try await send(base.write(pending.value))
        try check(expected)
        switch try base.result(response) {
        case .accepted(let revision):
            var next = stored
            next.shadow = HarborLayoutDocument(key: key, rev: revision, value: pending.value); next.parked = nil
            next.appliedLocal = try codec(pending.value).selection
            if next.pending?.version == pending.version { next.pending = nil }
            else { next.pending?.baseRev = revision }
            try save(next); error = nil
            if next.pending != nil { requestSync?() }
        case .rejected(let current):
            let adopted = try codec(current.value).selection
            var next = stored
            next.parked = StreamingSyncRecord.Parked(value: next.pending?.value ?? pending.value, lostToRev: current.rev)
            next.pending = nil; next.shadow = current; next.appliedLocal = adopted
            try adopt(next, selection: adopted, in: expected); error = nil
        }
    }
}
