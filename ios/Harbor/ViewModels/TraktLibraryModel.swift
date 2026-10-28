import Foundation
import Observation

@MainActor @Observable final class TraktLibraryModel {
    let account: TraktAccountStore
    let store: TraktLibraryStore
    private let client: TraktClient
    private let active: TraktClient.Active
    private var operation = UUID()
    private(set) var loading = false
    private(set) var transferring = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var error: String?
    @ObservationIgnored private var projection: (revision: Int, watchlist: [LibraryRecord], history: [LibraryRecord])?
    var isActive: Bool { active() }
    var watchlist: [LibraryRecord] { index().watchlist }
    var history: [LibraryRecord] { index().history }
    init(account: TraktAccountStore, store: TraktLibraryStore, client: TraktClient = .shared, active: @escaping TraktClient.Active) {
        self.account = account; self.store = store; self.client = client; self.active = active
    }
    convenience init(app: AppModel) {
        let owner = app.personalOwner, scope = app.accountOperationScope
        self.init(account: .forOwner(owner), store: .forOwner(owner), active: { [weak app] in
            app?.personalOwner == owner && app?.accountOperationScope == scope && app?.storageReady == true
        })
    }
    private func index() -> (watchlist: [LibraryRecord], history: [LibraryRecord]) {
        if let projection, projection.revision == store.revision { return (projection.watchlist, projection.history) }
        let watchlist = store.snapshot.watchlistRecords, history = store.snapshot.historyRecords
        projection = (store.revision, watchlist, history); return (watchlist, history)
    }
    func loadAccount() {
        guard active() else { return }
        do { if !account.ready { try account.load() }; store.bind(account.session?.trackingID) }
        catch { self.error = "Could not read the account on this device." }
    }
    func cancel() { operation = UUID(); loading = false; transferring = false }
    private func current(_ ticket: UUID, accountIdentity: UUID) -> Bool {
        ticket == operation && active() && account.identity == accountIdentity && account.session != nil && account.owner == store.owner && !Task.isCancelled
    }
    func refresh(force: Bool = false) async {
        guard active(), !loading, !transferring, !store.updating else { return }; loadAccount()
        guard let fingerprint = store.fingerprint, account.session != nil else { return }
        if !force, let date = store.refreshedAt, date.timeIntervalSinceNow > -20 { return }
        let ticket = operation, identity = account.identity
        let lease: TraktClient.Active = { [weak self] in self?.current(ticket, accountIdentity: identity) ?? false }
        loading = true; error = nil; defer { if ticket == operation { loading = false } }
        do {
            do { try await store.restore() } catch is CancellationError { throw CancellationError() }
            catch { /* A complete provider reply may replace a damaged disposable cache. */ }
            let revision = store.revision
            let list = try await account.response(.library(.watchlist), client: client, active: lease)
            let history = try await account.response(.library(.history), client: client, active: lease)
            let snapshot = TraktLibrarySnapshot(watchlist: try TraktLibraryItem.watchlist(list), history: try TraktLibraryItem.history(history))
            guard lease() else { return }; try await store.commit(snapshot, fingerprint: fingerprint, revision: revision)
        } catch is CancellationError { }
        catch { if lease() { self.error = Self.message(error) } }
    }
    func setWatchlisted(_ saved: Bool, target: TraktLibraryTarget, title: String, year: Int?) async {
        guard active(), !loading, !transferring, !target.ids.json.objectValue.isEmpty else { return }; loadAccount()
        guard let fingerprint = store.fingerprint, let write = store.beginUpdate() else { return }
        defer { store.endUpdate(write) }
        let ticket = operation, identity = account.identity
        let lease: TraktClient.Active = { [weak self] in self?.current(ticket, accountIdentity: identity) ?? false }
        error = nil
        do {
            _ = try await account.response(.library(.change(target, saved)), client: client, active: lease)
            guard lease() else { return }
            var snapshot = store.snapshot
            let existing = snapshot.watchlist.first(where: { target.matches($0) })
            snapshot.watchlist.removeAll { target.matches($0) }
            if saved { snapshot.watchlist.insert(existing ?? .init(type: target.kind, title: title, year: year, ids: target.ids, contextDate: ISO8601DateFormatter().string(from: Date())), at: 0) }
            try await store.commit(snapshot, fingerprint: fingerprint, revision: store.revision)
        } catch is CancellationError { }
        catch { if lease() { self.error = Self.message(error) } }
    }
    static func exportPlan(_ records: [LibraryRecord]) -> TraktWatchlistExportPlan {
        .init(records.map { .object(["id": .string($0.id), "type": $0.raw["type"], "removed": $0.raw["removed"], "temp": $0.raw["temp"]]) })
    }
    func export(_ plan: TraktWatchlistExportPlan) async -> TraktWatchlistExportResult? {
        guard active(), !loading, !transferring else { return nil }; loadAccount()
        guard account.session != nil, let write = store.beginUpdate() else { return nil }
        let ticket = operation, identity = account.identity
        let lease: TraktClient.Active = { [weak self] in self?.current(ticket, accountIdentity: identity) ?? false }
        transferring = true; completed = 0; total = plan.exportable; error = nil
        defer { store.endUpdate(write); if ticket == operation { transferring = false } }
        var synced = 0, firstError: Error?
        for chunk in plan.chunks {
            guard lease() else { return nil }
            do {
                let response = try await account.response(.library(.export(chunk)), client: client, active: lease)
                guard lease() else { return nil }; synced += TraktWatchlistExportResult.confirmed(response)
            } catch is CancellationError { return nil }
            catch { if firstError == nil { firstError = error } }
            guard lease() else { return nil }; completed += chunk["movies"].array.count + chunk["shows"].array.count
        }
        guard lease() else { return nil }
        if synced == 0, let firstError { error = Self.message(firstError); return nil }
        store.invalidate()
        return .init(exportable: plan.exportable, synced: synced, skippedAnime: plan.skippedAnime)
    }
    func fetchImport() async -> [TraktLibraryItem]? {
        guard active(), !loading, !transferring else { return nil }; loadAccount()
        let ticket = operation, identity = account.identity
        let lease: TraktClient.Active = { [weak self] in self?.current(ticket, accountIdentity: identity) ?? false }
        guard lease() else { return nil }; loading = true; error = nil
        defer { if ticket == operation { loading = false } }
        do {
            let value = try await account.response(.library(.watchlist), client: client, active: lease)
            guard lease() else { return nil }; return try TraktLibraryItem.watchlist(value)
        } catch is CancellationError { return nil }
        catch { if lease() { self.error = Self.message(error) }; return nil }
    }
    func importItems(_ items: [TraktLibraryItem], save: @escaping @MainActor (Media) async -> Bool) async -> Int? {
        guard active(), !loading, !transferring, account.session != nil else { return nil }
        let ticket = operation, identity = account.identity
        transferring = true; completed = 0; total = items.count; error = nil
        defer { if ticket == operation { transferring = false } }
        var added = 0
        for item in items {
            guard current(ticket, accountIdentity: identity) else { return nil }
            if let media = item.importMedia, await save(media) { added += 1 }
            guard current(ticket, accountIdentity: identity) else { return nil }; completed += 1
        }
        return added
    }
    static func message(_ error: Error) -> String {
        if let error = error as? TraktAPIError {
            switch error.status {
            case 401: return "Trakt sign-in expired. Reconnect Trakt in settings and try again."
            case 403, 423: return "Trakt rejected the request (account locked or permission denied)."
            case 420: return "Trakt account limit reached. Upgrade to Trakt VIP or trim your watchlist."
            case 429: return "Trakt is rate-limiting. Wait a minute and try again."
            default: return DesktopInterfaceText.value(error.status >= 500 ? "Trakt is having server trouble (HTTP {n}). Try again shortly." : "Trakt rejected the request (HTTP {n}).", variables: ["n": String(error.status)])
            }
        }
        return "Couldn't reach Trakt. Check your connection and try again."
    }
}
