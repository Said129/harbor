import XCTest
@testable import Harbor

final class ContinuePrivacyInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareTwoOwnedProfilesSharingAnUnconfiguredGuestSource() throws {
        _ = try Self.prepareOwnedSharedGuest()
    }
    @MainActor static func prepareOwnedSharedGuest() throws -> (binding: ActiveProfileBinding, other: DeviceHouseholdProfile) {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else { XCTFail("Refuse configured account"); throw HarborError(code: "owned-seed-safety") }
        let context = AppProfileContext.shared; try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil, context.configuration?.account == nil,
              let binding = context.binding else { XCTFail("Refuse configured household"); throw HarborError(code: "owned-seed-safety") }
        try context.save(HouseholdSourceAccount(account: nil, guestAddons: []))
        let profile = try context.profiles.create(name: "Owned shared profile")
        XCTAssertEqual(profile.shareStremioWith, binding.profileID)
        try ProfileSettingsStore.shared.activate(owner: binding.settingsOwner, sharedOwner: binding.sharedSettingsOwner, migrateLegacy: true, legacyTMDB: { nil })
        let defaults = UserDefaults.standard
        defaults.set(ContinueWatchingSources.defaultValue, forKey: "cwSources"); defaults.set(false, forKey: "cwPerProfile")
        defaults.set("never", forKey: "profilePromptInterval"); defaults.set("en", forKey: "uiLanguage"); defaults.set("classic", forKey: "homeMode")
        defaults.set(true, forKey: "nativeGuide.initialized.v1"); defaults.set(true, forKey: "nativeGuide.completed.v1")
        XCTAssertTrue(ProfileSettingsStore.shared.saveCurrent())
        let account = SimklAccountStore.forOwner(binding.personalOwner); try account.load(); XCTAssertNil(account.session)
        return (binding, profile)
    }
}
