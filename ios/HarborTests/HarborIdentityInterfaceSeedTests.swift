import XCTest
@testable import Harbor

final class HarborIdentityInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareAnOwnedGuestWithoutAnIdentitySession() async throws {
        try await PageContinuationInterfaceSeedTests.prepareOwnedHistory()
        let context = AppProfileContext.shared, binding = try XCTUnwrap(context.binding), active = try XCTUnwrap(context.profiles.active)
        XCTAssertFalse(ProfilePreferences.forOwner(binding.identityOwner).cloud.signedIn)
        let settings = ProfileSettingsStore.shared
        try settings.activate(owner: binding.settingsOwner, sharedOwner: binding.sharedSettingsOwner, migrateLegacy: true, legacyTMDB: { nil })
        try settings.setLaunchPreferences(ProfileLaunchPreferences(interval: .never, defaultID: active.id), sharedOwner: binding.sharedSettingsOwner, expectedOwner: binding.settingsOwner)
    }
}
