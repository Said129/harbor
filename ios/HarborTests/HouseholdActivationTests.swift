import XCTest
@testable import Harbor

@MainActor final class ActivationMemory: HouseholdProfilePersistence, HouseholdSessionPersistence, LegacyProfileLoading {
    let identity = "owned-activation-" + UUID().uuidString
    var rosters: [String: HouseholdProfileState] = [:]
    var sessions: HouseholdSessionState?
    var failRoster = false
    var failSession = false
    var failActivation = false
    var legacyReads = 0
    var legacy: LegacyProfileConfiguration {
        LegacyProfileConfiguration(configuration: HouseholdSourceAccount(account: SavedAccount(session: AccountSession(authKey: "owned-stremio-secret",
            user: AccountUser(id: identity, email: "owned@example.test", fullname: "Owned device")),
            collection: AccountCollection(addons: [], records: [.object(["private-record": .string("kept locally")])])), guestAddons: []))
    }
    func readHousehold(_ key: String) throws -> HouseholdProfileState? { rosters[key] }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws {
        if failRoster { throw HarborError(code: "owned-roster-failure") }; rosters[key] = value
    }
    func readHouseholdSessions() throws -> HouseholdSessionState? { sessions }
    func writeHouseholdSessions(_ value: HouseholdSessionState) throws {
        if failSession || (failActivation && value.activeHarborAccount != nil) { throw HarborError(code: "owned-session-failure") }
        sessions = value
    }
    func loadLegacyProfile() throws -> LegacyProfileConfiguration { legacyReads += 1; return legacy }
    func context() -> AppProfileContext {
        let factory: @MainActor (HouseholdProfileScope) -> HouseholdProfileStore = { HouseholdProfileStore(scope: $0, persistence: self) }
        return AppProfileContext(profiles: factory(.local(owner: identity)), sessions: HouseholdSessionVault(persistence: self), legacy: self, profileFactory: factory)
    }
    func remote(_ id: String = "desktop-primary", primary: Bool = true) -> JSONValue {
        .object(["syncId": .string(id), "name": .string(primary ? "Desktop primary" : "Desktop second"), "isPrimary": .bool(primary),
            "avatar": .string("/avatars/harbor_animal_01.webp"), "kid": .null, "settingsLinked": .bool(primary),
            "createdAt": .integer(1), "updatedAt": .integer(2), "deletedAt": .null])
    }
    func document(_ profiles: [JSONValue]? = nil) -> HarborLayoutDocument {
        HarborLayoutDocument(key: "account:profiles", rev: 2, value: .object(["profiles": .array(profiles ?? [remote()])]))
    }
}

@MainActor final class HouseholdActivationTests: XCTestCase {
    func testFirstAccountPreservesTheDeviceProfileAndEveryExistingDataNamespace() throws {
        let memory = ActivationMemory(), context = memory.context(); try context.prepare()
        let before = try XCTUnwrap(context.binding), source = try XCTUnwrap(context.configuration)
        let activated = try context.activateHarbor(account: "A", document: memory.document())
        XCTAssertTrue(activated); XCTAssertEqual(context.profiles.scope, .harbor(account: "A"))
        XCTAssertEqual(context.profiles.active?.id, before.profileID); XCTAssertEqual(context.profiles.active?.syncID, "desktop-primary")
        XCTAssertEqual(context.binding?.personalOwner, before.personalOwner)
        XCTAssertEqual(context.binding?.settingsOwner, before.settingsOwner)
        XCTAssertEqual(context.binding?.progressOwner, before.progressOwner)
        XCTAssertEqual(context.configuration, source); XCTAssertEqual(memory.sessions?.deviceImportAccount, "A")
        XCTAssertEqual(context.profiles.profiles.count, 1)
        let wire = try JSONEncoder().encode(context.profiles.state.wireValue)
        let text = String(decoding: wire, as: UTF8.self)
        for privateField in ["localDataOwner", "localProgressOwner", "authKey", "owned-stremio-secret", "private-record"] { XCTAssertFalse(text.contains(privateField)) }
    }
    func testAnotherAccountHasSeparateProfilesAndCannotCopyTheFirstAccountsSessionsOrShelves() throws {
        let memory = ActivationMemory(), context = memory.context(); try context.prepare()
        try context.activateHarbor(account: "A", document: memory.document())
        let a = try XCTUnwrap(context.binding), configuration = context.configuration
        try context.activateHarbor(account: "B", document: memory.document([memory.remote("B-primary")]))
        XCTAssertNotEqual(context.binding?.profileID, a.profileID); XCTAssertNotEqual(context.binding?.personalOwner, a.personalOwner)
        XCTAssertNotEqual(context.binding?.settingsOwner, a.settingsOwner); XCTAssertNil(context.configuration?.account)
        XCTAssertEqual(memory.sessions?.deviceImportAccount, "A")
        try context.activateHarbor(account: "A", document: memory.document())
        XCTAssertEqual(context.binding, a); XCTAssertEqual(context.configuration, configuration)
        context.reload(); try context.prepare()
        XCTAssertEqual(context.profiles.scope, .harbor(account: "A")); XCTAssertEqual(context.binding, a)
        XCTAssertEqual(memory.legacyReads, 1)
    }
    func testAProfilePINSurvivesImportAndMustBeVerifiedBeforeTheNewContextCanExposeItsAccount() async throws {
        let memory = ActivationMemory(), context = memory.context(); try context.prepare()
        let id = try XCTUnwrap(context.profiles.active?.id)
        try await context.profiles.setCredential(id, password: "4826")
        try context.activateHarbor(account: "A", document: memory.document())
        XCTAssertFalse(context.ready); XCTAssertNil(context.configuration); XCTAssertTrue(context.requiresSelection)
        XCTAssertNotNil(context.profiles.requestedProfile?.credential)
        let wrong = try await context.select(id, password: "4827"); XCTAssertFalse(wrong); XCTAssertNil(context.configuration)
        let correct = try await context.select(id, password: "4826"); XCTAssertTrue(correct)
        XCTAssertEqual(context.configuration?.account?.session.user.id, memory.identity)
    }
    func testAnInterruptedRosterInstallKeepsTheOldContextAndRetriesTheStagedPrivateCopyWithoutDuplicates() throws {
        let memory = ActivationMemory(), context = memory.context(); try context.prepare()
        let before = context.binding, configuration = context.configuration
        memory.failRoster = true
        XCTAssertThrowsError(try context.activateHarbor(account: "A", document: memory.document()))
        XCTAssertEqual(context.binding, before); XCTAssertEqual(context.configuration, configuration)
        XCTAssertNil(memory.sessions?.activeHarborAccount)
        let id = try XCTUnwrap(before?.profileID), destination = HouseholdAccountRoute(household: HouseholdProfileScope.harbor(account: "A").key, sourceID: id)
        let staged = try XCTUnwrap(memory.sessions?.sources[destination.key]?.version)
        memory.failRoster = false
        try context.activateHarbor(account: "A", document: memory.document())
        XCTAssertEqual(memory.sessions?.sources[destination.key]?.version, staged)
        XCTAssertEqual(context.profiles.profiles.map(\.id), [id]); XCTAssertEqual(context.configuration, configuration)
    }
    func testFailedSessionStagingAndFinalActivationLeaveTheOriginalContextUsable() throws {
        let memory = ActivationMemory(), context = memory.context(); try context.prepare()
        let before = context.binding
        memory.failSession = true
        XCTAssertThrowsError(try context.activateHarbor(account: "A", document: memory.document()))
        XCTAssertNil(memory.rosters[HouseholdProfileScope.harbor(account: "A").key]); XCTAssertEqual(context.binding, before)
        memory.failSession = false; memory.failActivation = true
        XCTAssertThrowsError(try context.activateHarbor(account: "A", document: memory.document()))
        XCTAssertEqual(context.binding, before); XCTAssertNil(memory.sessions?.activeHarborAccount)
        memory.failActivation = false
        try context.activateHarbor(account: "A", document: memory.document())
        XCTAssertEqual(context.binding?.profileID, before?.profileID); XCTAssertTrue(context.ready)
    }
    func testSharedAndIndependentProfilesKeepTheirOwnSettingsAndSourceRouting() async throws {
        let memory = ActivationMemory(), context = memory.context(); try context.prepare()
        let primary = try XCTUnwrap(context.profiles.active)
        let second = try context.profiles.create(name: "Independent")
        try context.profiles.edit(second.id, fields: ["settingsLinked": .bool(false)])
        let selected = try await context.select(second.id); XCTAssertTrue(selected)
        let before = try XCTUnwrap(context.binding)
        try context.activateHarbor(account: "A", document: memory.document([memory.remote(), memory.remote("remote-extra", primary: false)]))
        XCTAssertEqual(context.binding?.personalOwner, before.personalOwner); XCTAssertEqual(context.binding?.settingsOwner, before.settingsOwner)
        XCTAssertEqual(context.binding?.progressOwner, before.progressOwner)
        XCTAssertEqual(context.binding?.stremioSourceID, primary.id); XCTAssertNotNil(context.configuration?.account)
        let remote = try XCTUnwrap(context.profiles.profiles.first { $0.syncID == "remote-extra" })
        let remoteSelected = try await context.select(remote.id); XCTAssertTrue(remoteSelected)
        XCTAssertNil(context.configuration?.account, "An imported Desktop profile never inherits private source credentials implicitly")
    }
    func testMalformedRosterFailsBeforeClaimingAnAccountOrReplacingAnyLocalProfile() throws {
        let memory = ActivationMemory(), context = memory.context(); try context.prepare()
        let before = context.profiles.state
        let invalid = HarborLayoutDocument(key: "account:profiles", rev: 2, value: .object(["profiles": .array([memory.remote(), memory.remote()])]))
        XCTAssertThrowsError(try context.activateHarbor(account: "A", document: invalid))
        XCTAssertEqual(context.profiles.state, before); XCTAssertNil(memory.sessions?.deviceImportAccount)
        XCTAssertNil(memory.sessions?.activeHarborAccount)
    }
    func testOlderPersistedVersionsDecodeWithoutNewAliasesOrAccountClaims() throws {
        let profiles = try JSONDecoder().decode(HouseholdProfileState.self, from: Data("{\"version\":1,\"profiles\":[],\"tombstones\":[]}".utf8))
        XCTAssertNil(profiles.sharedSettingsOwner); XCTAssertEqual(try profiles.validated(), profiles)
        let sessions = try JSONDecoder().decode(HouseholdSessionState.self, from: Data("{\"version\":1,\"sources\":{},\"migratedOwners\":{}}".utf8))
        XCTAssertNil(sessions.activeHarborAccount); XCTAssertNil(sessions.deviceImportAccount); XCTAssertEqual(try sessions.validated(), sessions)
    }
}
