import XCTest
@testable import Harbor

@MainActor private final class PosterSettingsMemory: ProfileSettingsPersistence {
    var state: ProfileSettingsState?
    func readProfileSettings() throws -> ProfileSettingsState? { state }
    func writeProfileSettings(_ value: ProfileSettingsState) throws { state = value }
}

final class PosterCardConfigurationTests: XCTestCase {
    func testDesktopSizeAndCornerOptionsKeepTheirNearestChoiceAndStableTieOrder() {
        XCTAssertEqual(PosterCardConfiguration.sizes.map(\.scale), [0.8, 0.9, 1, 1.15, 1.3, 1.5])
        XCTAssertEqual(PosterCardConfiguration.radii.map(\.value), [0, 6, 12, 18, 28])
        XCTAssertEqual(PosterCardConfiguration(scale: 1.3).sizeIndex, 4)
        XCTAssertEqual(PosterCardConfiguration(radius: 3).radiusLabel, "Sharp")
        XCTAssertEqual(PosterCardConfiguration(radius: 40).radiusLabel, "Pill")
        XCTAssertEqual(PosterCardConfiguration(style: "tv").aspectRatio, 16.0 / 9)
        XCTAssertEqual(PosterCardConfiguration(style: "tv").rowWidth(), 318)
        XCTAssertEqual(PosterCardConfiguration(scale: 1.5).gridMinimum(availableWidth: 700), 159)
        XCTAssertEqual(PosterCardConfiguration(style: "tv", scale: 1.5).gridMinimum(availableWidth: 288), 288)
        XCTAssertEqual(PosterCardConfiguration(style: "tv", scale: 1.5).gridMinimum(availableWidth: 700), 477)
    }
    func testInvalidStoredChoicesRecoverAndTheSelectedQualityControlsTheDecodeBudget() {
        let invalid = PosterCardConfiguration(style: "future", logoPosition: "future", scale: .nan, radius: .infinity, effect: "future", quality: "future")
        XCTAssertEqual(invalid.style, .poster); XCTAssertEqual(invalid.logoPosition, .bottomStart)
        XCTAssertEqual(invalid.scale, 1); XCTAssertEqual(invalid.radius, 12); XCTAssertEqual(invalid.effect, .off); XCTAssertEqual(invalid.quality, .high)
        let balanced = PosterCardConfiguration(quality: "balanced").pixels(width: 300, displayScale: 3)
        let high = PosterCardConfiguration(quality: "high").pixels(width: 300, displayScale: 3)
        XCTAssertLessThan(balanced, high); XCTAssertLessThanOrEqual(high, 2_048)
        XCTAssertEqual(PosterCardConfiguration(quality: "max").pixels(width: 300, displayScale: 3), 0)
        XCTAssertEqual(PosterCardConfiguration(radius: -1).radius, 0)
    }
    @MainActor func testAllSixCardSettingsFollowSharedAndIndependentProfileSnapshotsAndReopen() throws {
        let suite = "owned-poster-settings-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let memory = PosterSettingsMemory(), store = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: false)
        let choices: [String: Any] = ["rowCardStyle": "tv", "tvCardLogoPos": "center", "posterScale": 1.3, "posterRadius": 28.0, "posterEffect": "fade", "posterQuality": "balanced"]
        for (key, value) in choices { defaults.set(value, forKey: key) }; XCTAssertTrue(store.saveCurrent())
        try store.activate(owner: "private", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertEqual(defaults.string(forKey: "rowCardStyle"), "tv")
        defaults.set("poster", forKey: "rowCardStyle"); defaults.set(0.0, forKey: "posterRadius"); defaults.set("max", forKey: "posterQuality"); XCTAssertTrue(store.saveCurrent())
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertEqual(defaults.string(forKey: "rowCardStyle"), "tv"); XCTAssertEqual(defaults.double(forKey: "posterRadius"), 28)
        XCTAssertEqual(defaults.string(forKey: "posterQuality"), "balanced"); XCTAssertEqual(defaults.string(forKey: "tvCardLogoPos"), "center")
        XCTAssertEqual(defaults.double(forKey: "posterScale"), 1.3); XCTAssertEqual(defaults.string(forKey: "posterEffect"), "fade")
        let reopened = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try reopened.activate(owner: "private", sharedOwner: "shared", migrateLegacy: false)
        XCTAssertEqual(defaults.string(forKey: "rowCardStyle"), "poster"); XCTAssertEqual(defaults.double(forKey: "posterRadius"), 0)
        XCTAssertEqual(defaults.string(forKey: "posterQuality"), "max")
    }
}
