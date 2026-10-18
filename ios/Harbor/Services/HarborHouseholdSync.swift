import Foundation
import Observation

/// Full Desktop account:profiles synchronization. The caller supplies the existing
/// authenticated Harbor transport; device credentials never enter this document.
@MainActor @Observable final class HarborHouseholdSync {
    static let key = "account:profiles"
    let account: String
    let profiles: HouseholdProfileStore
    private var generation = 0
    private(set) var busy = false
    private(set) var hydrated = false
    private(set) var error: String?
    @ObservationIgnored var requestSync: (() -> Void)?
    var hasPendingChanges: Bool { hydrated && (profiles.needsUpload || profiles.state.rosterAttempt != nil) }

    init(account: String, profiles: HouseholdProfileStore) { self.account = account; self.profiles = profiles }
    func invalidate() { generation += 1; busy = false; hydrated = false }
    private func check(_ expected: Int) throws {
        try Task.checkCancellation()
        guard expected == generation, profiles.ready, profiles.state.synchronizationAccount == account else { throw HarborError(code: "account-changed") }
    }
    func synchronize(state: JSONValue, send: @MainActor (JSONValue) async throws -> JSONValue) async throws {
        guard !busy else { return }
        busy = true; let expected = generation
        defer { if generation == expected { busy = false } }
        do {
            // Parse before binding or writing anything. A malformed or duplicated
            // server document must not turn fallback profiles into an upload.
            let incoming = try HarborLayoutDocument.state(state, key: Self.key)
            let roster = try incoming.map { try DesktopHouseholdRoster($0.value) }
            try profiles.bindSynchronization(account: account); try check(expected)
            if let incoming, let roster {
                let revision = profiles.state.serverRevision
                guard revision == nil || incoming.rev >= revision! else { throw HarborError(code: "household-roster-revision") }
                if revision == incoming.rev {
                    guard profiles.state.serverValue == roster.raw else { throw HarborError(code: "household-roster-revision") }
                }
                if let attempt = profiles.state.rosterAttempt, incoming.rev > attempt.baseRevision, roster.raw == attempt.value {
                    try profiles.acknowledgeRosterAttempt(attempt, revision: incoming.rev, account: account)
                } else if revision != incoming.rev {
                    try profiles.adopt(roster, revision: incoming.rev, clearingAttempt: true)
                }
            } else {
                // A successful full state GET is authoritative about absence.
                try profiles.noteMissingServerRoster(account: account)
            }
            try check(expected); hydrated = true
            guard let attempt = try profiles.prepareRosterAttempt(account: account) else { error = nil; return }
            let base = HarborLayoutDocument(key: Self.key, rev: attempt.baseRevision, value: attempt.value)
            let response = try await send(base.write(attempt.value))
            try check(expected)
            switch try base.result(response) {
            case .accepted(let revision):
                try profiles.acknowledgeRosterAttempt(attempt, revision: revision, account: account)
            case .rejected(let current):
                let winner = try DesktopHouseholdRoster(current.value)
                guard current.rev > attempt.baseRevision else { throw HarborError(code: "household-sync-rejected") }
                // Desktop adopts the winner's existing profiles, retains local
                // profiles absent from it, and requeues those missing profiles.
                try profiles.adopt(winner, revision: current.rev, clearingAttempt: true)
            }
            error = nil
            if profiles.needsUpload { requestSync?() }
        } catch {
            if generation == expected { self.error = "Profile changes are kept on this device. Synchronization will retry." }
            throw error
        }
    }
}
