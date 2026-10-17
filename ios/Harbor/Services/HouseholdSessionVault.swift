import Foundation
import Observation

struct HouseholdSourceAccount: Codable, Equatable, Sendable {
    var account: SavedAccount?
    var guestAddons: [Addon]?
    // Compare the complete protocol payload, including fields unknown to native UI.
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let left = try? JSONValue.encoded(lhs), let right = try? JSONValue.encoded(rhs) else { return false }
        return left == right
    }
}
struct HouseholdAccountRoute: Codable, Equatable, Sendable {
    let household: String
    let sourceID: String
    var key: String { HouseholdProfileScope.hash([household, sourceID]) }
}
struct HouseholdAccountRecord: Codable, Equatable, Sendable {
    let route: HouseholdAccountRoute
    let version: UUID
    let configuration: HouseholdSourceAccount
}
struct HouseholdSessionState: Codable, Equatable, Sendable {
    var version = 1
    var sources: [String: HouseholdAccountRecord] = [:]
    var migratedOwners: [String: HouseholdAccountRoute] = [:]
    func validated() throws -> Self {
        guard version == 1, sources.allSatisfy({ key, value in
            key == value.route.key && !value.route.household.isEmpty && value.route.household.utf8.count <= 256
                && !value.route.sourceID.isEmpty && value.route.sourceID.utf8.count <= 256
                && (value.configuration.account.map { $0.version == 1 && !$0.session.authKey.isEmpty && !$0.session.user.id.isEmpty } ?? true)
        }), migratedOwners.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }),
              try JSONEncoder().encode(self).count <= 16 * 1_024 * 1_024 else { throw HarborError(code: "household-sessions") }
        return self
    }
}
@MainActor protocol HouseholdSessionPersistence {
    func readHouseholdSessions() throws -> HouseholdSessionState?
    func writeHouseholdSessions(_ value: HouseholdSessionState) throws
}
@MainActor private struct KeychainHouseholdSessions: HouseholdSessionPersistence {
    private let key = "native-household-sessions-v1"
    func readHouseholdSessions() throws -> HouseholdSessionState? { try KeychainStore().read(key, as: HouseholdSessionState.self) }
    func writeHouseholdSessions(_ value: HouseholdSessionState) throws { try KeychainStore().write(value, key: key) }
}

/// The legacy claim and copied session are committed in one record. Old keys remain
/// readable by earlier IPAs but can never be auto-imported into another household.
@MainActor @Observable final class HouseholdSessionVault {
    struct Lease: Sendable {
        fileprivate let route: HouseholdAccountRoute
        fileprivate let generation: Int
        fileprivate let version: UUID?
        let configuration: HouseholdSourceAccount?
    }
    private let persistence: any HouseholdSessionPersistence
    private var state = HouseholdSessionState()
    private var route: HouseholdAccountRoute?
    private var generation = 0
    private(set) var ready = false
    private(set) var error: String?
    var current: HouseholdSourceAccount? { ready ? route.flatMap { state.sources[$0.key]?.configuration } : nil }
    init(persistence: (any HouseholdSessionPersistence)? = nil) {
        self.persistence = persistence ?? KeychainHouseholdSessions(); reload()
    }
    func reload() {
        generation += 1; ready = false
        do { state = try (persistence.readHouseholdSessions() ?? HouseholdSessionState()).validated(); ready = true; error = nil }
        catch { self.error = "Could not load profile accounts. Saved accounts are kept." }
    }
    @discardableResult func bind(profile: DeviceHouseholdProfile, profiles: [DeviceHouseholdProfile], scope: HouseholdProfileScope) throws -> Lease {
        guard ready, profiles.contains(where: { $0.id == profile.id && $0 == profile }) else { throw HarborError(code: "profile-account-scope") }
        let routing = HouseholdProfileRouting(profile: profile, profiles: profiles, scope: scope, cwPerProfile: false)
        let target = HouseholdAccountRoute(household: scope.key, sourceID: routing.stremioSourceID)
        if target != route { generation += 1; route = target }
        let record = state.sources[target.key]
        return Lease(route: target, generation: generation, version: record?.version, configuration: record?.configuration)
    }
    func unbind() { generation += 1; route = nil }
    private func validate(_ lease: Lease) throws {
        guard ready, lease.generation == generation, route == lease.route,
              state.sources[lease.route.key]?.version == lease.version else { throw HarborError(code: "profile-account-changed") }
    }
    /// Refreshing addons or a source session updates profiles that deliberately share it.
    func save(_ configuration: HouseholdSourceAccount, using lease: Lease) throws {
        try validate(lease)
        var next = state
        next.sources[lease.route.key] = HouseholdAccountRecord(route: lease.route, version: UUID(), configuration: configuration)
        try commit(next)
    }
    /// Desktop sign-in/sign-out detaches the active profile from a shared Stremio
    /// source. Persist its own configuration BEFORE committing that routing change.
    /// Until the caller commits shareStremioWith=nil and binds again, the shared
    /// account stays active. A failed roster write cannot sign other profiles out.
    func prepareOwnAccount(_ configuration: HouseholdSourceAccount, profile: DeviceHouseholdProfile,
                           profiles: [DeviceHouseholdProfile], scope: HouseholdProfileScope, using lease: Lease) throws {
        try validate(lease)
        guard profiles.contains(where: { $0 == profile }), lease.route.household == scope.key,
              HouseholdProfileRouting(profile: profile, profiles: profiles, scope: scope, cwPerProfile: false).stremioSourceID == lease.route.sourceID else { throw HarborError(code: "profile-account-scope") }
        let own = HouseholdAccountRoute(household: scope.key, sourceID: profile.id)
        var next = state
        next.sources[own.key] = HouseholdAccountRecord(route: own, version: UUID(), configuration: configuration)
        try commit(next)
    }
    /// Source Stremio accounts are private even when a new profile shares settings.
    @discardableResult func migrateLegacy(_ configuration: HouseholdSourceAccount, to profile: DeviceHouseholdProfile, scope: HouseholdProfileScope) throws -> Bool {
        guard ready, let owner = profile.legacyOwner,
              owner == (configuration.account?.session.user.id ?? "guest") else { throw HarborError(code: "profile-account-migration") }
        let target = HouseholdAccountRoute(household: scope.key, sourceID: profile.id)
        if let claimed = state.migratedOwners[owner] { return claimed == target }
        guard state.sources[target.key] == nil else { throw HarborError(code: "profile-account-migration") }
        var next = state
        next.sources[target.key] = HouseholdAccountRecord(route: target, version: UUID(), configuration: configuration)
        next.migratedOwners[owner] = target
        try commit(next); return true
    }
    private func commit(_ next: HouseholdSessionState) throws {
        let value = try next.validated()
        try persistence.writeHouseholdSessions(value); state = value; error = nil
    }
}
