import XCTest
@testable import Harbor

@MainActor final class MusicBillboardPublicTests: XCTestCase {
    func testActualPublicHot100KeepsItsPublishedDateRankAndOriginalCatalogIdentity() async throws {
        let scope = PluginExecutionScope(owner: "owned-public-billboard", activation: UUID())
        let client = MusicBillboardClient(scope: scope, currentScope: { scope }); defer { client.dispose() }
        let ranking = try await client.ranking("hot-100")
        XCTAssertEqual(ranking.chartId, "hot-100"); XCTAssertNotNil(ranking.dateValue)
        XCTAssertEqual(ranking.entries.first?.rank, 1); XCTAssertEqual(ranking.entries.count, 100)
        XCTAssertEqual(Set(ranking.entries.map(\.rank)).count, 100)
        for entry in ranking.entries {
            guard case .track(let track) = entry.item else { XCTFail("Hot 100 is a track chart"); return }
            XCTAssertTrue(track.id.hasPrefix("billboard:hot-100:")); XCTAssertEqual(track.connectorId, "catalog"); XCTAssertNil(track.playbackUrl)
        }
    }
}
