import XCTest
@testable import Harbor

final class WatchedByInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareAnotherOwnedWatcherAndAnExplicitDefaultOnAFreshGuest() async throws {
        try await PageContinuationInterfaceSeedTests.prepareOwnedHistory()
        let context = AppProfileContext.shared
        let binding = try XCTUnwrap(context.binding), active = try XCTUnwrap(context.profiles.active)
        let watcher = try context.profiles.create(name: "Owned watcher", avatar: "/avatars/harbor_animal_02.webp")
        let preferences = ProfileSettingsStore.shared
        try preferences.activate(owner: binding.settingsOwner, sharedOwner: binding.sharedSettingsOwner, migrateLegacy: true, legacyTMDB: { nil })
        try preferences.setLaunchPreferences(ProfileLaunchPreferences(interval: .never, defaultID: active.id), sharedOwner: binding.sharedSettingsOwner, expectedOwner: binding.settingsOwner)
        let watches = ProfilePreferences.forOwner(binding.identityOwner).cloud.watchedBy
        XCTAssertNil(watches.account)
        try watches.record(mediaID: "owned-anime-layout", profileID: watcher.id)
        XCTAssertEqual(watches.value.watcher(mediaID: "owned-anime-layout", activeID: active.id, profiles: context.profiles.profiles)?.id, watcher.id)
        XCTAssertEqual(context.profiles.active?.id, active.id)
    }
}
