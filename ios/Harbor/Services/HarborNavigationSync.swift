import Foundation
import Observation

struct NavigationSyncRecord: Codable, Sendable {
    struct Pending: Codable, Sendable { let version: UUID; var baseRev: Int64; let value: JSONValue; var preservesSharedBackup: Bool? = nil }
    struct Parked: Codable, Sendable { let value: JSONValue; let lostToRev: Int64 }
    var version = 1
    var shadow: HarborLayoutDocument?
    var appliedLocal: NativeNavigationLayout?
    var pending: Pending?
    var parked: Parked?
}
@MainActor protocol NavigationSyncPersistence {
    func readSync(_ key: String) throws -> NavigationSyncRecord?
    func writeSync(_ value: NavigationSyncRecord, key: String) throws
}
@MainActor struct KeychainNavigationSyncPersistence: NavigationSyncPersistence {
    func readSync(_ key: String) throws -> NavigationSyncRecord? { try KeychainStore().read(key, as: NavigationSyncRecord.self) }
    func writeSync(_ value: NavigationSyncRecord, key: String) throws { try KeychainStore().write(value, key: key) }
}

/// Desktop replaces layout sections as a whole. A conflict adopts the server
/// and parks our version locally; it never silently merges two row orderings.
@MainActor @Observable
final class HarborNavigationSync {
    private let owner: String
    let preferences: ScopedNavigationPreferences
    private let persistence: any NavigationSyncPersistence
    private let defaultOrder: [String]
    private let knownIDs: Set<String>
    private var scope: NavigationScope?
    private var documentKey = ""
    private var stored = NavigationSyncRecord()
    private var hydrated = false
    private(set) var error: String?
    @ObservationIgnored var requestSync: (@MainActor () -> Void)?
    var hasPendingChanges: Bool { scope != nil && stored.pending != nil }
    var hasParkedVersion: Bool { scope != nil && stored.parked != nil }
    func refreshSharedValue() throws { try preferences.refreshStoredValue() }

    init(owner: String, preferences: ScopedNavigationPreferences, defaultOrder: [String], knownIDs: Set<String>, persistence: (any NavigationSyncPersistence)? = nil) {
        self.owner = owner; self.preferences = preferences; self.defaultOrder = defaultOrder; self.knownIDs = knownIDs
        self.persistence = persistence ?? KeychainNavigationSyncPersistence()
    }
    func unbind() {
        if preferences.scope == scope { preferences.onEdit = nil }
        scope = nil; documentKey = ""; hydrated = false; error = nil
    }
    private func check(_ expected: NavigationScope) throws {
        try Task.checkCancellation()
        guard scope == expected, preferences.scope == expected, preferences.ready else { throw HarborError(code: "account-changed") }
    }
    private func save(_ next: NavigationSyncRecord) throws {
        guard let scope, !documentKey.isEmpty, next.version == 1, try JSONEncoder().encode(next).count <= 384 * 1_024 else { throw HarborError(code: "navigation-sync-store") }
        try persistence.writeSync(next, key: syncKey(scope, key: documentKey)); stored = next
    }
    private func syncKey(_ scope: NavigationScope, key: String) -> String { "navigation-sync-" + EBookShelf.hash(scope.key + "|" + key) }
    private func codec(_ value: JSONValue? = nil) throws -> DesktopNavigationLayout { try DesktopNavigationLayout(value ?? stored.pending?.value ?? stored.shadow?.value ?? .object([:])) }
    private func mobile(_ value: NativeNavigationLayout) -> NativeNavigationLayout {
        var seen = Set<String>()
        return NativeNavigationLayout(order: (value.order + defaultOrder).filter { knownIDs.contains($0) && seen.insert($0).inserted }, hidden: value.hidden.intersection(knownIDs), renamed: value.renamed.filter { knownIDs.contains($0.key) })
    }
    private func enqueue(_ layout: NativeNavigationLayout, force: Bool = false, base: JSONValue? = nil, replacedAt: Int64? = nil) throws {
        guard hydrated, let scope else { return }
        try check(scope)
        if !force {
            if let pending = stored.pending {
                let previous = try codec(pending.value).native(knownIDs: knownIDs, preserving: layout, defaultOrder: defaultOrder)
                if mobile(previous) == mobile(layout) { return }
            } else if let previous = stored.appliedLocal, mobile(previous) == mobile(layout) { return }
        }
        let value = try codec(base).applying(layout, knownIDs: knownIDs, defaultOrder: defaultOrder).raw
        var next = stored
        if let revision = replacedAt, let previous = stored.pending, previous.preservesSharedBackup != true { next.parked = .init(value: previous.value, lostToRev: revision) }
        next.pending = NavigationSyncRecord.Pending(version: UUID(), baseRev: stored.shadow?.rev ?? 0, value: value)
        if replacedAt != nil { next.pending?.preservesSharedBackup = true }
        try save(next); error = nil; requestSync?()
    }
    func restoreMyVersion() {
        guard let scope, let parked = stored.parked else { return }
        do {
            try check(scope)
            let next = try codec(parked.value).native(knownIDs: knownIDs, preserving: preferences.value, defaultOrder: defaultOrder)
            try preferences.apply(next, to: scope, editor: scope.editorID)
            // Explicit restore remains meaningful even if a deleted server
            // document left the same visible mobile values on this device.
            try enqueue(next, force: true, base: stored.shadow?.value ?? .object([:]))
        } catch { self.error = "Could not restore your navigation. The saved version is kept." }
    }

    func synchronize(state: JSONValue, account: String, profile: JSONValue, send: @MainActor (JSONValue) async throws -> JSONValue) async throws {
        try Task.checkCancellation()
        guard preferences.scope?.owner == owner, let profileID = profile["syncId"].string,
              !account.isEmpty, !profileID.isEmpty, profileID != "account", profileID.utf8.count <= 256 else { throw HarborError(code: "navigation-sync-target") }
        let expected = NavigationScope.harbor(owner: owner, account: account, profile: profileID, linked: profile["settingsLinked"] != .bool(false))
        let key = profileID + ":nav"
        let incoming = try HarborLayoutDocument.state(state, key: key)
        if let incoming { _ = try codec(incoming.value) }
        if scope != expected || preferences.scope != expected {
            let loaded = try persistence.readSync(syncKey(expected, key: key)) ?? NavigationSyncRecord()
            guard loaded.version == 1, loaded.appliedLocal?.valid != false else { throw HarborError(code: "navigation-sync-store") }
            if let shadow = loaded.shadow {
                guard shadow.key == key, shadow.rev >= 0, shadow.rev <= HarborLayoutDocument.maximumRevision else { throw HarborError(code: "navigation-sync-store") }
                _ = try DesktopNavigationLayout(shadow.value)
            }
            if let pending = loaded.pending {
                guard pending.baseRev >= 0, pending.baseRev <= HarborLayoutDocument.maximumRevision else { throw HarborError(code: "navigation-sync-store") }
                _ = try DesktopNavigationLayout(pending.value)
            }
            if let parked = loaded.parked { _ = try DesktopNavigationLayout(parked.value) }
            preferences.bind(expected)
            guard preferences.ready else { throw HarborError(code: "navigation-sync-store") }
            scope = expected; documentKey = key; stored = loaded; hydrated = false
        }
        try check(expected)
        // Recover an edit whose native preference write succeeded but whose
        // queue write failed. Do this before applying any incoming server data.
        if let pending = stored.pending,
           mobile(try codec(pending.value).native(knownIDs: knownIDs, preserving: preferences.value, defaultOrder: defaultOrder)) != mobile(preferences.value) {
            let revision = try HarborLayoutDocument.revision(state["rev"])
            hydrated = true; try enqueue(preferences.value, replacedAt: preferences.lastEditor == "" ? revision : nil)
        } else if stored.pending == nil, preferences.lastEditor == nil || preferences.lastEditor == expected.editorID,
                  let previous = stored.appliedLocal, mobile(previous) != mobile(preferences.value) {
            hydrated = true; try enqueue(preferences.value)
        }
        let baseRev = stored.pending?.baseRev ?? stored.shadow?.rev ?? 0
        if let incoming, incoming.rev < baseRev { throw HarborError(code: "layout-sync-response") }
        if let incoming, let shadow = stored.shadow, incoming.rev == shadow.rev, incoming.value != shadow.value { throw HarborError(code: "layout-sync-response") }
        hydrated = true
        preferences.onEdit = { [weak self] value in
            guard let self, self.scope == expected else { return }
            do { try self.enqueue(value) }
            catch { self.error = "Your navigation is saved locally. Cloud sync will retry." }
        }
        if stored.pending == nil, let incoming, incoming == stored.shadow, preferences.lastEditor != nil { error = nil; return }
        if stored.pending == nil, incoming == nil, stored.shadow == nil, stored.appliedLocal == preferences.value { error = nil; return }
        if let pending = stored.pending, let incoming, incoming.value == pending.value {
            var next = stored; next.shadow = incoming; next.pending = nil
            if pending.preservesSharedBackup != true { next.parked = nil }
            next.appliedLocal = preferences.value; try save(next); error = nil; return
        }
        if let pending = stored.pending, (incoming == nil && pending.baseRev > 0) || (incoming?.rev ?? 0) > pending.baseRev {
            var next = stored
            if pending.preservesSharedBackup != true { next.parked = NavigationSyncRecord.Parked(value: pending.value, lostToRev: incoming?.rev ?? 0) }
            next.pending = nil; next.shadow = incoming
            if let incoming {
                let adopted = try codec(incoming.value).native(knownIDs: knownIDs, preserving: preferences.value, defaultOrder: defaultOrder)
                try preferences.apply(adopted, to: expected); next.appliedLocal = adopted
            } else { next.appliedLocal = preferences.value }
            try save(next); error = nil; return
        }
        if stored.pending == nil {
            var next = stored
            if let incoming {
                let adopted = try codec(incoming.value).native(knownIDs: knownIDs, preserving: preferences.value, defaultOrder: defaultOrder)
                if stored.appliedLocal == nil, mobile(preferences.value) != mobile(adopted), preferences.value != NativeNavigationLayout() {
                    next.parked = NavigationSyncRecord.Parked(value: try codec(incoming.value).applying(preferences.value, knownIDs: knownIDs, defaultOrder: defaultOrder).raw, lostToRev: incoming.rev)
                }
                try preferences.apply(adopted, to: expected); next.appliedLocal = adopted
            } else { next.appliedLocal = preferences.value }
            next.shadow = incoming; try save(next); error = nil; return
        }
        guard let pending = stored.pending else { return }
        let base = HarborLayoutDocument(key: key, rev: pending.baseRev, value: pending.value)
        let response = try await send(base.write(pending.value))
        try check(expected)
        switch try base.result(response) {
        case .accepted(let revision):
            let accepted = HarborLayoutDocument(key: key, rev: revision, value: pending.value)
            var next = stored; next.shadow = accepted
            if pending.preservesSharedBackup != true { next.parked = nil }
            next.appliedLocal = try codec(pending.value).native(knownIDs: knownIDs, preserving: preferences.value, defaultOrder: defaultOrder)
            if next.pending?.version == pending.version { next.pending = nil }
            else { next.pending?.baseRev = revision }
            try save(next); error = nil
            if next.pending != nil { requestSync?() }
        case .rejected(let current):
            let adopted = try codec(current.value).native(knownIDs: knownIDs, preserving: preferences.value, defaultOrder: defaultOrder)
            var next = stored
            if next.pending?.preservesSharedBackup != true { next.parked = NavigationSyncRecord.Parked(value: next.pending?.value ?? pending.value, lostToRev: current.rev) }
            next.pending = nil; next.shadow = current; next.appliedLocal = adopted
            try preferences.apply(adopted, to: expected); try save(next); error = nil
        }
    }
}
