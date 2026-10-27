import Foundation

struct SimklPendingWatch: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let identity: SimklWatchIdentity
    let at: Date
}
struct SimklPendingDocument: Codable, Sendable {
    let fingerprint: String
    var entries: [SimklPendingWatch] = []
    var valid: Bool { fingerprint.count == 64 && entries.count <= 50 && Set(entries.map(\.id)).count == entries.count && entries.allSatisfy { $0.identity.valid } }
}
@MainActor protocol SimklPendingPersistence {
    func read(owner: String) throws -> SimklPendingDocument?
    func write(_ value: SimklPendingDocument?, owner: String) throws
}
@MainActor private struct KeychainSimklPending: SimklPendingPersistence {
    private func key(_ owner: String) -> String { "native-simkl-pending-v1-" + EBookShelf.hash(owner) }
    func read(owner: String) throws -> SimklPendingDocument? { try KeychainStore().read(key(owner), as: SimklPendingDocument.self) }
    func write(_ value: SimklPendingDocument?, owner: String) throws {
        if let value { try KeychainStore().write(value, key: key(owner)) } else { try KeychainStore().remove(key(owner)) }
    }
}
@MainActor final class SimklPendingWatches {
    private static var stores: [String: SimklPendingWatches] = [:]
    static func forOwner(_ owner: String) -> SimklPendingWatches {
        if let store = stores[owner] { return store }; let store = SimklPendingWatches(owner: owner); stores[owner] = store; return store
    }
    let owner: String
    private let persistence: any SimklPendingPersistence
    private(set) var document: SimklPendingDocument?
    private var flushes = Set<String>()
    init(owner: String, persistence: (any SimklPendingPersistence)? = nil) { self.owner = owner; self.persistence = persistence ?? KeychainSimklPending() }
    func bind(_ token: String?) throws {
        guard let token else { try persistence.write(nil, owner: owner); document = nil; return }
        let fingerprint = EBookShelf.hash(token)
        if document?.fingerprint == fingerprint { return }
        let saved = try persistence.read(owner: owner)
        guard saved?.valid ?? true else { throw HarborError(code: "simkl-pending") }
        document = saved?.fingerprint == fingerprint ? saved : SimklPendingDocument(fingerprint: fingerprint)
    }
    func record(_ identity: SimklWatchIdentity, now: Date = Date()) throws -> SimklPendingWatch {
        guard identity.valid, var next = document else { throw HarborError(code: "simkl-pending") }
        let entry = SimklPendingWatch(id: UUID(), identity: identity.sanitized, at: now)
        next.entries.removeAll { $0.identity.key == identity.key }; next.entries.insert(entry, at: 0); next.entries = Array(next.entries.prefix(50))
        try persistence.write(next, owner: owner); document = next; return entry
    }
    func remove(_ entry: SimklPendingWatch, fingerprint: String) throws {
        guard var next = document, next.fingerprint == fingerprint, next.entries.contains(where: { $0.id == entry.id }) else { return }
        next.entries.removeAll { $0.id == entry.id }; try persistence.write(next, owner: owner); document = next
    }
    func beginFlush(_ fingerprint: String) -> Bool { flushes.insert(fingerprint).inserted }
    func endFlush(_ fingerprint: String) { flushes.remove(fingerprint) }
}

enum SimklWatchEndpoint: Sendable {
    case scrobble(SimklScrobbleAction, JSONValue), history(JSONValue)
    var path: String { switch self { case .scrobble(let action, _): "/scrobble/" + action.rawValue; case .history: "/sync/history" } }
    var body: JSONValue { switch self { case .scrobble(_, let body), .history(let body): body } }
}
@MainActor final class SimklWatchReporter {
    let account: SimklAccountStore
    let queue: SimklPendingWatches
    private let client: SimklClient
    private let active: @MainActor () -> Bool
    private let mapping: @Sendable (String) async throws -> JSONValue
    private let resolve: @Sendable (String, Int, Int) async -> TrackerResolutionResult
    init(account: SimklAccountStore, queue: SimklPendingWatches, client: SimklClient = .shared, active: @escaping @MainActor () -> Bool,
         mapping: @escaping @Sendable (String) async throws -> JSONValue = { try await AnimeFranchiseService.shared.response(.mapping($0)) },
         resolve: @escaping @Sendable (String, Int, Int) async -> TrackerResolutionResult = { await TrackerEpisodeResolver.shared.resolve(metaID: $0, season: $1, number: $2) }) {
        self.account = account; self.queue = queue; self.client = client; self.active = active; self.mapping = mapping; self.resolve = resolve
    }
    private func owned(_ token: String) -> Bool { active() && account.session?.accessToken == token }
    func send(_ event: SimklPlaybackPolicy.Event, identity: SimklWatchIdentity) async {
        guard active(), let token = account.session?.accessToken, let body = identity.scrobbleBody(progress: event.progress) else { return }
        let lease: SimklClient.Lease = { [weak self] in await self?.owned(token) ?? false }
        var pending: SimklPendingWatch?
        if event.recordWatched {
            do { try queue.bind(token); pending = try queue.record(identity) } catch { /* Tracking persistence must not interrupt playback. */ }
        }
        let stopped = await post(.scrobble(event.action, body), token: token, lease: lease)
        guard event.recordWatched, owned(token) else { return }
        let recorded = await history(identity, token: token, lease: lease)
        if stopped && recorded, let pending { try? queue.remove(pending, fingerprint: EBookShelf.hash(token)) }
        if recorded { SimklLibraryStore.forOwner(account.owner).invalidate() }
    }
    func recover() async {
        guard active(), let token = account.session?.accessToken else { return }
        do { try queue.bind(token) } catch { return }
        let entries = queue.document?.entries ?? []; guard !entries.isEmpty else { return }
        let lease: SimklClient.Lease = { [weak self] in await self?.owned(token) ?? false }
        let fingerprint = EBookShelf.hash(token)
        guard queue.beginFlush(fingerprint) else { return }; defer { queue.endFlush(fingerprint) }
        for entry in entries {
            guard owned(token), !Task.isCancelled else { return }
            guard let body = entry.identity.scrobbleBody(progress: 100) else { continue }
            let stopped = await post(.scrobble(.stop, body), token: token, lease: lease)
            guard owned(token), !Task.isCancelled else { return }
            let recorded = await history(entry.identity, token: token, lease: lease)
            guard owned(token), !Task.isCancelled else { return }
            if stopped && recorded { try? queue.remove(entry, fingerprint: EBookShelf.hash(token)) }
            if recorded { SimklLibraryStore.forOwner(account.owner).invalidate() }
        }
    }
    private func history(_ identity: SimklWatchIdentity, token: String, lease: @escaping SimklClient.Lease) async -> Bool {
        guard owned(token) else { return false }
        do {
            guard let body = try await identity.historyBody(mapping: mapping), owned(token) else { return false }
            if await post(.history(body), token: token, lease: lease) { return true }
            guard owned(token), !Task.isCancelled, !AnimeService.isAnime(identity.mediaID),
                  let episode = identity.episode, let season = episode.season, let number = episode.episode else { return false }
            let resolution = await resolve(identity.mediaID, season, number)
            guard owned(token), !Task.isCancelled, let resolved = resolution.episode else { return false }
            return await post(.history(resolved.simklHistoryBody()), token: token, lease: lease)
        } catch { return false }
    }
    private func post(_ endpoint: SimklWatchEndpoint, token: String, lease: @escaping SimklClient.Lease) async -> Bool {
        do {
            let response = try await client.response(.watch(endpoint), token: token, current: lease)
            guard owned(token), !response["not_found"].objectValue.values.contains(where: { !$0.array.isEmpty }) else { return false }
            if case .history(let body) = endpoint { return SimklHistoryReceipt.confirms(body: body, response: response) }
            return true
        } catch { return false }
    }
}

enum SimklHistoryReceipt {
    static func confirms(body: JSONValue, response: JSONValue) -> Bool {
        if !body["movies"].array.isEmpty { return (response["added"]["movies"].integer ?? 0) >= body["movies"].array.count }
        let shows = body["shows"].array
        guard !shows.isEmpty else { return false }
        var episodes = Set<String>()
        for (index, show) in shows.enumerated() {
            for season in show["seasons"].array {
                for episode in season["episodes"].array {
                    guard let seasonNumber = season["number"].integer, let number = episode["number"].integer else { return false }
                    episodes.insert("\(index)|\(seasonNumber)|\(number)")
                }
            }
        }
        if !episodes.isEmpty { return (response["added"]["episodes"].integer ?? 0) >= episodes.count }
        return (response["added"]["shows"].integer ?? 0) >= shows.count
    }
}
