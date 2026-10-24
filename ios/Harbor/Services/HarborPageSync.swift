import Foundation
import Observation

struct PageSyncRecord: Codable, Sendable {
    struct Pending: Codable, Sendable { let version: UUID; var baseRev: Int64; let value: JSONValue }
    struct Parked: Codable, Sendable { let value: JSONValue; let lostToRev: Int64 }
    struct Adoption: Codable, Sendable { let previous: PageLayout; let next: PageLayout }
    var version = 1
    var shadow: HarborLayoutDocument?
    var applied: PageLayout?
    var pending: Pending?
    var parked: Parked?
    var adoption: Adoption?
}
@MainActor protocol PageSyncPersistence {
    func read(_ key: String) throws -> PageSyncRecord?
    func write(_ value: PageSyncRecord, key: String) throws
}
@MainActor private struct KeychainPageSync: PageSyncPersistence {
    func read(_ key: String) throws -> PageSyncRecord? { try KeychainStore().read(key, as: PageSyncRecord.self) }
    func write(_ value: PageSyncRecord, key: String) throws { try KeychainStore().write(value, key: key) }
}

/// Whole-section replacement follows Desktop's server revision authority.
/// The journal is written before applying a remote layout, and local conflicts
/// remain recoverable instead of being merged into an invented row ordering.
@MainActor @Observable final class HarborPageSync {
    let preferences: PageCustomization
    private let persistence: any PageSyncPersistence
    private var scope: NavigationScope?
    private var document = ""
    private var stored = PageSyncRecord()
    private var mapping: DesktopPageRowMap
    private var generation = 0
    private var hydrated = false
    private var busy = false
    private(set) var error: String?
    @ObservationIgnored var requestSync: (() -> Void)?
    var hasPendingChanges: Bool { scope != nil && stored.pending != nil }
    var hasParkedVersion: Bool { scope != nil && stored.parked != nil }

    init(preferences: PageCustomization, persistence: (any PageSyncPersistence)? = nil) {
        self.preferences = preferences; self.persistence = persistence ?? KeychainPageSync()
        mapping = DesktopPageRowMap(page: preferences.page, rails: preferences.currentRails)
    }
    func unbind() {
        generation += 1
        if preferences.scope == scope { preferences.onEdit = nil; preferences.onRails = nil }
        scope = nil; document = ""; hydrated = false; busy = false; error = nil
    }
    private func check(_ expected: NavigationScope, generation: Int) throws {
        try Task.checkCancellation()
        guard generation == self.generation, scope == expected, preferences.scope == expected, preferences.ready else { throw HarborError(code: "account-changed") }
    }
    private func key(_ scope: NavigationScope, document: String) -> String { "page-layout-sync-" + EBookShelf.hash(scope.key + "|" + document) }
    private func codec(_ raw: JSONValue? = nil) throws -> DesktopPageLayout {
        try DesktopPageLayout(page: preferences.page, raw: raw ?? stored.pending?.value ?? stored.shadow?.value ?? .object([:]))
    }
    private func save(_ value: PageSyncRecord) throws {
        guard let scope, !document.isEmpty, value.version == 1, try JSONEncoder().encode(value).count <= 512 * 1_024 else { throw HarborError(code: "page-sync-store") }
        try persistence.write(value, key: key(scope, document: document)); stored = value
    }
    private func validate(_ value: PageSyncRecord, document: String) throws {
        guard value.version == 1, value.applied.map(PageCustomization.valid) != false else { throw HarborError(code: "page-sync-store") }
        if let shadow = value.shadow {
            guard shadow.key == document, (0...HarborLayoutDocument.maximumRevision).contains(shadow.rev) else { throw HarborError(code: "page-sync-store") }
            _ = try codec(shadow.value)
        }
        if let pending = value.pending {
            guard (0...HarborLayoutDocument.maximumRevision).contains(pending.baseRev) else { throw HarborError(code: "page-sync-store") }
            _ = try codec(pending.value)
        }
        if let parked = value.parked { _ = try codec(parked.value) }
        if let adoption = value.adoption {
            guard PageCustomization.valid(adoption.previous), PageCustomization.valid(adoption.next) else { throw HarborError(code: "page-sync-store") }
        }
    }
    private func completeAdoption(_ expected: NavigationScope) throws {
        guard let adoption = stored.adoption else { return }
        // A user can edit after a journal failure. Preserve that newer local edit;
        // the applied baseline below lets the next synchronization enqueue it.
        if preferences.layout == adoption.previous || preferences.layout == adoption.next { try preferences.apply(adoption.next, to: expected) }
        var next = stored; next.adoption = nil; next.applied = adoption.next; try save(next)
    }
    private func adopt(_ layout: PageLayout, record: PageSyncRecord, in expected: NavigationScope) throws {
        var journal = record; journal.adoption = .init(previous: preferences.layout, next: layout)
        try save(journal); try completeAdoption(expected)
    }
    private func enqueue(_ layout: PageLayout) throws {
        guard hydrated, let scope else { return }
        try check(scope, generation: generation)
        let raw = try codec().applying(layout, mapping: mapping).raw
        if let pending = stored.pending, pending.value == raw { return }
        if stored.pending == nil, let applied = stored.applied, try codec().applying(applied, mapping: mapping).raw == raw { return }
        var next = stored; next.pending = .init(version: UUID(), baseRev: stored.shadow?.rev ?? 0, value: raw)
        try save(next); error = nil; requestSync?()
    }
    private func register(_ rails: [PageRail], in expected: NavigationScope, generation: Int) throws {
        try check(expected, generation: generation)
        var nextMap = mapping; nextMap.register(rails)
        guard nextMap != mapping else { return }
        mapping = nextMap
        if let raw = stored.pending?.value ?? stored.shadow?.value {
            let layout = try codec(raw).native(preserving: preferences.layout, mapping: mapping)
            try adopt(layout, record: stored, in: expected)
        }
    }
    func restoreMyVersion() {
        guard let scope, let parked = stored.parked else { return }
        do {
            try check(scope, generation: generation)
            let layout = try codec(parked.value).native(preserving: preferences.layout, mapping: mapping)
            try adopt(layout, record: stored, in: scope)
            // Desktop's explicit restore re-pushes the entire parked section.
            // Later edits must keep its opaque fields until it is acknowledged.
            var next = stored; next.pending = .init(version: UUID(), baseRev: stored.shadow?.rev ?? 0,
                value: try codec(parked.value).applying(layout, mapping: mapping).raw)
            try save(next); error = nil; requestSync?()
        } catch { self.error = "Could not restore your layout. The saved version is kept." }
    }
    func synchronize(state: JSONValue, account: String, profile: JSONValue, send: @MainActor (JSONValue) async throws -> JSONValue) async throws {
        guard !busy else { return }
        try Task.checkCancellation()
        guard preferences.ready, !account.isEmpty, account.utf8.count <= 256, let id = profile["syncId"].string,
              !id.isEmpty, id != "account", id.utf8.count <= 256 else { throw HarborError(code: "page-sync-target") }
        let expected = NavigationScope.harbor(owner: preferences.owner, account: account, profile: id, linked: profile["settingsLinked"] != .bool(false))
        let document = id + ":" + preferences.page, incoming = try HarborLayoutDocument.state(state, key: id + ":" + preferences.page)
        if let incoming { _ = try codec(incoming.value) }
        if scope != expected || preferences.scope != expected {
            let value = try persistence.read(key(expected, document: document)) ?? PageSyncRecord()
            try validate(value, document: document)
            preferences.bind(expected)
            guard preferences.ready else { throw HarborError(code: "page-sync-store") }
            self.scope = expected; self.document = document; stored = value; hydrated = false
            mapping = DesktopPageRowMap(page: preferences.page, rails: preferences.currentRails)
        }
        let generation = self.generation; busy = true
        defer { if self.generation == generation { busy = false } }
        try check(expected, generation: generation); try completeAdoption(expected)
        if stored.pending == nil, let applied = stored.applied,
           try codec().applying(applied, mapping: mapping).raw != codec().applying(preferences.layout, mapping: mapping).raw {
            hydrated = true; try enqueue(preferences.layout)
        }
        let revision = stored.pending?.baseRev ?? stored.shadow?.rev ?? 0
        if let incoming, incoming.rev < revision { throw HarborError(code: "layout-sync-response") }
        if let incoming, let shadow = stored.shadow, incoming.rev == shadow.rev, incoming.value != shadow.value { throw HarborError(code: "layout-sync-response") }
        hydrated = true
        preferences.onEdit = { [weak self] layout in
            guard let self, self.generation == generation, self.scope == expected else { return }
            do { try self.enqueue(layout) } catch { self.error = "Your layout is saved locally. Cloud sync will retry." }
        }
        preferences.onRails = { [weak self] rails in
            guard let self else { return }
            do { try self.register(rails, in: expected, generation: generation) } catch { self.error = "Your layout is saved locally. Cloud sync will retry." }
        }
        if let pending = stored.pending, let incoming, incoming.value == pending.value {
            var next = stored; next.shadow = incoming; next.pending = nil; next.parked = nil; next.applied = preferences.layout
            try save(next); error = nil; return
        }
        if let pending = stored.pending, (incoming == nil && pending.baseRev > 0) || (incoming?.rev ?? 0) > pending.baseRev {
            var next = stored; next.parked = .init(value: pending.value, lostToRev: incoming?.rev ?? 0); next.pending = nil; next.shadow = incoming
            if let incoming { try adopt(codec(incoming.value).native(preserving: preferences.layout, mapping: mapping), record: next, in: expected) }
            else { next.applied = preferences.layout; try save(next) }
            error = nil; return
        }
        if stored.pending == nil {
            var next = stored; next.shadow = incoming
            if let incoming {
                let layout = try codec(incoming.value).native(preserving: preferences.layout, mapping: mapping)
                var defaults = PageLayout(); defaults.secondaryMoreInfo = preferences.page != "home"; defaults.playButtonSquare = preferences.page != "home"
                if stored.applied == nil, preferences.layout != defaults,
                   try codec(incoming.value).applying(preferences.layout, mapping: mapping).raw != codec(incoming.value).applying(layout, mapping: mapping).raw {
                    next.parked = .init(value: try codec(incoming.value).applying(preferences.layout, mapping: mapping).raw, lostToRev: incoming.rev)
                }
                try adopt(layout, record: next, in: expected)
            } else { next.applied = preferences.layout; try save(next) }
            error = nil; return
        }
        guard let pending = stored.pending else { return }
        let base = HarborLayoutDocument(key: document, rev: pending.baseRev, value: pending.value)
        let response = try await send(base.write(pending.value))
        try check(expected, generation: generation)
        switch try base.result(response) {
        case .accepted(let revision):
            var next = stored; next.shadow = .init(key: document, rev: revision, value: pending.value); next.parked = nil
            next.applied = try codec(pending.value).native(preserving: preferences.layout, mapping: mapping)
            if next.pending?.version == pending.version { next.pending = nil } else { next.pending?.baseRev = revision }
            try save(next); error = nil
            if next.pending != nil { requestSync?() }
        case .rejected(let current):
            let layout = try codec(current.value).native(preserving: preferences.layout, mapping: mapping)
            var next = stored; next.parked = .init(value: next.pending?.value ?? pending.value, lostToRev: current.rev); next.pending = nil; next.shadow = current
            try adopt(layout, record: next, in: expected); error = nil
        }
    }
}
