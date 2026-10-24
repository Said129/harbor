import XCTest
@testable import Harbor

final class DesktopAnimeRowTests: XCTestCase {
    func testAllTwentyOriginalRowsRetainRequestsDecadesGenresRankFlagsAndGemsDoublePagination() throws {
        let asset = try DesktopAnimeRows.read()
        let fixture = try reference()
        let rows = fixture["rows"].array
        XCTAssertEqual(asset.rows.count, 20); XCTAssertEqual(AnimeService.definitions().count, 24)
        XCTAssertEqual(asset.rows.map(\.key), rows.compactMap { $0["key"].string })
        for (row, expected) in zip(asset.rows, rows) {
            XCTAssertEqual(row.ranked, expected["ranked"] == .bool(true)); XCTAssertEqual(row.pool, expected["pool"].string)
            XCTAssertEqual(row.rail.id, "anime-" + row.key); XCTAssertEqual(row.rail.ranked, row.ranked)
            for (plan, raw) in zip(row.plans, expected["plans"].array) {
                let request = try plan.request(page: 3)
                XCTAssertEqual(request.path, raw["path"].string)
                XCTAssertEqual(request.parameters["page"], String(3 * plan.factor + plan.offset))
                XCTAssertEqual(request.parameters["limit"], "25")
                for (key, value) in raw["parameters"].objectValue { XCTAssertEqual(request.parameters[key], value.string) }
            }
        }
        let eras = asset.rows.filter { $0.pool == "era" }; XCTAssertEqual(eras.count, 4)
        XCTAssertEqual(eras.first?.plans.first?.parameters["start_date"], "2020-01-01")
        XCTAssertEqual(eras.last?.plans.first?.parameters["end_date"], "1999-12-31")
        let genres = asset.rows.filter { $0.pool == "genre" }; XCTAssertEqual(genres.count, 8)
        XCTAssertEqual(genres.first?.plans.first?.parameters["genres"], "1")
        let gems = try XCTUnwrap(asset.rows.first { $0.key == "gems" })
        XCTAssertEqual(try gems.plans.map { try $0.request(page: 3).parameters["page"] }, ["5", "6"])
    }
    func testOriginalGemsOracleRejectsSequelsInsufficientRatingsAndPopularityWithoutDroppingEligibleDuplicates() throws {
        let asset = try DesktopAnimeRows.read(), fixture = try reference()
        let row = try XCTUnwrap(asset.rows.first { $0.key == "gems" })
        let raw = fixture["gems"]["input"].array
        let result = try asset.filtered(raw + raw, for: row)
        XCTAssertEqual(result.compactMap { $0["mal_id"].integer }, fixture["gems"]["expectedIDs"].array.compactMap(\.integer))
        var rejected = raw[0].objectValue; rejected["members"] = .integer(350001)
        let duplicates = try asset.filtered([.object(rejected), raw[0]], for: row)
        XCTAssertEqual(duplicates.count, 1, "The original marks a duplicate only after all eligibility checks pass")
        XCTAssertThrowsError(try row.plans[0].request(page: 0)); XCTAssertThrowsError(try row.plans[0].request(page: 101))
        XCTAssertThrowsError(try asset.filtered(Array(repeating: raw[0], count: 101), for: row))
    }
    func testNewSupportedDirectMALRankingsKeepCorrectSourceParametersAndOffsets() throws {
        let airing = try MALPublicCatalog.request("anime-top-airing", page: 2)
        XCTAssertEqual(airing.path, "/anime/ranking"); XCTAssertEqual(airing.parameters["ranking_type"], "airing"); XCTAssertEqual(airing.parameters["offset"], "25")
        let all = try MALPublicCatalog.request("anime-all-time", page: 3)
        XCTAssertEqual(all.parameters["ranking_type"], "all"); XCTAssertEqual(all.parameters["offset"], "50")
    }
    private func reference() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "anime-row-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
}
