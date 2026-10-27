import Foundation
import Observation

/// Profile-bound counterpart of Desktop's external-cw feed. Failed refreshes
/// retain the last cards; a disabled source or replaced account exposes none.
@MainActor @Observable final class SimklPlaybackFeed {
    private let client: SimklClient
    private let now: @Sendable () -> Date
    private let sleep: SimklClient.Sleep
    private var snapshot: [LibraryRecord] = [] { didSet { revision &+= 1 } }
    private(set) var revision = 0
    private var fetchedAt: Date?
    private var operation = UUID()
    private var account: SimklAccountStore?
    private var token: String?
    private var scope: String?
    @ObservationIgnored private var active: @MainActor () -> Bool = { false }
    @ObservationIgnored private var enabled: @MainActor () -> Bool = { false }
    @ObservationIgnored private var loading: (id: UUID, task: Task<Void, Never>)?
    var records: [LibraryRecord] { isCurrent(operation) ? snapshot : [] }
    func records(for owner: String) -> [LibraryRecord] { account?.owner == owner ? records : [] }
    init(client: SimklClient = .shared, now: @escaping @Sendable () -> Date = { Date() }, sleep: @escaping SimklClient.Sleep = { try await Task.sleep(for: .seconds($0)) }) {
        self.client = client; self.now = now; self.sleep = sleep
    }
    func bind(account: SimklAccountStore, scope: String, active: @escaping @MainActor () -> Bool, enabled: @escaping @MainActor () -> Bool) {
        self.active = active; self.enabled = enabled
        let changed = self.scope != scope || self.account !== account || token != account.session?.accessToken
        if changed || !active() || !enabled() {
            operation = UUID(); loading?.task.cancel(); loading = nil; snapshot = []; fetchedAt = nil
        }
        self.account = account; self.scope = scope; token = account.session?.accessToken
    }
    private func isCurrent(_ ticket: UUID) -> Bool {
        ticket == operation && active() && enabled() && account?.ready == true && token != nil && token == account?.session?.accessToken
    }
    func refresh(focused: Bool = false, force: Bool = false, resume: ResumeStore? = nil, dismissed: @escaping @MainActor (LibraryRecord) -> Bool = { _ in false }) async {
        guard isCurrent(operation), !Task.isCancelled else { return }
        if let loading { await loading.task.value; return }
        if !force, let fetchedAt, now().timeIntervalSince(fetchedAt) < (focused ? 30 : 300) { return }
        let ticket = operation
        let task = Task { await self.load(ticket: ticket, resume: resume, dismissed: dismissed) }
        loading = (ticket, task); await task.value
        if loading?.id == ticket { loading = nil }
    }
    private func load(ticket: UUID, resume: ResumeStore?, dismissed: @escaping @MainActor (LibraryRecord) -> Bool) async {
        guard let token else { return }
        let lease: SimklClient.Lease = { [weak self] in await self?.isCurrent(ticket) ?? false }
        for attempt in 0...3 {
            guard isCurrent(ticket), !Task.isCancelled else { return }
            do {
                let raw: JSONValue
                do { raw = try await client.response(.playback, token: token, current: lease) }
                catch let error as SimklAPIError where error.status == 404 { raw = .array([]) }
                guard isCurrent(ticket), !Task.isCancelled else { return }
                let values = SimklPlaybackImport.items(raw)
                snapshot = values; fetchedAt = now()
                if let resume {
                    for record in values {
                        guard isCurrent(ticket), !Task.isCancelled else { return }
                        guard !dismissed(record), let (target, entry) = SimklPlaybackImport.checkpoint(record) else { continue }
                        do { try await resume.importRemote(target, entry: entry, current: lease) }
                        catch is CancellationError { return }
                        catch { Diagnostics.shared.recordFailure(error) }
                    }
                }
                return
            } catch is CancellationError { return }
            catch {
                guard isCurrent(ticket), !Task.isCancelled else { return }
                fetchedAt = nil
                guard attempt < 3 else { return }
                do { try await sleep([1.0, 4.0, 10.0][attempt]) } catch { return }
            }
        }
    }
}

struct ContinueWatchingSources: Codable, Equatable, Sendable {
    var library = true
    var trakt = false
    var simkl = false
    var local = true
    static let defaultValue = "{\"library\":true,\"trakt\":false,\"simkl\":false,\"local\":true}"
    init() { }
    init(rawValue: String) { self = (try? JSONDecoder().decode(Self.self, from: Data(rawValue.utf8))) ?? Self() }
    var rawValue: String { (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? Self.defaultValue }
    private enum CodingKeys: String, CodingKey { case library, trakt, simkl, local }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        library = try values.decodeIfPresent(Bool.self, forKey: .library) ?? true
        trakt = try values.decodeIfPresent(Bool.self, forKey: .trakt) ?? false
        simkl = try values.decodeIfPresent(Bool.self, forKey: .simkl) ?? false
        local = try values.decodeIfPresent(Bool.self, forKey: .local) ?? true
    }
}
