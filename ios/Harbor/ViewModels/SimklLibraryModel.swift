import Foundation
import Observation

@MainActor @Observable final class SimklLibraryModel {
    let account: SimklAccountStore
    let store: SimklLibraryStore
    private let client: SimklClient
    private let active: @MainActor () -> Bool
    private var operation = UUID()
    private(set) var loading = false
    private(set) var error: String?
    private(set) var relations: [String: Set<String>] = [:]
    private var relationsRevision = 0
    @ObservationIgnored private var collectionCache: (revision: Int, relations: Int, locale: String, index: SimklCollectionIndex)?
    private var resolvedRelations = Set<String>()
    private var loadingRelations = false
    var isActive: Bool { active() }
    var collection: SimklCollectionIndex {
        let revision = store.revision, locale = Locale.current.identifier
        if let saved = collectionCache, saved.revision == revision, saved.relations == relationsRevision, saved.locale == locale { return saved.index }
        let index = SimklCollectionIndex(store.snapshot, relations: relations)
        collectionCache = (revision, relationsRevision, locale, index); return index
    }
    init(account: SimklAccountStore, store: SimklLibraryStore, client: SimklClient = .shared, active: @escaping @MainActor () -> Bool) {
        self.account = account; self.store = store; self.client = client; self.active = active
    }
    convenience init(app: AppModel) {
        let owner = app.personalOwner, scope = app.accountOperationScope
        self.init(account: .forOwner(owner), store: .forOwner(owner), active: { [weak app] in
            app?.personalOwner == owner && app?.accountOperationScope == scope && app?.interfaceProfileScope != "unbound"
        })
    }
    func loadAccount() {
        guard active() else { return }
        do {
            if !account.ready { try account.load() }
            let previous = store.fingerprint; store.bind(account.session?.accessToken)
            if previous != store.fingerprint { relations.removeAll(); resolvedRelations.removeAll(); relationsRevision &+= 1 }
        }
        catch { self.error = "Could not read the account on this device." }
    }
    func cancel() { operation = UUID(); loading = false }
    private func current(_ ticket: UUID, token: String) -> Bool { ticket == operation && active() && account.session?.accessToken == token && !Task.isCancelled }
    func refresh(force: Bool = false, maximumAge: TimeInterval = 20) async {
        guard !loading, active() else { return }
        loadAccount()
        guard let token = account.session?.accessToken else { return }
        if !force, let date = store.refreshedAt, date.timeIntervalSinceNow > -max(0, maximumAge.isFinite ? maximumAge : 20) { return }
        let ticket = operation, fingerprint = EBookShelf.hash(token)
        let lease: SimklClient.Lease = { [weak self] in await self?.current(ticket, token: token) ?? false }
        loading = true; error = nil
        defer { if ticket == operation { loading = false } }
        do {
            do { try await store.restore() } catch is CancellationError { throw CancellationError() }
            catch { /* A damaged disposable cache is replaced only by a complete provider response. */ }
            let revision = store.revision
            var snapshot = store.snapshot
            let activities = try await client.response(.library(.activities), token: token, current: lease)
            if snapshot.lastSync == nil || force {
                snapshot = .init()
                for kind in SimklMediaKind.allCases {
                    let response = try await client.response(.library(.all(kind)), token: token, current: lease)
                    snapshot.merge(response, kind: kind)
                }
                snapshot.mergeRatings(try await client.response(.library(.ratings), token: token, current: lease))
            } else {
                if activities["all"].string != snapshot.lastSync {
                    let delta = try await client.response(.library(.delta(snapshot.lastSync!)), token: token, current: lease)
                    for kind in SimklMediaKind.allCases { snapshot.merge(delta, kind: kind) }
                    if SimklLibrarySnapshot.removalsChanged(activities, since: snapshot.lastSync) {
                        let response = try await client.response(.library(.identities), token: token, current: lease)
                        // An HTTP error must never be interpreted as an empty list.
                        guard case .object = response else { throw HarborError(code: "simkl-response") }
                        var valid = Set<String>()
                        for kind in SimklMediaKind.allCases {
                            for raw in response[kind.bucket].array {
                                let node = kind == .anime ? [raw["anime"], raw["show"], raw["movie"]].first(where: { !$0.objectValue.isEmpty }) ?? .null : raw[kind == .movie ? "movie" : "show"]
                                if let id = SimklIdentifiers(node["ids"]).values["simkl"]?.textValue { valid.insert(kind.rawValue + ":" + id) }
                            }
                        }
                        snapshot.items = snapshot.items.filter { valid.contains($0.key) }
                    }
                    snapshot.mergeRatings(try await client.response(.library(.ratings), token: token, current: lease))
                }
            }
            snapshot.activities = activities
            snapshot.lastSync = snapshot.activities["all"].string ?? ISO8601DateFormatter().string(from: Date())
            guard current(ticket, token: token) else { throw CancellationError() }
            try await store.commit(snapshot, fingerprint: fingerprint, expectedRevision: revision)
        } catch is CancellationError { }
        catch { if current(ticket, token: token) { self.error = Self.message(error) } }
    }
    func setStatus(_ status: SimklListStatus?, target: SimklTarget, media: Media) async {
        await mutate(status.map { .status(target, $0) } ?? .remove(target)) { response, snapshot in
            let previous = snapshot.item(for: target)
            if let previous, status == nil { snapshot.items[previous.id] = nil; return }
            guard let status else { return }
            let echoed = response["added"][target.listBucket].array.first?["to"].string.flatMap(SimklListStatus.init(rawValue:))
            var item = previous ?? SimklListItem(kind: target.kind, ids: target.ids, title: media.name,
                year: media.releaseInfo.flatMap { Int(String($0.prefix(4))) }, status: status, watchedEpisodes: [], poster: media.poster)
            item.status = echoed ?? status; if item.addedAt == nil { item.addedAt = ISO8601DateFormatter().string(from: Date()) }
            snapshot.items[item.id] = item
        }
    }
    func setRating(_ rating: Int?, target: SimklTarget) async {
        await mutate(.rating(target, rating)) { _, snapshot in
            snapshot.setRating(rating, target: target)
        }
    }
    func loadRelations() async {
        guard active(), !loadingRelations, let token = account.session?.accessToken else { return }
        let ticket = operation
        let lease: SimklClient.Lease = { [weak self] in await self?.current(ticket, token: token) ?? false }
        loadingRelations = true; defer { loadingRelations = false }
        var additions: [String: Set<String>] = [:]
        defer {
            if current(ticket, token: token), !additions.isEmpty {
                relations.merge(additions) { _, new in new }; resolvedRelations.formUnion(additions.keys); relationsRevision &+= 1
            }
        }
        let groups = SimklCollection.franchises(Array(store.snapshot.items.values).filter(SimklCollection.isAnime))
            .sorted { ($0.map(\.title).min() ?? "") < ($1.map(\.title).min() ?? "") }
        guard groups.count > 1 else { return }
        for group in groups.prefix(50) {
            guard current(ticket, token: token), let item = group.first else { return }
            guard !resolvedRelations.contains(item.id), let id = item.ids.values["simkl"]?.integer else { continue }
            do {
                let value = try await client.response(.detail(item.kind == .movie ? .movie : .anime, id), current: lease)
                guard current(ticket, token: token) else { return }
                var related = Set<String>()
                for relation in value["relations"].array where relation["is_direct"] != .bool(false) {
                    if let id = relation["ids"]["simkl_id"].integer {
                        for target in store.snapshot.items.values where SimklCollection.isAnime(target) && target.ids.values["simkl"]?.integer == id { related.insert(target.id) }
                    }
                }
                additions[item.id] = related
            } catch is CancellationError { return }
            catch let error as SimklAPIError where error.retryAt != nil { return }
            catch { /* Retain title grouping; a later appearance can retry missing public relations. */ }
        }
    }
    private func mutate(_ endpoint: SimklLibraryEndpoint, update: (JSONValue, inout SimklLibrarySnapshot) -> Void) async {
        guard active(), !store.updating, let token = account.session?.accessToken else { return }
        let ticket = operation, fingerprint = EBookShelf.hash(token)
        let lease: SimklClient.Lease = { [weak self] in await self?.current(ticket, token: token) ?? false }
        store.updating = true; error = nil
        defer { store.updating = false }
        do {
            let response = try await client.response(.library(endpoint), token: token, current: lease)
            guard current(ticket, token: token) else { throw CancellationError() }
            if response["not_found"].objectValue.values.contains(where: { !$0.array.isEmpty }) { throw HarborError(code: "simkl-target") }
            let revision = store.revision
            var snapshot = store.snapshot; update(response, &snapshot)
            try await store.commit(snapshot, fingerprint: fingerprint, expectedRevision: revision)
        } catch is CancellationError { }
        catch { if current(ticket, token: token) { self.error = Self.message(error) } }
    }
    static func message(_ error: Error) -> String {
        if let error = error as? SimklAPIError {
            if error.status == 401 { return "Simkl sign-in expired, reconnect it" }
            if error.retryAt != nil { return "Simkl is temporarily limiting requests. Try again later." }
        }
        return "Couldn't reach Simkl"
    }
}
