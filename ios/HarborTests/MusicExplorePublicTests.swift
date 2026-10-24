import XCTest
@testable import Harbor

@MainActor final class MusicExplorePublicTests: XCTestCase {
    func testActualPublicGenreChartUsesOriginalCatalogReferencesWithoutPlaybackClaims() async throws {
        let scope = PluginExecutionScope(owner: "owned-public-music", activation: UUID())
        let actual = MusicExploreClient(scope: scope, currentScope: { scope })
        defer { actual.dispose() }
        let result = try await actual.selection(152)
        XCTAssertFalse(result.tracks.isEmpty)
        XCTAssertTrue(result.tracks.allSatisfy { $0.id.hasPrefix("deezer:track:") && $0.connectorId == "catalog" && $0.playbackUrl == nil })
        XCTAssertTrue(result.artists.allSatisfy { $0.id.hasPrefix("artist|catalog|deezer:artist:") })
    }
}
