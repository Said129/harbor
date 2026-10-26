import XCTest
@testable import Harbor

final class CardArtworkInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedPinnedArtworkAndImageLanguagesOnAFreshGuest() async throws {
        try await CustomSourceInterfaceSeedTests.prepareOwnedSources()
        let defaults = UserDefaults.standard, preferences = TitleArtworkPreferences.shared
        defaults.set("tv", forKey: "rowCardStyle"); defaults.set(1.0, forKey: "posterScale")
        defaults.set(["English", "Original"], forKey: "tmdbImageLangs")
        for (kind, file) in [(TitleArtworkKind.logo, "logo.png"), (.poster, "edited.png"), (.backdrop, "cover.png")] {
            XCTAssertTrue(preferences.toggle(kind, id: "owned-source-title-1", url: "http://127.0.0.1:18734/" + file))
        }
        XCTAssertTrue(ProfileSettingsStore.shared.saveCurrent())
        XCTAssertNil(AppProfileContext.shared.configuration?.account)
    }
}
