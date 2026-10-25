import XCTest
@testable import Harbor

@MainActor private final class OwnedIdentityMigration: HarborIdentityMigrationPersistence {
    var values: [String: JSONValue] = [:]
    var remaining: Int?
    func readIdentity(_ key: String) throws -> JSONValue? { values[key] }
    func writeIdentity(_ value: JSONValue, key: String) throws {
        if let remaining {
            guard remaining > 0 else { throw HarborError(code: "owned-identity-copy-failure") }
            self.remaining = remaining - 1
        }
        values[key] = value
    }
}

@MainActor final class ProfileIdentityMigrationTests: XCTestCase {
    private func record(_ id: String = "owned-user", server: HarborIdentityServer? = nil) -> JSONValue {
        var session: [String: JSONValue] = ["id": .string(id), "username": .string("Owned"), "token": .string("owned-token"), "refresh": .string("owned-refresh")]
        if let server { session["server"] = .string(server.base) }
        return .object(["session": .object(session), "future": .object(["preserved": .bool(true)])])
    }
    func testLegacyIdentityIsAssignedOnlyToThePrimaryAndSecondarySettingsOrStremioSharingCannotInheritIt() async throws {
        let memory = ActivationMemory(), context = memory.context(), storage = OwnedIdentityMigration()
        try context.prepare()
        let primary = try XCTUnwrap(context.profiles.active), source = HarborProfileIdentity.key(memory.identity), previous = record()
        let secondary = try context.profiles.create(name: "Secondary")
        XCTAssertTrue(secondary.desktop.settingsLinked); XCTAssertEqual(secondary.shareStremioWith, primary.id)
        let primaryOwner = HarborProfileIdentity.owner(primary, scope: context.profiles.scope)
        storage.values[source] = previous
        XCTAssertTrue(try HarborProfileIdentity.migrateLegacy(context: context, persistence: storage))
        XCTAssertEqual(storage.values[HarborProfileIdentity.key(primaryOwner)], previous)
        let changed = try await context.select(secondary.id); XCTAssertTrue(changed)
        XCTAssertFalse(try HarborProfileIdentity.migrateLegacy(context: context, persistence: storage))
        let secondaryOwner = HarborProfileIdentity.owner(secondary, scope: context.profiles.scope)
        XCTAssertNotEqual(primaryOwner, secondaryOwner); XCTAssertNil(storage.values[HarborProfileIdentity.key(secondaryOwner)])
        XCTAssertEqual(storage.values[source], previous)
        XCTAssertEqual(storage.values[HarborProfileIdentity.claimKey(memory.identity)], .string(primaryOwner))
    }
    func testAnExplicitPrivateLogoutOrLoginWinsOverLegacyStateAndEvenADamagedLegacyRecord() throws {
        let memory = ActivationMemory(), context = memory.context(), storage = OwnedIdentityMigration()
        try context.prepare()
        let target = HarborProfileIdentity.owner(try XCTUnwrap(context.profiles.active), scope: context.profiles.scope)
        let destination = HarborProfileIdentity.key(target), source = HarborProfileIdentity.key(memory.identity)
        for existing in [JSONValue.object([:]), record("private-user", server: .community)] {
            storage.values = [source: record(), destination: existing]
            XCTAssertFalse(try HarborProfileIdentity.migrateLegacy(context: context, persistence: storage))
            XCTAssertEqual(storage.values[destination], existing)
            storage.values[source] = .object(["session": .array([])])
            XCTAssertFalse(try HarborProfileIdentity.migrateLegacy(context: context, persistence: storage))
            XCTAssertEqual(storage.values[destination], existing)
        }
    }
    func testAnInterruptedCopyCanRetryOnlyForItsClaimedPrimaryEvenAfterAnotherProfileBecomesPrimary() async throws {
        let memory = ActivationMemory(), context = memory.context(), storage = OwnedIdentityMigration()
        try context.prepare()
        let primary = try XCTUnwrap(context.profiles.active), other = try context.profiles.create(name: "Other")
        let destination = HarborProfileIdentity.key(HarborProfileIdentity.owner(primary, scope: context.profiles.scope))
        let source = HarborProfileIdentity.key(memory.identity), previous = record()
        storage.values[source] = previous; storage.remaining = 1
        XCTAssertThrowsError(try HarborProfileIdentity.migrateLegacy(context: context, persistence: storage))
        XCTAssertNil(storage.values[destination]); XCTAssertEqual(storage.values[source], previous)
        try context.profiles.makePrimary(other.id)
        let selected = try await context.select(other.id); XCTAssertTrue(selected); storage.remaining = nil
        XCTAssertFalse(try HarborProfileIdentity.migrateLegacy(context: context, persistence: storage))
        XCTAssertNil(storage.values[HarborProfileIdentity.key(HarborProfileIdentity.owner(other, scope: context.profiles.scope))])
        try context.profiles.makePrimary(primary.id)
        let returned = try await context.select(primary.id); XCTAssertTrue(returned)
        XCTAssertTrue(try HarborProfileIdentity.migrateLegacy(context: context, persistence: storage))
        XCTAssertEqual(storage.values[destination], previous)
    }
    func testMalformedLegacyStateOrClaimCannotCreateAPrivateIdentityOrOverwriteTheOriginal() throws {
        let memory = ActivationMemory(), context = memory.context(), storage = OwnedIdentityMigration()
        try context.prepare()
        let destination = HarborProfileIdentity.key(HarborProfileIdentity.owner(try XCTUnwrap(context.profiles.active), scope: context.profiles.scope))
        let source = HarborProfileIdentity.key(memory.identity), malformed: JSONValue = .object(["session": .object(["id": .integer(5)])])
        storage.values[source] = malformed
        XCTAssertThrowsError(try HarborProfileIdentity.migrateLegacy(context: context, persistence: storage))
        XCTAssertEqual(storage.values[source], malformed); XCTAssertNil(storage.values[destination])
        storage.values[source] = record(); storage.values[HarborProfileIdentity.claimKey(memory.identity)] = .string("not-a-profile-identity")
        XCTAssertThrowsError(try HarborProfileIdentity.migrateLegacy(context: context, persistence: storage))
        XCTAssertNil(storage.values[destination]); XCTAssertEqual(storage.values[source], record())
    }
    func testAMatchingProviderIDOnAnotherServerCannotClaimTheActivatedHouseholdsLegacyIdentity() throws {
        let memory = ActivationMemory(), context = memory.context(), storage = OwnedIdentityMigration()
        try context.prepare(); try context.activateHarbor(account: "same-provider", document: memory.document())
        let source = HarborProfileIdentity.key(memory.identity), previous = record("same-provider", server: .community)
        storage.values[source] = previous
        XCTAssertFalse(try HarborProfileIdentity.migrateLegacy(context: context, persistence: storage))
        XCTAssertNil(storage.values[HarborProfileIdentity.claimKey(memory.identity)]); XCTAssertEqual(storage.values[source], previous)
    }
    func testAuthenticatedActivationPreservesEachPrivateNamespaceAndTheAliasNeverEntersThePortableRoster() throws {
        let memory = ActivationMemory(), context = memory.context()
        try context.prepare()
        let primary = try XCTUnwrap(context.profiles.active), secondary = try context.profiles.create(name: "Other")
        let old = Dictionary(uniqueKeysWithValues: context.profiles.profiles.map { ($0.id, HarborProfileIdentity.owner($0, scope: context.profiles.scope)) })
        let doc = memory.document([memory.remote(), secondary.desktop.raw])
        try context.activateHarbor(account: "owned-account", document: doc, identityOwner: try XCTUnwrap(old[primary.id]))
        for row in context.profiles.profiles { XCTAssertEqual(HarborProfileIdentity.owner(row, scope: context.profiles.scope), old[row.id]) }
        let wire = String(decoding: try JSONEncoder().encode(context.profiles.state.wireValue), as: UTF8.self)
        XCTAssertFalse(wire.contains("localIdentityOwner")); XCTAssertFalse(wire.contains("harbor-profile-"))
        var foreign = memory.remote().objectValue; foreign["localIdentityOwner"] = .string(try XCTUnwrap(old[secondary.id]))
        XCTAssertEqual(try DesktopHouseholdProfile(.object(foreign)).raw["localIdentityOwner"], .null)
        var invalid = context.profiles.state; invalid.profiles[0].localIdentityOwner = "invalid"
        XCTAssertThrowsError(try invalid.validated())
    }
}
