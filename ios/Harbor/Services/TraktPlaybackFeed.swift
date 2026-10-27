import Foundation
import Observation

@MainActor @Observable final class TraktPlaybackFeed {
    private let client: TraktClient
    private let now: @Sendable () -> Date
    private let sleep: TraktClient.Sleep
    private var snapshot: [LibraryRecord] = [] { didSet { revision &+= 1 } }
    private(set) var revision = 0
    private var fetchedAt: Date?
    private var operation = UUID()
    private var identity: UUID?
    private var account: TraktAccountStore?
    private var scope: String?
    @ObservationIgnored private var active: TraktClient.Active = { false }
    @ObservationIgnored private var enabled: TraktClient.Active = { false }
    @ObservationIgnored private var loading: (id: UUID, task: Task<Void, Never>)?
    var records: [LibraryRecord] { current(operation) ? snapshot : [] }
    func records(for owner: String) -> [LibraryRecord] { account?.owner == owner ? records : [] }
    init(client: TraktClient = .shared, now: @escaping @Sendable () -> Date = { Date() }, sleep: @escaping TraktClient.Sleep = { try await Task.sleep(for: .seconds($0)) }) {
        self.client = client; self.now = now; self.sleep = sleep
    }
    func bind(account: TraktAccountStore, scope: String, active: @escaping TraktClient.Active, enabled: @escaping TraktClient.Active) {
        let changed = self.account !== account || self.scope != scope || identity != account.identity
        self.active = active; self.enabled = enabled
        if changed || !active() || !enabled() { operation = UUID(); loading?.task.cancel(); loading = nil; snapshot = []; fetchedAt = nil }
        self.account = account; self.scope = scope; identity = account.identity
    }
    private func current(_ ticket: UUID) -> Bool {
        ticket == operation && active() && enabled() && account?.ready == true && account?.session != nil && identity == account?.identity
    }
    private func canImport(_ ticket: UUID, record: LibraryRecord, dismissed: @MainActor @Sendable (LibraryRecord) -> Bool) -> Bool {
        current(ticket) && !dismissed(record)
    }
    func refresh(focused: Bool = false, force: Bool = false, resume: ResumeStore? = nil, dismissed: @escaping @MainActor @Sendable (LibraryRecord) -> Bool = { _ in false }) async {
        guard current(operation), !Task.isCancelled else { return }
        if let loading { await loading.task.value; return }
        if !force, let fetchedAt, now().timeIntervalSince(fetchedAt) < (focused ? 30 : 300) { return }
        let ticket = operation, task = Task { await self.load(ticket, resume: resume, dismissed: dismissed) }
        loading = (ticket, task); await task.value
        if loading?.id == ticket { loading = nil }
    }
    private func load(_ ticket: UUID, resume: ResumeStore?, dismissed: @escaping @MainActor @Sendable (LibraryRecord) -> Bool) async {
        guard let account else { return }
        let active: TraktClient.Active = { [weak self] in self?.current(ticket) ?? false }
        for attempt in 0...3 {
            guard current(ticket), !Task.isCancelled else { return }
            do {
                let raw: JSONValue
                do { raw = try await account.response(.playback, client: client, active: active) }
                catch let error as TraktAPIError where error.status == 404 { raw = .array([]) }
                guard current(ticket), !Task.isCancelled else { return }
                let records = TraktPlaybackImport.items(raw); snapshot = records; fetchedAt = now()
                if let resume {
                    for record in records {
                        guard current(ticket), !Task.isCancelled else { return }
                        guard !dismissed(record), let (target, entry) = TraktPlaybackImport.checkpoint(record) else { continue }
                        do {
                            try await resume.importRemote(target, entry: entry, current: { [weak self] in
                                await self?.canImport(ticket, record: record, dismissed: dismissed) ?? false
                            })
                        } catch is CancellationError { return }
                        catch { Diagnostics.shared.recordFailure(error) }
                    }
                }
                return
            } catch is CancellationError { return }
            catch {
                guard current(ticket), !Task.isCancelled else { return }; fetchedAt = nil
                guard attempt < 3 else { return }
                do { try await sleep([1.0, 4.0, 10.0][attempt]) } catch { return }
            }
        }
    }
}
