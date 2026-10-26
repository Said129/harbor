import XCTest
@testable import Harbor

@MainActor private final class TitleArtworkSettingsMemory: ProfileSettingsPersistence {
    var state: ProfileSettingsState?
    func readProfileSettings() throws -> ProfileSettingsState? { state }
    func writeProfileSettings(_ value: ProfileSettingsState) throws { state = value }
}

@MainActor final class TitleArtworkPreferencesTests: XCTestCase {
    func testGalleryOverridesAndImageLanguageOrderPersistIndependentlyAcrossProfileSwitchesAndReopen() throws {
        let suite = "owned-title-artwork-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let memory = TitleArtworkSettingsMemory(), store = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: false)
        let preferences = TitleArtworkPreferences(defaults: defaults)
        for kind in TitleArtworkKind.allCases { XCTAssertTrue(preferences.toggle(kind, id: "owned-title", url: "https://owned.invalid/" + kind.rawValue + ".png")) }
        defaults.set(["Japanese", "Original", "English"], forKey: "tmdbImageLangs"); XCTAssertTrue(store.saveCurrent())
        try store.activate(owner: "private", sharedOwner: "shared", migrateLegacy: false); preferences.reloadPreferences()
        XCTAssertTrue(preferences.toggle(.logo, id: "owned-title", url: "https://owned.invalid/private.png"))
        XCTAssertTrue(preferences.toggle(.poster, id: "owned-title", url: "https://owned.invalid/poster.png"))
        defaults.set(["Spanish", "Original"], forKey: "tmdbImageLangs"); XCTAssertTrue(store.saveCurrent())
        try store.activate(owner: "shared", sharedOwner: "shared", migrateLegacy: false); preferences.reloadPreferences()
        let media = Media(id: "owned-title", type: "movie", name: "Owned title")
        let displayed = preferences.applying(to: media)
        XCTAssertEqual(displayed.id, media.id); XCTAssertEqual(displayed.name, media.name)
        XCTAssertEqual(displayed.poster, "https://owned.invalid/poster.png"); XCTAssertEqual(displayed.background, "https://owned.invalid/backdrop.png")
        XCTAssertEqual(displayed.logo, "https://owned.invalid/logo.png")
        var resolvedPlayback = Media(id: "tt1234567", type: "movie", name: media.name); resolvedPlayback.artworkSourceID = media.id
        let artworkForPlayback = preferences.applying(to: resolvedPlayback)
        XCTAssertEqual(artworkForPlayback.id, "tt1234567"); XCTAssertEqual(artworkForPlayback.logo, displayed.logo)
        XCTAssertEqual(defaults.stringArray(forKey: "tmdbImageLangs"), ["Japanese", "Original", "English"])
        let reopenedStore = ProfileSettingsStore(defaults: defaults, persistence: memory)
        try reopenedStore.activate(owner: "private", sharedOwner: "shared", migrateLegacy: false)
        let reopened = TitleArtworkPreferences(defaults: defaults)
        XCTAssertEqual(reopened.value(.logo, id: media.id), "https://owned.invalid/private.png"); XCTAssertNil(reopened.value(.poster, id: media.id))
        XCTAssertEqual(defaults.stringArray(forKey: "tmdbImageLangs"), ["Spanish", "Original"])
        XCTAssertFalse(reopened.toggle(.logo, id: media.id, url: "https://person:secret@owned.invalid/wrong.png"))
        XCTAssertEqual(reopened.value(.logo, id: media.id), "https://owned.invalid/private.png")
    }
}
