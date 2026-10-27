import XCTest
@testable import Harbor

final class SimklPlaybackImportInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareSourceControlsOnAnOwnedGuestWithoutTrackerCredentials() throws {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else { XCTFail("Refuse configured account"); return }
        let context = AppProfileContext.shared; try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil, context.configuration?.account == nil,
              let binding = context.binding else { XCTFail("Refuse configured household"); return }
        try context.save(HouseholdSourceAccount(account: nil, guestAddons: []))
        try ProfileSettingsStore.shared.activate(owner: binding.settingsOwner, sharedOwner: binding.sharedSettingsOwner, migrateLegacy: true, legacyTMDB: { nil })
        let defaults = UserDefaults.standard
        defaults.set(ContinueWatchingSources.defaultValue, forKey: "cwSources"); defaults.set(false, forKey: "cwPerProfile")
        defaults.set("en", forKey: "uiLanguage"); defaults.set("classic", forKey: "homeMode")
        defaults.set(true, forKey: "nativeGuide.initialized.v1"); defaults.set(true, forKey: "nativeGuide.completed.v1")
        XCTAssertTrue(ProfileSettingsStore.shared.saveCurrent())
        let account = SimklAccountStore.forOwner(binding.personalOwner); try account.load(); XCTAssertNil(account.session)
    }
}
