import XCTest
@testable import Harbor

final class PosterAppearanceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedPosterCatalogWithDesktopDefaultsAndNoPersonalAccount() async throws {
        try await CustomSourceInterfaceSeedTests.prepareOwnedSources()
        ThemePreferences.shared.reset()
        XCTAssertTrue(ProfileSettingsStore.shared.saveCurrent())
        XCTAssertNil(AppProfileContext.shared.configuration?.account)
    }
}
