import XCTest
@testable import Harbor

final class CardArtworkPolicyTests: XCTestCase {
    private func reference() throws -> JSONValue {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "card-artwork-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
    }
    func testImageLanguageOrderAndLogoScoresMatchAllOriginalDesktopReferenceCases() throws {
        let reference = try reference()
        XCTAssertEqual(reference["actual_original_typescript_executed"], .bool(true))
        let cases = reference["policy_cases"].array; XCTAssertEqual(cases.count, 7)
        for entry in cases {
            let policy = CardArtworkPolicy(languages: entry["languages"].array.compactMap(\.string), metadataLanguage: entry["metadata"].string ?? "", originalLanguage: entry["original"].string)
            XCTAssertEqual(policy.parameter, entry["expected"]["parameter"].string)
            XCTAssertEqual(policy.localizes, entry["expected"]["localizes"] == .bool(true))
            XCTAssertEqual(policy.logo(entry["logos"].array), entry["expected"]["logo"].string)
        }
    }
    func testAnimeArtSearchMatchesOriginalTitleYearAndJapaneseAnimationRankingWithoutBorrowingAnotherTitle() throws {
        let reference = try reference(), cases = reference["anime_cases"].array
        XCTAssertEqual(cases.count, 6); XCTAssertEqual(reference["provider_network_requests"], .integer(0))
        for entry in cases {
            let hit = AnimeCardArtworkMatch.best(entry["results"].array, name: entry["name"].string ?? "", year: entry["year"].string, kind: entry["kind"].string ?? "tv", exact: entry["exact"] == .bool(true))
            XCTAssertEqual(hit?["id"].integer, entry["expected_id"].integer, entry["name"].string ?? "")
        }
    }
}
