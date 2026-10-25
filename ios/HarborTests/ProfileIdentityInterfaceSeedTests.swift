import XCTest
@testable import Harbor

final class ProfileIdentityInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareAnOwnedRetiredPrimaryIdentityAndAnUnsignedLinkedSecondaryOnAFreshGuest() async throws {
        try await PageContinuationInterfaceSeedTests.prepareOwnedHistory()
        let context = AppProfileContext.shared, store = KeychainStore()
        let binding = try XCTUnwrap(context.binding), primary = try XCTUnwrap(context.profiles.active)
        let key = HarborProfileIdentity.key(binding.identityOwner)
        guard try store.read(key, as: JSONValue.self) == nil,
              try store.read(HarborProfileIdentity.claimKey(binding.identityOwner), as: JSONValue.self) == nil else { XCTFail("Refuse an existing Harbor identity"); return }
        try context.profiles.edit(primary.id, fields: ["name": .string("Owned primary")])
        let secondary = try context.profiles.create(name: "Owned independent")
        XCTAssertTrue(secondary.desktop.settingsLinked); XCTAssertEqual(secondary.shareStremioWith, primary.id)
        let raw: JSONValue = .object(["session": .object(["id": .string("owned-retired-account"), "username": .string("Owned primary"),
            "token": .string("owned-retired-token"), "refresh": .string("owned-retired-refresh")])])
        // A retired origin fails locally before transport; synthetic credentials
        // must never be submitted to a real account service in UI preparation.
        try store.write(raw, key: key)
        let settings = ProfileSettingsStore.shared
        try settings.activate(owner: binding.settingsOwner, sharedOwner: binding.sharedSettingsOwner, migrateLegacy: true, legacyTMDB: { nil })
        try settings.setLaunchPreferences(ProfileLaunchPreferences(interval: .never, defaultID: primary.id), sharedOwner: binding.sharedSettingsOwner, expectedOwner: binding.settingsOwner)
        XCTAssertNil(try store.read(HarborProfileIdentity.key(HarborProfileIdentity.owner(secondary, scope: context.profiles.scope)), as: JSONValue.self))
    }
}
