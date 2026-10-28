import Foundation
import Observation

protocol TraktWatchedPersistence: Sendable {
    func read(owner: String, fingerprint: String) async throws -> TraktWatchedState?
    func write(_ value: TraktWatchedState, owner: String, fingerprint: String) async throws
}
actor TraktWatchedDisk: TraktWatchedPersistence {
    static let shared = TraktWatchedDisk()
    private struct Document: Codable { let version: Int; let fingerprint: String; let state: TraktWatchedState }
    private let root: URL
    init(root: URL? = nil) { self.root = root ?? URL.applicationSupportDirectory.appendingPathComponent("HarborTraktWatched", isDirectory: true) }
    private func url(_ owner: String) -> URL { root.appendingPathComponent(EBookShelf.hash(owner) + ".json") }
    func read(owner: String, fingerprint: String) throws -> TraktWatchedState? {
        let url = url(owner); guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_024 * 1_024 else { throw HarborError(code: "trakt-watched-cache") }
        let value = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard value.version == 1, value.state.keys.count <= 20_000 else { throw HarborError(code: "trakt-watched-cache") }
        return value.fingerprint == fingerprint ? value.state : nil
    }
    func write(_ value: TraktWatchedState, owner: String, fingerprint: String) throws {
        guard value.keys.count <= 20_000 else { throw HarborError(code: "trakt-watched-cache") }
        let data = try JSONEncoder().encode(Document(version: 1, fingerprint: fingerprint, state: value))
        guard data.count <= 1_024 * 1_024 else { throw HarborError(code: "trakt-watched-cache") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: url(owner), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var url = root, values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
    }
}

@MainActor @Observable final class TraktWatchedFeed {
    private let client: TraktClient
    private let disk: any TraktWatchedPersistence
    private let now: @Sendable () -> Date
    private var account: TraktAccountStore?
    private var accountIdentity: UUID?
    private var scope: String?
    private var operation = UUID()
    private var restored = false
    private var fetchedAt: Date?
    private var snapshot: TraktWatchedState?
    private(set) var revision = 0
    @ObservationIgnored private var active: TraktClient.Active = { false }
    @ObservationIgnored private var loading: (id: UUID, task: Task<Void, Never>)?
    @ObservationIgnored private var writing: Task<Void, Never>?
    init(client: TraktClient = .shared, disk: any TraktWatchedPersistence = TraktWatchedDisk.shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.disk = disk; self.now = now
    }
    func bind(account: TraktAccountStore, scope: String, active: @escaping TraktClient.Active) {
        let changed = self.account !== account || self.scope != scope || accountIdentity != account.identity
        self.active = active
        if changed { clear() }; self.account = account; self.scope = scope; accountIdentity = account.identity
    }
    func clear() {
        operation = UUID(); loading?.task.cancel(); loading = nil; writing?.cancel(); writing = nil; snapshot = nil; restored = false; fetchedAt = nil; revision &+= 1
    }
    private func current(_ ticket: UUID) -> Bool {
        ticket == operation && active() && account?.ready == true && account?.session != nil && accountIdentity == account?.identity && !Task.isCancelled
    }
    private var fingerprint: String? { account?.session?.trackingID.map { EBookShelf.hash($0.uuidString) } }
    func state(for owner: String) -> TraktWatchedState? {
        guard account?.owner == owner, current(operation), let snapshot, snapshot.fresh(now()) else { return nil }; return snapshot
    }
    func refresh(force: Bool = false) async {
        guard current(operation) else { return }
        if let loading { await loading.task.value; return }
        if !force, let fetchedAt, now().timeIntervalSince(fetchedAt) < 30 { return }
        let ticket = operation, task = Task { await self.load(ticket) }; loading = (ticket, task)
        await task.value; if loading?.id == ticket { loading = nil }
    }
    private func load(_ ticket: UUID) async {
        guard let account, let fingerprint else { return }
        let lease: TraktClient.Active = { [weak self] in self?.current(ticket) ?? false }
        if !restored {
            do {
                let saved = try await disk.read(owner: account.owner, fingerprint: fingerprint)
                guard lease() else { return }; snapshot = saved; restored = true; revision &+= 1
            } catch { if !lease() { return }; restored = true }
        }
        do {
            let revision = revision
            let value = try await account.response(.library(.watchedKeys), client: client, active: lease)
            let state = try TraktWatchedState(at: now(), history: value)
            guard lease(), self.revision == revision else { return }; snapshot = state; fetchedAt = now(); self.revision &+= 1
            try await disk.write(state, owner: account.owner, fingerprint: fingerprint)
        } catch is CancellationError { }
        catch { if lease() { Diagnostics.shared.recordFailure(error) } }
    }
    @discardableResult func enqueueMark(_ media: Media, episodes: [Episode], owner: String, wholeSeries: Bool = false) -> Task<Void, Never>? {
        guard account?.owner == owner, current(operation), let account, let fingerprint else { return nil }
        let anime = ["kitsu:", "mal:", "anilist:", "anidb:"].contains { media.id.hasPrefix($0) }
        guard !(wholeSeries && anime) else { return nil }
        let ticket = operation, before = writing
        let identities: [TraktWatchIdentity] = media.episodic ? episodes.map { .init(mediaID: media.id, episode: $0) } : [.init(mediaID: media.id)]
        let task = Task { [weak self] in
            await before?.value
            guard let self, self.current(ticket) else { return }
            let reporter = TraktWatchReporter(account: account, queue: .forOwner(owner), client: self.client, active: { [weak self] in self?.current(ticket) ?? false })
            for identity in identities {
                guard self.current(ticket) else { return }
                guard let confirmed = await reporter.mark(identity), self.current(ticket) else { continue }
                var state = self.snapshot ?? TraktWatchedState(at: self.now(), keys: [])
                state.record(confirmed); self.snapshot = state; self.fetchedAt = nil; self.revision &+= 1
                do { try await self.disk.write(state, owner: owner, fingerprint: fingerprint) }
                catch { if self.current(ticket) { Diagnostics.shared.recordFailure(error) } }
            }
        }
        writing = task; return task
    }
    func settled() async { await writing?.value }
}
