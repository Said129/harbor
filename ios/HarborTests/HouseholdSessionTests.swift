import XCTest
@testable import Harbor

@MainActor private final class HouseholdSessionMemory: HouseholdSessionPersistence {
    var value: HouseholdSessionState?
    var failRead = false
    var failWrite = false
    func readHouseholdSessions() throws -> HouseholdSessionState? {
        if failRead { throw HarborError(code: "synthetic-read") }; return value
    }
    func writeHouseholdSessions(_ value: HouseholdSessionState) throws {
        if failWrite { throw HarborError(code: "synthetic-write") }; self.value = value
    }
}
@MainActor private final class SessionTestProfiles: HouseholdProfilePersistence {
    var value: HouseholdProfileState?
    func readHousehold(_ key: String) throws -> HouseholdProfileState? { value }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws { self.value = value }
}

@MainActor final class HouseholdSessionTests: XCTestCase {
    private func makeProfiles() throws -> (HouseholdProfileStore, DeviceHouseholdProfile, DeviceHouseholdProfile) {
        let store = HouseholdProfileStore(scope: .local(owner: "synthetic-stremio-owner"), persistence: SessionTestProfiles())
        let first = try store.create(name: "Primary", legacyOwner: "synthetic-stremio-owner")
        let second = try store.create(name: "Secondary")
        return (store, first, second)
    }
    private var account: HouseholdSourceAccount {
        let user = AccountUser(id: "synthetic-stremio-owner", email: nil, fullname: "Synthetic user")
        let saved = SavedAccount(session: AccountSession(authKey: "synthetic-offline-token", user: user),
            collection: AccountCollection(addons: [], records: [.object(["unknown-cloud-record": .bool(true)])]))
        return HouseholdSourceAccount(account: saved, guestAddons: [])
    }
    func testSharedStremioSourceUsesTheSameSessionButIndependentSourceIsEmpty() throws {
        let (profiles, first, second) = try makeProfiles(); let vault = HouseholdSessionVault(persistence: HouseholdSessionMemory())
        let lease = try vault.bind(profile: first, profiles: profiles.profiles, scope: profiles.scope)
        try vault.save(account, using: lease)
        let shared = try vault.bind(profile: second, profiles: profiles.profiles, scope: profiles.scope)
        XCTAssertEqual(shared.configuration, account)
        try profiles.shareStremio(second.id, with: nil)
        let detached = try XCTUnwrap(profiles.profiles.first { $0.id == second.id })
        let separate = try vault.bind(profile: detached, profiles: profiles.profiles, scope: profiles.scope)
        XCTAssertNil(separate.configuration); XCTAssertNil(vault.current)
    }
    func testLateLoginOrRefreshCannotWriteAfterTheSelectedSourceChanged() throws {
        let (profiles, first, second) = try makeProfiles(); let vault = HouseholdSessionVault(persistence: HouseholdSessionMemory())
        let old = try vault.bind(profile: first, profiles: profiles.profiles, scope: profiles.scope)
        try profiles.shareStremio(second.id, with: nil)
        let detached = try XCTUnwrap(profiles.profiles.first { $0.id == second.id })
        _ = try vault.bind(profile: detached, profiles: profiles.profiles, scope: profiles.scope)
        XCTAssertThrowsError(try vault.save(account, using: old)); XCTAssertNil(vault.current)
        _ = try vault.bind(profile: first, profiles: profiles.profiles, scope: profiles.scope)
        XCTAssertThrowsError(try vault.save(account, using: old), "Returning to the old source does not revive a stale request")
    }
    func testLegacySessionAndClaimAreAtomicIdempotentAndNeverCopiedToAnotherHousehold() throws {
        let (profiles, first, _) = try makeProfiles(); let memory = HouseholdSessionMemory(), vault = HouseholdSessionVault(persistence: memory)
        memory.failWrite = true
        XCTAssertThrowsError(try vault.migrateLegacy(account, to: first, scope: profiles.scope)); XCTAssertNil(memory.value)
        memory.failWrite = false
        XCTAssertTrue(try vault.migrateLegacy(account, to: first, scope: profiles.scope))
        let lease = try vault.bind(profile: first, profiles: profiles.profiles, scope: profiles.scope)
        XCTAssertEqual(lease.configuration, account)
        try vault.save(HouseholdSourceAccount(account: nil, guestAddons: []), using: lease)
        XCTAssertTrue(try vault.migrateLegacy(account, to: first, scope: profiles.scope))
        XCTAssertNil(vault.current?.account, "Legacy files must not sign a profile back in after it signed out")
        XCTAssertFalse(try vault.migrateLegacy(account, to: first, scope: .harbor(account: "another-household")))
        let restart = HouseholdSessionVault(persistence: memory)
        let restored = try restart.bind(profile: first, profiles: profiles.profiles, scope: profiles.scope)
        XCTAssertNil(restored.configuration?.account)
    }
    func testWriteCompareAndSwapKeepsNewerAccountAndCompleteUnknownCloudRecords() throws {
        let (profiles, first, _) = try makeProfiles(); let memory = HouseholdSessionMemory(), vault = HouseholdSessionVault(persistence: memory)
        let initial = try vault.bind(profile: first, profiles: profiles.profiles, scope: profiles.scope)
        try vault.save(account, using: initial)
        XCTAssertThrowsError(try vault.save(HouseholdSourceAccount(account: nil, guestAddons: nil), using: initial))
        XCTAssertEqual(vault.current?.account?.collection.records.first?["unknown-cloud-record"], .bool(true))
        let restart = HouseholdSessionVault(persistence: memory)
        let restored = try restart.bind(profile: first, profiles: profiles.profiles, scope: profiles.scope)
        XCTAssertEqual(restored.configuration, account)
    }
    func testUnreadableVaultNeverExposesOldAccountsOrOverwritesWithDefaults() throws {
        let (profiles, first, _) = try makeProfiles(); let memory = HouseholdSessionMemory(), vault = HouseholdSessionVault(persistence: memory)
        let lease = try vault.bind(profile: first, profiles: profiles.profiles, scope: profiles.scope)
        try vault.save(account, using: lease); let before = memory.value
        memory.failRead = true; vault.reload()
        XCTAssertFalse(vault.ready); XCTAssertNil(vault.current)
        XCTAssertThrowsError(try vault.save(account, using: lease))
        XCTAssertThrowsError(try vault.bind(profile: first, profiles: profiles.profiles, scope: profiles.scope))
        XCTAssertEqual(memory.value, before)
        memory.failRead = false; vault.reload()
        _ = try vault.bind(profile: first, profiles: profiles.profiles, scope: profiles.scope)
        XCTAssertEqual(vault.current, account)
    }
}
