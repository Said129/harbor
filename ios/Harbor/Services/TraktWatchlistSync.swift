import Foundation

@MainActor final class TraktWatchlistSync {
    let id = UUID()
    let account: TraktAccountStore
    let store: TraktLibraryStore
    let decisionKey: String
    let fingerprint: String
    private let identity: UUID
    private let client: TraktClient
    private let active: TraktClient.Active
    private let model: TraktLibraryModel
    private var valid = true
    private var previous: Task<Void, Never>?
    var isActive: Bool {
        valid && active() && account.ready && account.identity == identity && account.session != nil
            && account.owner == store.owner && store.fingerprint == fingerprint
    }
    init?(account: TraktAccountStore, store: TraktLibraryStore, client: TraktClient = .shared, active: @escaping TraktClient.Active) {
        guard account.ready, let trackingID = account.session?.trackingID, account.owner == store.owner else { return nil }
        store.bind(trackingID)
        guard let fingerprint = store.fingerprint else { return nil }
        self.account = account; self.store = store; self.client = client; self.active = active
        self.fingerprint = fingerprint; identity = account.identity; decisionKey = EBookShelf.hash(account.owner)
        model = .init(account: account, store: store, client: client, active: active)
    }
    func invalidate() { valid = false; previous?.cancel(); model.cancel() }
    func refresh() async { guard isActive else { return }; await model.refresh() }
    func decision(saved: Bool, at date: Date = Date()) -> JSONValue {
        .object(["fingerprint": .string(fingerprint), "saved": .bool(saved), "at": .number(date.timeIntervalSince1970 * 1_000)])
    }
    @discardableResult func enqueue(_ media: Media, saved: Bool) -> Task<Void, Never>? {
        guard isActive, let target = TraktLibraryTarget(media) else { return nil }
        let before = previous
        let task = Task { [weak self] in
            await before?.value
            guard let self, self.isActive, !Task.isCancelled else { return }
            // Transfers and button taps share one provider write lease. A tap
            // must not disappear just because a manual export is still running.
            while self.store.updating {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard self.isActive else { return }
            }
            guard let write = self.store.beginUpdate() else { return }
            defer { self.store.endUpdate(write) }
            let lease: TraktClient.Active = { [weak self] in self?.isActive == true && !Task.isCancelled }
            do {
                _ = try await self.account.response(.library(.change(target, saved)), client: self.client, active: lease)
                guard lease() else { return }
                var snapshot = self.store.snapshot
                let existing = snapshot.watchlist.first { target.matches($0) }
                snapshot.watchlist.removeAll { target.matches($0) }
                if saved {
                    snapshot.watchlist.insert(existing ?? .init(type: target.kind, title: media.name, year: media.releaseInfo.flatMap { Int($0.prefix(4)) }, ids: target.ids,
                        contextDate: Date().ISO8601Format()), at: 0)
                }
                try await self.store.commit(snapshot, fingerprint: self.fingerprint, revision: self.store.revision)
            } catch is CancellationError { }
            catch { if lease() { Diagnostics.shared.recordFailure(error) } }
        }
        previous = task; return task
    }
    func settled() async { await previous?.value }
}
