import XCTest
@testable import Harbor

@MainActor private final class DisplaySettingsMemory: ProfileSettingsPersistence {
    var state: ProfileSettingsState?
    func readProfileSettings() throws -> ProfileSettingsState? { state }
    func writeProfileSettings(_ value: ProfileSettingsState) throws { state = value }
}

@MainActor final class DisplaySettingsTests: XCTestCase {
    func testHidePosterTitlesDefaultsToShowingTitles() throws {
        let suite = "display-settings-default-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(defaults.object(forKey: "hidePosterTitles"))
        XCTAssertFalse(defaults.bool(forKey: "hidePosterTitles"))
        XCTAssertTrue(ProfileSettingsStore.keys.contains("hidePosterTitles"))
    }

    func testCaptionRuleShowsTitleOnlyForPosterCardsWhenNotHidden() {
        XCTAssertTrue(PosterBehaviorPolicy.showsCaption(true, style: .poster, hidesTitles: false))
        XCTAssertFalse(PosterBehaviorPolicy.showsCaption(true, style: .poster, hidesTitles: true))
        XCTAssertFalse(PosterBehaviorPolicy.showsCaption(true, style: .tv, hidesTitles: false))
        XCTAssertFalse(PosterBehaviorPolicy.showsCaption(false, style: .poster, hidesTitles: false))
        XCTAssertFalse(PosterBehaviorPolicy.showsCaption(false, style: .tv, hidesTitles: true))
    }

    func testHidePosterTitlesSurvivesAProfileSaveAndReopen() throws {
        let suite = "display-settings-profile-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let memory = DisplaySettingsMemory(), store = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: false)
        defaults.set(true, forKey: "hidePosterTitles")
        XCTAssertTrue(store.saveCurrent())
        defaults.set(false, forKey: "hidePosterTitles")
        let reopened = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try reopened.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertTrue(defaults.bool(forKey: "hidePosterTitles"))
    }
}
