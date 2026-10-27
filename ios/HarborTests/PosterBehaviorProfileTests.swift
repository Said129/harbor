import XCTest
@testable import Harbor

@MainActor private final class PosterBehaviorSettingsMemory: ProfileSettingsPersistence {
    var state: ProfileSettingsState?
    func readProfileSettings() throws -> ProfileSettingsState? { state }
    func writeProfileSettings(_ value: ProfileSettingsState) throws { state = value }
}

@MainActor final class PosterBehaviorProfileTests: XCTestCase {
    func testBehaviorSettingsAreIsolatedPerProfileAndSurviveReopeningTheSettingsStore() throws {
        let suite = "owned-poster-behavior-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let memory = PosterBehaviorSettingsMemory(), store = ProfileSettingsStore(defaults: defaults, persistence: memory)
        let toggles = ["posterFocusedCard", "posterBackdropExpansion", "posterDockMagnification"]
        XCTAssertTrue(Set(toggles + ["posterDockTransitionMs"]).isSubset(of: ProfileSettingsStore.keys))
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: false)
        for key in toggles { defaults.set(true, forKey: key) }; defaults.set(1_250.0, forKey: "posterDockTransitionMs"); XCTAssertTrue(store.saveCurrent())
        try store.activate(owner: "private", sharedOwner: "shared", migrateLegacy: false)
        // An independent profile initially forks the shared document, as Desktop does.
        for key in toggles { XCTAssertTrue(defaults.bool(forKey: key)); defaults.set(false, forKey: key) }
        XCTAssertEqual(defaults.double(forKey: "posterDockTransitionMs"), 1_250)
        defaults.set(350.0, forKey: "posterDockTransitionMs"); XCTAssertTrue(store.saveCurrent())
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: false)
        for key in toggles { XCTAssertTrue(defaults.bool(forKey: key)) }; XCTAssertEqual(defaults.double(forKey: "posterDockTransitionMs"), 1_250)
        let reopened = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try reopened.activate(owner: "private", sharedOwner: "shared", migrateLegacy: false)
        for key in toggles { XCTAssertFalse(defaults.bool(forKey: key)) }; XCTAssertEqual(defaults.double(forKey: "posterDockTransitionMs"), 350)
    }
}
