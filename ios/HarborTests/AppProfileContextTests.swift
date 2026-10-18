import XCTest
@testable import Harbor

@MainActor private final class ContextPlayback: ProfilePlaybackControlling {
    var closes = 0
    func close() { closes += 1 }
}

@MainActor private final class ProfileContextMemory: HouseholdProfilePersistence, HouseholdSessionPersistence, LegacyProfileLoading {
    var profile: HouseholdProfileState?
    var sessions: HouseholdSessionState?
    var legacy = LegacyProfileConfiguration(configuration: HouseholdSourceAccount(account: nil, guestAddons: []))
    var failLegacy = false
    var failCopy = false
    var legacyReads = 0
    func readHousehold(_ key: String) throws -> HouseholdProfileState? { profile }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws { profile = value }
    func readHouseholdSessions() throws -> HouseholdSessionState? { sessions }
    func writeHouseholdSessions(_ value: HouseholdSessionState) throws {
        if failCopy { throw HarborError(code: "synthetic-copy-failed") }; sessions = value
    }
    func loadLegacyProfile() throws -> LegacyProfileConfiguration {
        legacyReads += 1
        if failLegacy { throw HarborError(code: "synthetic-unreadable-legacy") }; return legacy
    }
}

@MainActor final class AppProfileContextTests: XCTestCase {
    private func account(_ id: String) -> HouseholdSourceAccount {
        HouseholdSourceAccount(account: SavedAccount(session: AccountSession(authKey: "synthetic-" + id,
            user: AccountUser(id: id, email: "not-for-roster@example.test", fullname: "Synthetic household")),
            collection: AccountCollection(addons: [], records: [.object(["unknown-record": .string(id)])])), guestAddons: [])
    }
    private func make(_ memory: ProfileContextMemory) -> AppProfileContext {
        let store = HouseholdProfileStore(scope: .local(owner: "synthetic-device"), persistence: memory)
        return AppProfileContext(profiles: store, sessions: HouseholdSessionVault(persistence: memory), legacy: memory)
    }
    func testBootstrapKeepsExistingNamespacesAndNeverReadsLegacyAfterTheAtomicClaim() throws {
        let memory = ProfileContextMemory(); memory.legacy = LegacyProfileConfiguration(configuration: account("existing-owner"))
        let context = make(memory); try context.prepare()
        XCTAssertTrue(context.ready); XCTAssertEqual(context.binding?.personalOwner, "existing-owner")
        XCTAssertEqual(context.binding?.progressOwner, "existing-owner"); XCTAssertEqual(context.configuration, memory.legacy.configuration)
        XCTAssertEqual(memory.legacyReads, 1)
        memory.failLegacy = true
        let restart = make(memory); try restart.prepare()
        XCTAssertTrue(restart.ready); XCTAssertEqual(memory.legacyReads, 1)
        XCTAssertEqual(restart.configuration?.account?.collection.records.first?["unknown-record"], .string("existing-owner"))
    }
    func testASeparateHarborHouseholdNeverImportsTheDeviceLegacySession() throws {
        let memory = ProfileContextMemory(); memory.legacy = LegacyProfileConfiguration(configuration: account("private-device-owner"))
        let store = HouseholdProfileStore(scope: .harbor(account: "separate-synthetic-household"), persistence: memory)
        let context = AppProfileContext(profiles: store, sessions: HouseholdSessionVault(persistence: memory), legacy: memory)
        try context.prepare()
        XCTAssertEqual(memory.legacyReads, 0); XCTAssertTrue(store.profiles.isEmpty); XCTAssertNil(context.configuration)
        _ = try store.create(name: "Remote household")
        try context.prepare()
        XCTAssertTrue(context.ready); XCTAssertEqual(memory.legacyReads, 0); XCTAssertNil(context.configuration)
        XCTAssertNotEqual(context.binding?.personalOwner, "private-device-owner")
    }
    func testFailedInitialCopyRecoversTheSameProfileWithoutCreatingAnotherGuest() throws {
        let memory = ProfileContextMemory(); memory.failCopy = true; let context = make(memory)
        XCTAssertThrowsError(try context.prepare())
        let id = try XCTUnwrap(context.profiles.profiles.first?.id)
        XCTAssertEqual(context.profiles.profiles.count, 1); XCTAssertNil(memory.sessions)
        memory.failCopy = false; try context.prepare()
        XCTAssertEqual(context.profiles.profiles.count, 1); XCTAssertEqual(context.binding?.profileID, id)
        XCTAssertTrue(context.ready)
    }
    func testProfilesSharingStremioHaveSeparatePersonalDataAndExplicitSignInDetachesOnlyOne() async throws {
        let memory = ProfileContextMemory(); memory.legacy = LegacyProfileConfiguration(configuration: account("primary-owner"))
        let context = make(memory); try context.prepare()
        let first = try XCTUnwrap(context.profiles.active)
        let second = try context.profiles.create(name: "Second person")
        let primary = try XCTUnwrap(context.binding)
        _ = try await context.select(second.id)
        XCTAssertEqual(context.configuration?.account?.session.user.id, "primary-owner")
        XCTAssertNotEqual(context.binding?.personalOwner, primary.personalOwner)
        XCTAssertEqual(context.binding?.settingsOwner, primary.settingsOwner)
        XCTAssertEqual(context.binding?.progressOwner, primary.progressOwner)
        try context.save(account("independent-owner"), explicitAuthenticationChange: true)
        XCTAssertNil(context.profiles.active?.shareStremioWith)
        XCTAssertEqual(context.configuration?.account?.session.user.id, "independent-owner")
        _ = try await context.select(first.id)
        XCTAssertEqual(context.configuration?.account?.session.user.id, "primary-owner")
        XCTAssertEqual(context.binding?.personalOwner, "primary-owner")
    }
    func testIndependentGuestSourceCannotInheritTheOriginalGuestLibraryOrResumeNamespace() async throws {
        let memory = ProfileContextMemory(), context = make(memory); try context.prepare()
        let original = try XCTUnwrap(context.binding)
        let second = try context.profiles.create(name: "Independent guest")
        try context.profiles.shareStremio(second.id, with: nil)
        _ = try await context.select(second.id)
        XCTAssertNotEqual(context.binding?.progressOwner, original.progressOwner)
        XCTAssertNotEqual(context.binding?.personalOwner, original.personalOwner)
        XCTAssertNil(context.configuration)
        let before = context.activationID
        try context.save(account("new-owner"), explicitAuthenticationChange: true)
        XCTAssertNotEqual(context.activationID, before)
        XCTAssertNotEqual(context.binding?.progressOwner, original.progressOwner)
    }
    func testActivationTokenChangesEvenWhenTheSameStremioAccountIsSharedOrRevisited() async throws {
        let memory = ProfileContextMemory(), context = make(memory); try context.prepare()
        let first = try XCTUnwrap(context.profiles.active)
        let token = context.activationID, second = try context.profiles.create(name: "Second person")
        let oldPlayer = ContextPlayback()
        XCTAssertTrue(context.playback.register(oldPlayer, generation: context.playback.generation))
        _ = try await context.select(second.id); XCTAssertNotEqual(context.activationID, token)
        XCTAssertEqual(oldPlayer.closes, 1)
        _ = try await context.select(first.id); XCTAssertNotEqual(context.activationID, token)
        let current = context.activationID
        let samePlayer = ContextPlayback()
        XCTAssertTrue(context.playback.register(samePlayer, generation: context.playback.generation))
        try context.save(HouseholdSourceAccount(account: nil, guestAddons: []))
        XCTAssertEqual(context.activationID, current, "A source refresh must not reset the active UI")
        XCTAssertEqual(samePlayer.closes, 0)
        context.reload(); XCTAssertEqual(samePlayer.closes, 1)
    }
    func testUnreadableLegacyNeverCreatesDefaultsAndLockedSelectionHidesTheAccountUntilVerified() async throws {
        let memory = ProfileContextMemory(); memory.failLegacy = true; let context = make(memory)
        XCTAssertThrowsError(try context.prepare()); XCTAssertTrue(context.profiles.profiles.isEmpty); XCTAssertNil(memory.sessions)
        memory.failLegacy = false; try context.prepare()
        let first = try XCTUnwrap(context.profiles.active)
        try await context.profiles.setCredential(first.id, password: "4826")
        context.profiles.lockSession(); try context.refreshRouting()
        XCTAssertTrue(context.requiresSelection); XCTAssertFalse(context.ready); XCTAssertNil(context.configuration)
        let wrong = try await context.select(first.id, password: "4827"); XCTAssertFalse(wrong)
        XCTAssertFalse(context.ready)
        let correct = try await context.select(first.id, password: "4826"); XCTAssertTrue(correct); XCTAssertTrue(context.ready)
    }
    func testHarborIdentitySurvivesChangingStremioAndRemovingTheOriginalProfile() async throws {
        let memory = ProfileContextMemory(); memory.legacy = LegacyProfileConfiguration(configuration: account("original-source"))
        let context = make(memory); try context.prepare()
        let original = try XCTUnwrap(context.profiles.active)
        let identity = try XCTUnwrap(context.binding?.identityOwner)
        let next = try context.profiles.create(name: "Second person")
        try context.profiles.makePrimary(next.id)
        _ = try await context.select(next.id)
        try context.save(account("different-source"), explicitAuthenticationChange: true)
        try context.profiles.remove(original.id); try context.refreshRouting()
        XCTAssertEqual(context.binding?.identityOwner, identity)
        XCTAssertEqual(context.binding?.sharedSettingsOwner, identity)
        XCTAssertNotEqual(context.binding?.personalOwner, identity)
        context.reload(); try context.prepare()
        XCTAssertEqual(context.binding?.identityOwner, identity)
        XCTAssertEqual(context.configuration?.account?.session.user.id, "different-source")
        XCTAssertTrue(context.profiles.profiles.allSatisfy { $0.legacyOwner == nil })
    }
}
