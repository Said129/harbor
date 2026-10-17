import XCTest
@testable import Harbor

@MainActor private final class HouseholdMemory: HouseholdProfilePersistence {
    var values: [String: HouseholdProfileState] = [:]
    var failRead = false
    var failWrite = false
    var writes = 0
    func readHousehold(_ key: String) throws -> HouseholdProfileState? {
        if failRead { throw HarborError(code: "synthetic-read") }; return values[key]
    }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws {
        if failWrite { throw HarborError(code: "synthetic-write") }; values[key] = value; writes += 1
    }
}

private actor HeldProfileCredentialCheck: ProfileCredentialChecking {
    private var answer: CheckedContinuation<Bool, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    func verifies(_ password: String, credential: DeviceProfileCredential) async throws -> Bool {
        await withCheckedContinuation { continuation in
            answer = continuation; waiting?.resume(); waiting = nil
        }
    }
    func waitUntilStarted() async {
        if answer != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func complete() { answer?.resume(returning: true); answer = nil }
}

@MainActor final class HouseholdProfileTests: XCTestCase {
    private func profile(_ id: String, name: String = "Synthetic household", primary: Bool = false, kid: Bool = false) throws -> DesktopHouseholdProfile {
        try DesktopHouseholdProfile(.object(["syncId": .string(id), "name": .string(name), "isPrimary": .bool(primary),
            "avatar": .string("/avatars/harbor_animal_01.webp"), "color": .string("#7dd3fc"), "settingsLinked": .bool(true),
            "kid": kid ? .object(["age": .integer(7), "curfewMinutes": .integer(60)]) : .null,
            "createdAt": .integer(10), "updatedAt": .integer(20), "deletedAt": .null,
            "future-desktop-field": .object(["keep": .bool(true)])]))
    }
    private func roster(_ profiles: [DesktopHouseholdProfile], extra: [String: JSONValue] = [:]) throws -> DesktopHouseholdRoster {
        var fields = extra; fields["profiles"] = .array(profiles.map(\.raw)); return try DesktopHouseholdRoster(.object(fields))
    }
    private func setup(_ existing: HouseholdMemory? = nil, scope: HouseholdProfileScope = .local(owner: "synthetic-owner")) -> (HouseholdMemory, HouseholdProfileStore) {
        let memory = existing ?? HouseholdMemory()
        return (memory, HouseholdProfileStore(scope: scope, persistence: memory))
    }
    private func knownCredential() -> DeviceProfileCredential {
        let hex = "d938e11b043abdde026737f0df28d9bcac9d97718aa2c8b7bf623cebf016eef2"
        let bytes = stride(from: 0, to: hex.count, by: 2).map { offset in
            UInt8(hex[hex.index(hex.startIndex, offsetBy: offset)..<hex.index(hex.startIndex, offsetBy: offset + 2)], radix: 16)!
        }
        return DeviceProfileCredential(version: 1, salt: Data((0..<32).map { UInt8($0) }), rounds: 600_000, digest: Data(bytes))
    }

    func testPortableRosterRetainsFutureFieldsAndDropsAllDeviceSecrets() throws {
        var fields = try profile("remote-kid", kid: true).raw.objectValue
        fields["id"] = .string("desktop-local-id"); fields["passwordHash"] = .string("must-not-cross-device")
        fields["shareStremioWith"] = .string("desktop-local-source")
        var kid = fields["kid"]!.objectValue; kid["parentPinHash"] = .string("device-only"); fields["kid"] = .object(kid)
        let document = try DesktopHouseholdRoster(.object(["profiles": .array([.object(fields)]), "future-roster": .bool(true)]))
        let wire = try XCTUnwrap(document.raw["profiles"].array.first)
        XCTAssertEqual(wire["passwordHash"], .null); XCTAssertEqual(wire["id"], .null)
        XCTAssertEqual(wire["shareStremioWith"], .null); XCTAssertEqual(wire["kid"]["parentPinHash"], .null)
        XCTAssertEqual(wire["future-desktop-field"]["keep"], .bool(true)); XCTAssertEqual(document.raw["future-roster"], .bool(true))
        XCTAssertTrue(document.profiles[0].isKid); XCTAssertEqual(document.profiles[0].age, 7); XCTAssertEqual(document.profiles[0].curfewMinutes, 60)
        let decoded = try JSONDecoder().decode(DesktopHouseholdProfile.self, from: JSONEncoder().encode(JSONValue.object(fields)))
        XCTAssertEqual(decoded.raw["passwordHash"], .null); XCTAssertEqual(decoded.raw["kid"]["parentPinHash"], .null)
        for value in ["data:image/jpeg;base64,AAAA", "https://cdn.example.test/avatar.webp", "/avatars/../private", "/avatars/a.webp?key=private"] {
            XCTAssertEqual(DesktopHouseholdProfile.portableAvatar(.string(value)), .null)
        }
        XCTAssertEqual(DesktopHouseholdProfile.portableAvatar(.string("/kids/avatars/kid-2.webp")), .string("/kids/avatars/kid-2.webp"))
    }

    func testInvalidOrDuplicateRosterCannotEraseAnExistingHousehold() throws {
        let (_, store) = setup(); _ = try store.create(name: "Existing person")
        let before = store.state
        let row = try profile("duplicate")
        XCTAssertThrowsError(try roster([row, row]))
        let malformed: JSONValue = .object(["profiles": .array([.object(["syncId": .string("bad")])])])
        XCTAssertThrowsError(try DesktopHouseholdRoster(malformed))
        var bad = row.raw.objectValue; bad["settingsLinked"] = .string("false")
        XCTAssertThrowsError(try DesktopHouseholdProfile(.object(bad)))
        bad = row.raw.objectValue; bad["kid"] = .object(["age": .integer(-1)])
        XCTAssertThrowsError(try DesktopHouseholdProfile(.object(bad)))
        XCTAssertEqual(store.state, before)
    }

    func testRoutingMatchesLinkedSettingsAndOptionalPrivateContinueWatching() throws {
        let (_, store) = setup()
        let one = try store.create(name: "Primary", legacyOwner: "synthetic-old-owner")
        let two = try store.create(name: "Second person")
        let sharedOne = HouseholdProfileRouting(profile: one, profiles: store.profiles, scope: store.scope, cwPerProfile: false)
        let sharedTwo = HouseholdProfileRouting(profile: two, profiles: store.profiles, scope: store.scope, cwPerProfile: false)
        XCTAssertNotEqual(sharedOne.personal, sharedTwo.personal); XCTAssertEqual(sharedOne.settings, sharedTwo.settings)
        XCTAssertEqual(sharedOne.personal, "synthetic-old-owner", "Existing shelves and tracker sessions retain their real iOS namespace")
        XCTAssertEqual(sharedTwo.continuing, "synthetic-old-owner", "An explicitly shared primary source retains existing playback progress")
        XCTAssertEqual(sharedOne.continuing, sharedTwo.continuing); XCTAssertEqual(sharedTwo.stremioSourceID, one.id)
        let privateTwo = HouseholdProfileRouting(profile: two, profiles: store.profiles, scope: store.scope, cwPerProfile: true)
        XCTAssertTrue(privateTwo.privateContinuing); XCTAssertEqual(privateTwo.continuing, privateTwo.personal)
        try store.edit(two.id, fields: ["settingsLinked": .bool(false)])
        let unlinked = try XCTUnwrap(store.profiles.first { $0.id == two.id })
        XCTAssertEqual(HouseholdProfileRouting(profile: unlinked, profiles: store.profiles, scope: store.scope, cwPerProfile: false).settings, sharedTwo.personal)
        try store.shareStremio(two.id, with: nil)
        let detached = try XCTUnwrap(store.profiles.first { $0.id == two.id })
        XCTAssertFalse(HouseholdProfileRouting(profile: detached, profiles: store.profiles, scope: store.scope, cwPerProfile: true).privateContinuing)
        XCTAssertThrowsError(try store.create(name: "Cannot migrate twice", legacyOwner: "another-old-owner"))
    }

    func testPINDerivationMatchesIndependentVectorAndUsesFreshDeviceSalt() async throws {
        let credential = knownCredential()
        let correct = try await credential.verifies("4826"), wrong = try await credential.verifies("4827")
        XCTAssertTrue(correct); XCTAssertFalse(wrong)
        let first = try await DeviceProfileCredential.create("4826"), second = try await DeviceProfileCredential.create("4826")
        XCTAssertTrue(first.valid); XCTAssertNotEqual(first.salt, second.salt); XCTAssertNotEqual(first.digest, second.digest)
        XCTAssertTrue(DeviceProfileCredential.validPIN("1234")); XCTAssertFalse(DeviceProfileCredential.validPIN("１２３４"))
        XCTAssertFalse(DeviceProfileCredential.validPIN("123")); XCTAssertFalse(DeviceProfileCredential.validPIN("12a4"))
    }

    func testEverySelectionRequiresRealPINAndRestartRelocksTheStoredSelection() async throws {
        let (memory, store) = setup(); let one = try store.create(name: "Primary"), two = try store.create(name: "Protected")
        let selected = try await store.select(two.id); XCTAssertTrue(selected)
        try await store.setCredential(two.id, password: "4826")
        _ = try await store.select(one.id); store.lockSession()
        let noProof = try await store.select(two.id), badProof = try await store.select(two.id, password: "4827")
        XCTAssertFalse(noProof); XCTAssertFalse(badProof); XCTAssertEqual(store.active?.id, one.id)
        let accepted = try await store.select(two.id, password: "4826"); XCTAssertTrue(accepted)
        let restart = HouseholdProfileStore(scope: store.scope, persistence: memory)
        XCTAssertEqual(restart.requestedProfile?.id, two.id); XCTAssertNil(restart.active)
        XCTAssertThrowsError(try restart.edit(two.id, fields: ["name": .string("Bypass")]))
        let reopened = try await restart.select(two.id, password: "4826"); XCTAssertTrue(reopened)
        XCTAssertEqual(restart.active?.id, two.id)
    }

    func testFailedSelectionPersistenceNeverPublishesOrCachesAnUnlock() async throws {
        let (memory, store) = setup(); let one = try store.create(name: "Primary"), two = try store.create(name: "Protected")
        _ = try await store.select(two.id); try await store.setCredential(two.id, password: "4826")
        _ = try await store.select(one.id); store.lockSession(); let before = store.state
        memory.failWrite = true
        do { _ = try await store.select(two.id, password: "4826"); XCTFail("The write must fail") } catch {}
        XCTAssertEqual(store.state, before); XCTAssertEqual(store.active?.id, one.id); XCTAssertFalse(store.verifying)
        memory.failWrite = false
        let withoutProof = try await store.select(two.id); XCTAssertFalse(withoutProof)
    }

    func testKidParentGateProtectsLeavingEditingAndRemovingTheLimit() async throws {
        let (_, store) = setup(); let adult = try store.create(name: "Adult")
        let kid = try store.create(name: "Kid", avatar: "/kids/avatars/kid-1.webp", kid: .object(["age": .integer(7), "curfewMinutes": .integer(60)]))
        try await store.setCredential(kid.id, password: "4826", parent: true)
        _ = try await store.select(kid.id); store.lockSession()
        let refused = try await store.select(adult.id), wrong = try await store.select(adult.id, parentPassword: "4827")
        XCTAssertFalse(refused); XCTAssertFalse(wrong); XCTAssertEqual(store.active?.id, kid.id)
        XCTAssertThrowsError(try store.edit(kid.id, fields: ["kid": .null])); XCTAssertThrowsError(try store.remove(kid.id))
        let unlock = try await store.unlockParent(kid.id, password: "4826"); XCTAssertTrue(unlock)
        try store.edit(kid.id, fields: ["kid": .object(["age": .integer(9), "curfewMinutes": .integer(90)])])
        XCTAssertEqual(store.active?.desktop.curfewMinutes, 90)
        let accepted = try await store.select(adult.id); XCTAssertTrue(accepted)
        _ = try await store.select(kid.id)
        let nextVisit = try await store.select(adult.id)
        XCTAssertFalse(nextVisit, "A parent editing the profile does not leave the next child visit unlocked")
    }

    func testServerAdoptionPreservesDevicePINParentPINSharingAndMigrationOwner() throws {
        let (memory, store) = setup(); let primary = try store.create(name: "Adult", legacyOwner: "existing-owner")
        let kid = try store.create(name: "Child", kid: .object(["age": .integer(7)]))
        var persisted = store.state
        let index = try XCTUnwrap(persisted.profiles.firstIndex { $0.id == kid.id })
        persisted.profiles[index].credential = knownCredential(); persisted.profiles[index].parentCredential = knownCredential()
        memory.values[store.scope.key] = persisted; store.reload()
        let remote = try kid.desktop.editing(["name": .string("Changed on Desktop"), "settingsLinked": .bool(false)], at: 100)
        try store.adopt(roster([primary.desktop, remote], extra: ["future-roster": .string("kept")]), revision: 4)
        let adopted = try XCTUnwrap(store.profiles.first { $0.id == kid.id })
        XCTAssertEqual(adopted.credential, knownCredential()); XCTAssertEqual(adopted.parentCredential, knownCredential())
        XCTAssertEqual(adopted.shareStremioWith, primary.id); XCTAssertFalse(adopted.desktop.settingsLinked)
        XCTAssertEqual(store.profiles.first { $0.id == primary.id }?.legacyOwner, "existing-owner")
        XCTAssertEqual(store.state.wireValue["future-roster"], .string("kept"))
        let encoded = String(decoding: try JSONEncoder().encode(store.state.wireValue), as: UTF8.self)
        XCTAssertFalse(encoded.contains("credential")); XCTAssertFalse(encoded.contains("parentPinHash")); XCTAssertFalse(encoded.contains("existing-owner"))
    }

    func testMissingRowsAreKeptButExplicitTombstonesRetireProfilesWithoutResurrection() throws {
        let (_, store) = setup(); let one = try store.create(name: "Primary"), two = try store.create(name: "Second")
        try store.adopt(roster([one.desktop]), revision: 2)
        XCTAssertTrue(store.profiles.contains { $0.id == two.id }); XCTAssertTrue(store.needsUpload)
        try store.remove(two.id)
        try store.adopt(roster([one.desktop, two.desktop]), revision: 3)
        XCTAssertFalse(store.profiles.contains { $0.syncID == two.syncID })
        XCTAssertTrue(store.state.wireValue["profiles"].array.contains { $0["syncId"].string == two.syncID && $0["deletedAt"] != .null })
        var tombstone = one.desktop.raw.objectValue; tombstone["deletedAt"] = .integer(300)
        try store.adopt(roster([try DesktopHouseholdProfile(.object(tombstone))]), revision: 4)
        XCTAssertTrue(store.profiles.isEmpty); XCTAssertNil(store.active)
    }

    func testReadAndWriteErrorsKeepTheCommittedRosterAndDisableFallbackOverwrite() throws {
        let (memory, store) = setup(); let one = try store.create(name: "Keep this person")
        let before = store.state; memory.failWrite = true
        XCTAssertThrowsError(try store.edit(one.id, fields: ["name": .string("Not committed")]))
        XCTAssertEqual(store.state, before)
        XCTAssertThrowsError(try store.adopt(roster([try profile("other", primary: true)]), revision: 7))
        XCTAssertEqual(store.state, before)
        memory.failWrite = false; memory.failRead = true; store.reload()
        XCTAssertFalse(store.ready); XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertThrowsError(try store.create(name: "Cannot overwrite with defaults"))
        XCTAssertEqual(memory.values[store.scope.key], before)
        memory.failRead = false; store.reload(); XCTAssertEqual(store.state, before)
    }

    func testHarborAccountsAndCanonicalScopeIdentifiersCannotShareLocalProfiles() throws {
        let memory = HouseholdMemory()
        let one = HouseholdProfileStore(scope: .harbor(account: "a|b"), persistence: memory)
        let two = HouseholdProfileStore(scope: .harbor(account: "a"), persistence: memory)
        _ = try one.create(name: "Account one")
        XCTAssertTrue(two.profiles.isEmpty); _ = try two.create(name: "Account two")
        one.reload(); XCTAssertEqual(one.profiles.first?.desktop.name, "Account one")
        XCTAssertNotEqual(HouseholdProfileScope.local(owner: "a").key, HouseholdProfileScope.harbor(account: "a").key)
        XCTAssertNotEqual(HouseholdProfileScope.hash(["a|b", "c"]), HouseholdProfileScope.hash(["a", "b|c"]))
    }

    func testRepeatedPullHasStableTimestampsNoEchoAndRejectsConflictingRevisions() throws {
        let (memory, store) = setup(); let row = try profile("desktop-primary", primary: true)
        let document = try roster([row], extra: ["future": .bool(true)])
        try store.adopt(document, revision: 8)
        XCTAssertFalse(store.needsUpload); let writes = memory.writes
        try store.adopt(document, revision: 8); XCTAssertEqual(memory.writes, writes)
        XCTAssertEqual(store.profiles[0].desktop.raw["updatedAt"], .integer(20))
        let changed = try row.editing(["name": .string("Other name")], at: 1_000)
        XCTAssertThrowsError(try store.adopt(roster([changed]), revision: 8))
        XCTAssertThrowsError(try store.adopt(document, revision: 7))
        XCTAssertThrowsError(try store.adopt(document, revision: 9_007_199_254_740_992))
        let noOp = try row.editing(["name": .string(row.name)], at: 3_000)
        XCTAssertEqual(noOp, row)
    }

    func testFirstPullNeverDeletesAnExistingGuestBasedOnItsName() throws {
        let (_, store) = setup(); let guest = try store.create(name: "Guest 4826", legacyOwner: "months-of-data")
        try store.adopt(roster([try profile("desktop-primary", primary: true)]), revision: 1)
        let kept = try XCTUnwrap(store.profiles.first { $0.id == guest.id })
        XCTAssertEqual(kept.legacyOwner, "months-of-data"); XCTAssertFalse(kept.desktop.isPrimary)
        XCTAssertEqual(store.profiles.filter { $0.desktop.isPrimary }.count, 1); XCTAssertTrue(store.needsUpload)
    }

    func testReloadInvalidatesAnInFlightPINResultBeforeItCanSelectOrUnlock() async throws {
        let (memory, original) = setup(); let one = try original.create(name: "Primary"), two = try original.create(name: "Protected")
        var saved = original.state
        let index = try XCTUnwrap(saved.profiles.firstIndex { $0.id == two.id }); saved.profiles[index].credential = knownCredential()
        memory.values[original.scope.key] = saved
        let check = HeldProfileCredentialCheck()
        let store = HouseholdProfileStore(scope: original.scope, persistence: memory, credentials: check)
        let task = Task { try await store.select(two.id, password: "synthetic-held-proof") }
        await check.waitUntilStarted(); XCTAssertTrue(store.verifying)
        store.reload(); await check.complete()
        do { _ = try await task.value; XCTFail("A stale proof must not select a profile after reload") }
        catch let failure as HarborError { XCTAssertEqual(failure.code, "profile-selection-changed") }
        XCTAssertEqual(store.active?.id, one.id); XCTAssertFalse(store.verifying)
        let noProof = try await store.select(two.id); XCTAssertFalse(noProof)
    }

    func testRemoteAdoptionInvalidatesAnInFlightUnlockAndKeepsTheDeviceCredential() async throws {
        let (memory, original) = setup(); let one = try original.create(name: "Primary"), two = try original.create(name: "Protected")
        var saved = original.state
        let index = try XCTUnwrap(saved.profiles.firstIndex { $0.id == two.id }); saved.profiles[index].credential = knownCredential()
        memory.values[original.scope.key] = saved
        let check = HeldProfileCredentialCheck()
        let store = HouseholdProfileStore(scope: original.scope, persistence: memory, credentials: check)
        let task = Task { try await store.select(two.id, password: "synthetic-held-proof") }
        await check.waitUntilStarted()
        let changed = try two.desktop.editing(["name": .string("Edited on Desktop")], at: 200)
        try store.adopt(roster([one.desktop, changed]), revision: 7)
        await check.complete()
        do { _ = try await task.value; XCTFail("An old proof cannot commit after roster adoption") }
        catch let failure as HarborError { XCTAssertEqual(failure.code, "profile-selection-changed") }
        XCTAssertEqual(store.active?.id, one.id); XCTAssertFalse(store.verifying)
        XCTAssertEqual(store.profiles.first { $0.id == two.id }?.credential, knownCredential())
        XCTAssertEqual(store.profiles.first { $0.id == two.id }?.desktop.name, "Edited on Desktop")
    }
}
