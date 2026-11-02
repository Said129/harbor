import Foundation
import XCTest
@testable import Harbor

@MainActor private final class OwnedMusicSettingsDisk: ProfileSettingsPersistence {
    var state: ProfileSettingsState?
    func readProfileSettings() throws -> ProfileSettingsState? { state }
    func writeProfileSettings(_ value: ProfileSettingsState) throws { state = value }
}

@MainActor final class MusicPreferencesTests: XCTestCase {
    func testPreferredMusicSourceSurvivesRestartWithoutLeakingAcrossIndependentProfiles() throws {
        let name = "owned-music-preferences-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name)), disk = OwnedMusicSettingsDisk()
        defer { defaults.removePersistentDomain(forName: name) }
        let key = "harbor.music.preferredSource", store = ProfileSettingsStore(defaults: defaults, persistence: disk)
        try store.activate(owner: "owned-a", sharedOwner: "owned-a", migrateLegacy: true)
        defaults.set("subsonic", forKey: key)
        try store.activate(owner: "owned-b", sharedOwner: "owned-b", migrateLegacy: false)
        XCTAssertNil(defaults.string(forKey: key))
        defaults.set("soundcloud", forKey: key)
        try store.activate(owner: "owned-a", sharedOwner: "owned-a", migrateLegacy: false)
        XCTAssertEqual(defaults.string(forKey: key), "subsonic")
        XCTAssertTrue(store.saveCurrent())
        let reopened = ProfileSettingsStore(defaults: defaults, persistence: disk)
        try reopened.activate(owner: "owned-b", sharedOwner: "owned-b", migrateLegacy: false)
        XCTAssertEqual(defaults.string(forKey: key), "soundcloud")
    }
}
