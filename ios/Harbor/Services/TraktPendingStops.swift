import Foundation

struct TraktPendingStop: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let identity: TraktWatchIdentity
    let progress: Double
    let at: Date
}
struct TraktPendingDocument: Codable, Sendable {
    let fingerprint: String
    var entries: [TraktPendingStop] = []
    var valid: Bool {
        fingerprint.count == 64 && entries.count <= 50 && Set(entries.map(\.id)).count == entries.count
            && entries.allSatisfy { $0.identity.valid && $0.progress.isFinite && (70...100).contains($0.progress) && $0.at.timeIntervalSince1970.isFinite }
    }
}
@MainActor protocol TraktPendingPersistence {
    func read(owner: String) throws -> TraktPendingDocument?
    func write(_ value: TraktPendingDocument?, owner: String) throws
}
@MainActor private struct KeychainTraktPending: TraktPendingPersistence {
    private func key(_ owner: String) -> String { "native-trakt-pending-v1-" + EBookShelf.hash(owner) }
    func read(owner: String) throws -> TraktPendingDocument? { try KeychainStore().read(key(owner), as: TraktPendingDocument.self) }
    func write(_ value: TraktPendingDocument?, owner: String) throws {
        if let value { try KeychainStore().write(value, key: key(owner)) } else { try KeychainStore().remove(key(owner)) }
    }
}
@MainActor final class TraktPendingStops {
    private static var stores: [String: TraktPendingStops] = [:]
    static func forOwner(_ owner: String) -> TraktPendingStops {
        if let store = stores[owner] { return store }
        let store = TraktPendingStops(owner: owner); stores[owner] = store; return store
    }
    let owner: String
    private let persistence: any TraktPendingPersistence
    private(set) var document: TraktPendingDocument?
    private var flushing = Set<String>()
    init(owner: String, persistence: (any TraktPendingPersistence)? = nil) { self.owner = owner; self.persistence = persistence ?? KeychainTraktPending() }
    func bind(_ trackingID: UUID?) throws {
        guard let trackingID else { try persistence.write(nil, owner: owner); document = nil; return }
        let fingerprint = EBookShelf.hash(trackingID.uuidString)
        if document?.fingerprint == fingerprint { return }
        let previous = try persistence.read(owner: owner)
        guard previous?.valid ?? true else { throw HarborError(code: "trakt-pending") }
        document = previous?.fingerprint == fingerprint ? previous : TraktPendingDocument(fingerprint: fingerprint)
    }
    func record(_ identity: TraktWatchIdentity, progress: Double, now: Date = Date()) throws -> TraktPendingStop? {
        guard progress.isFinite, progress >= 70 else { return nil }
        guard identity.valid, var next = document else { throw HarborError(code: "trakt-pending") }
        let entry = TraktPendingStop(id: UUID(), identity: identity.sanitized, progress: min(100, progress), at: now)
        next.entries.removeAll { $0.identity.key == identity.key }; next.entries.insert(entry, at: 0); next.entries = Array(next.entries.prefix(50))
        try persistence.write(next, owner: owner); document = next; return entry
    }
    func remove(_ entry: TraktPendingStop, fingerprint: String) throws {
        guard var next = document, next.fingerprint == fingerprint, next.entries.contains(where: { $0.id == entry.id }) else { return }
        next.entries.removeAll { $0.id == entry.id }; try persistence.write(next, owner: owner); document = next
    }
    func beginFlush(_ fingerprint: String) -> Bool { flushing.insert(fingerprint).inserted }
    func endFlush(_ fingerprint: String) { flushing.remove(fingerprint) }
}

@MainActor final class TraktWatchReporter {
    enum Outcome: String, Sendable { case recorded, alreadyRecorded = "already-recorded", failed }
    let account: TraktAccountStore
    let queue: TraktPendingStops
    private let client: TraktClient
    private let active: TraktClient.Active
    private let accountIdentity: UUID
    private let resolve: @Sendable (String, Int, Int) async -> TrackerResolutionResult
    private let specialMovie: @Sendable (String, Int, Int) async -> TrackerShowIDs?
    init(account: TraktAccountStore, queue: TraktPendingStops, client: TraktClient = .shared, active: @escaping TraktClient.Active,
         resolve: @escaping @Sendable (String, Int, Int) async -> TrackerResolutionResult = { await TrackerEpisodeResolver.shared.resolve(metaID: $0, season: $1, number: $2) },
         specialMovie: @escaping @Sendable (String, Int, Int) async -> TrackerShowIDs? = { await TrackerEpisodeResolver.shared.specialMovie(metaID: $0, season: $1, number: $2) }) {
        self.account = account; self.queue = queue; self.client = client; self.active = active; self.resolve = resolve; self.specialMovie = specialMovie
        accountIdentity = account.identity
    }
    private func owned(_ ticket: UUID) -> Bool { active() && account.owner == queue.owner && account.ready && account.session != nil && account.identity == accountIdentity && account.identity == ticket && !Task.isCancelled }
    func send(_ event: TraktPlaybackPolicy.Event, identity: TraktWatchIdentity) async {
        guard event.progress.isFinite, owned(accountIdentity), let trackingID = account.session?.trackingID, let target = TraktWatchTarget.resolve(identity), target.kind != .show else { return }
        let ticket = accountIdentity, fingerprint = EBookShelf.hash(trackingID.uuidString)
        if event.action != .stop { await playback(event.action, target: target, identity: identity, progress: event.progress, ticket: ticket); return }
        var pending: TraktPendingStop?
        if event.progress >= 70 {
            do { try queue.bind(trackingID); pending = try queue.record(identity, progress: event.progress) }
            catch { Diagnostics.shared.recordFailure(error) }
        }
        let outcome = await stop(target: target, identity: identity, progress: event.progress, ticket: ticket)
        guard owned(ticket), outcome != .failed, let pending else { return }
        do { try queue.remove(pending, fingerprint: fingerprint) } catch { Diagnostics.shared.recordFailure(error) }
    }
    func recover() async {
        guard owned(accountIdentity), let trackingID = account.session?.trackingID else { return }
        do { try queue.bind(trackingID) } catch { Diagnostics.shared.recordFailure(error); return }
        let ticket = accountIdentity, fingerprint = EBookShelf.hash(trackingID.uuidString)
        guard queue.beginFlush(fingerprint) else { return }; defer { queue.endFlush(fingerprint) }
        for pending in queue.document?.entries ?? [] {
            guard owned(ticket) else { return }
            let outcome: Outcome
            if let target = TraktWatchTarget.resolve(pending.identity), target.kind != .show {
                outcome = await stop(target: target, identity: pending.identity, progress: 100, ticket: ticket)
            } else { outcome = .recorded }
            guard owned(ticket) else { return }
            if outcome != .failed { do { try queue.remove(pending, fingerprint: fingerprint) } catch { Diagnostics.shared.recordFailure(error) } }
        }
    }
    private func scrobble(_ action: TraktScrobbleAction, target: TraktWatchTarget, progress: Double, ticket: UUID) async -> Outcome {
        guard target.kind != .show, let body = target.scrobbleBody(progress) else { return .failed }
        for attempt in 0...1 {
            guard owned(ticket) else { return .failed }
            do {
                _ = try await account.response(.watch(.scrobble(action, body)), client: client, active: { [weak self] in self?.owned(ticket) ?? false })
                return owned(ticket) ? .recorded : .failed
            } catch let error as TraktAPIError where action == .stop && error.status == 409 { return owned(ticket) ? .alreadyRecorded : .failed }
            catch {
                guard action == .stop, attempt == 0, owned(ticket) else { return .failed }
                do { try await client.pause(0.8) } catch { return .failed }
            }
        }
        return .failed
    }
    private func history(_ target: TraktWatchTarget, ticket: UUID) async -> Bool {
        guard owned(ticket), let body = target.historyBody else { return false }
        do {
            let value = try await account.response(.watch(.history(body)), client: client, active: { [weak self] in self?.owned(ticket) ?? false })
            return owned(ticket) && TraktHistoryReceipt.confirms(value)
        } catch { return false }
    }
    func mark(_ identity: TraktWatchIdentity) async -> TraktWatchTarget? {
        let ticket = accountIdentity
        guard owned(ticket), let target = TraktWatchTarget.resolve(identity), target.kind != .show else { return nil }
        if await history(target, ticket: ticket) { return target }
        guard owned(ticket), target.resolvable, let season = target.season, let number = target.number else { return nil }
        let result = await resolve(identity.mediaID, season, number)
        guard owned(ticket) else { return nil }
        let resolved: TraktWatchTarget
        if let episode = result.episode { resolved = .init(episode) }
        else if result.reason == "not-found", season == 0, let ids = await specialMovie(identity.mediaID, season, number), owned(ticket) { resolved = .init(kind: .movie, ids: ids) }
        else { return nil }
        return await history(resolved, ticket: ticket) ? resolved : nil
    }
    private func playback(_ action: TraktScrobbleAction, target: TraktWatchTarget, identity: TraktWatchIdentity, progress: Double, ticket: UUID) async {
        if await scrobble(action, target: target, progress: progress, ticket: ticket) == .recorded { return }
        guard owned(ticket), target.resolvable, let season = target.season, let number = target.number else { return }
        let resolution = await resolve(identity.mediaID, season, number)
        guard owned(ticket), let episode = resolution.episode else { return }
        _ = await scrobble(action, target: .init(episode), progress: progress, ticket: ticket)
    }
    private func stop(target: TraktWatchTarget, identity: TraktWatchIdentity, progress: Double, ticket: UUID) async -> Outcome {
        let direct = await scrobble(.stop, target: target, progress: progress, ticket: ticket)
        guard owned(ticket) else { return .failed }
        if direct != .failed { return direct }
        if progress >= 70, await history(target, ticket: ticket) { return .recorded }
        guard owned(ticket), target.resolvable, let season = target.season, let number = target.number else { return .failed }
        let result = await resolve(identity.mediaID, season, number)
        guard owned(ticket) else { return .failed }
        let resolved: TraktWatchTarget
        if let episode = result.episode { resolved = .init(episode) }
        else if result.reason == "not-found", season == 0, let ids = await specialMovie(identity.mediaID, season, number), owned(ticket) { resolved = .init(kind: .movie, ids: ids) }
        else { return .failed }
        let confirmed = await scrobble(.stop, target: resolved, progress: progress, ticket: ticket)
        guard owned(ticket) else { return .failed }
        if confirmed != .failed { return confirmed }
        guard progress >= 70 else { return .failed }
        return await history(resolved, ticket: ticket) ? .recorded : .failed
    }
}
