import Foundation
import Observation

@MainActor @Observable final class LibraryHistoryModel {
    let library: LibraryModel
    let account: TraktAccountStore
    let store: TraktLibraryStore
    private let client: TraktClient
    private let active: TraktClient.Active
    private let owner: String
    private let personalOwner: String
    private var operation = UUID()
    private var fetchedAt: Date?
    private(set) var loading = false
    private(set) var error: String?
    @ObservationIgnored private var projection: (library: Int, remote: Int, connected: Bool, entries: [LibraryHistoryEntry])?
    var isActive: Bool { active() && library.owner == owner && library.personalOwner == personalOwner }
    var entries: [LibraryHistoryEntry] {
        guard isActive else { return [] }
        let fingerprint = account.session?.trackingID.map { EBookShelf.hash($0.uuidString) }
        let connected = account.owner == personalOwner && store.owner == personalOwner && account.ready && fingerprint != nil && store.fingerprint == fingerprint
        if let projection, projection.library == library.historyRevision, projection.remote == store.revision, projection.connected == connected { return projection.entries }
        let entries = LibraryHistoryEntry.merge(local: library.items, remote: connected ? store.snapshot.history : [])
        projection = (library.historyRevision, store.revision, connected, entries); return entries
    }
    init(library: LibraryModel, account: TraktAccountStore, store: TraktLibraryStore, client: TraktClient = .shared, active: @escaping TraktClient.Active) {
        self.library = library; self.account = account; self.store = store; self.client = client; self.active = active
        owner = library.owner; personalOwner = library.personalOwner
    }
    convenience init(app: AppModel) {
        let owner = app.personalOwner, scope = app.accountOperationScope
        self.init(library: app.library, account: .forOwner(owner), store: .forOwner(owner), active: { [weak app] in
            app?.storageReady == true && app?.personalOwner == owner && app?.accountOperationScope == scope
        })
    }
    func loadAccount() {
        guard isActive, account.owner == personalOwner, account.owner == store.owner else { return }
        do { if !account.ready { try account.load() }; store.bind(account.session?.trackingID) }
        catch { error = "Could not read the account on this device." }
    }
    func cancel() { operation = UUID(); loading = false }
    func refresh(force: Bool = false) async {
        guard isActive, !loading else { return }; loadAccount()
        guard account.owner == personalOwner, account.owner == store.owner, account.session != nil, let fingerprint = store.fingerprint else { return }
        if !force, let fetchedAt, fetchedAt.timeIntervalSinceNow > -20 { return }
        let ticket = operation, identity = account.identity
        let lease: TraktClient.Active = { [weak self] in
            guard let self else { return false }; return self.isActive && self.operation == ticket && self.account.identity == identity && !Task.isCancelled
        }
        loading = true; error = nil; defer { if ticket == operation { loading = false } }
        do {
            do { try await store.restore() } catch is CancellationError { throw CancellationError() } catch { }
            let value = try await account.response(.library(.history), client: client, active: lease)
            let history = try TraktLibraryItem.history(value)
            guard lease(), store.fingerprint == fingerprint else { return }
            // Only this bucket changes; an independently updated watchlist stays.
            var snapshot = store.snapshot; snapshot.history = history
            try await store.commit(snapshot, fingerprint: fingerprint, revision: store.revision)
            guard lease() else { return }; fetchedAt = Date()
        } catch is CancellationError { }
        catch { if lease() { self.error = TraktLibraryModel.message(error) } }
    }
    func remove(_ entry: LibraryHistoryEntry) async {
        guard isActive, entry.localID != nil else { return }
        let saved = await library.removeHistory(entry.record, owner: owner, personalOwner: personalOwner)
        if isActive { error = saved ? nil : library.error }
    }
}
