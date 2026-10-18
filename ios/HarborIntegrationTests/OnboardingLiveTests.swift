import XCTest
@testable import Harbor

final class OnboardingLiveTests: XCTestCase {
    func testNativeTasteSetupLoadsActualPublicTitlesWithCoversWithoutBundledKeys() async throws {
        let configuration = MetadataConfiguration(tmdbKey: "", region: "US", language: "en-US", translateTitles: true)
        let titles = try await OnboardingContent().taste(configuration: configuration, service: HarborService())
        XCTAssertGreaterThanOrEqual(titles.count, 16); XCTAssertLessThanOrEqual(titles.count, 40)
        XCTAssertEqual(Set(titles.map(\.id)).count, titles.count)
        XCTAssertTrue(titles.allSatisfy { $0.poster?.hasPrefix("https://") == true })
        XCTAssertTrue(titles.contains { $0.type == "movie" }); XCTAssertTrue(titles.contains { $0.type == "series" })
        let first = try XCTUnwrap(titles.first?.poster)
        let bytes = try await ArtworkStore.shared.data(first)
        XCTAssertGreaterThan(bytes.count, 100, "Use an actual provider cover through the native image producer")
    }
}
