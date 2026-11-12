import XCTest
@testable import Harbor

/// The MAL score read for an anime detail page (Desktop's `jikanScore`).
final class F8MALScoreTests: XCTestCase {
    private func decode(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testScoreReadsTheSingleTitleReply() throws {
        let value = try decode(#"{"data": {"mal_id": 5114, "score": 8.7}}"#)
        XCTAssertEqual(AnimeService.malScore(value), "8.7")
    }

    func testMissingOrZeroScoreIsNil() throws {
        let zero: JSONValue = try decode(#"{"data": {"mal_id": 1, "score": 0}}"#)
        let missing: JSONValue = try decode(#"{"data": {"mal_id": 1}}"#)
        XCTAssertNil(AnimeService.malScore(zero))
        XCTAssertNil(AnimeService.malScore(missing))
    }

    func testScoreAboveTenIsNil() throws {
        let high: JSONValue = try decode(#"{"data": {"score": 11.2}}"#)
        XCTAssertNil(AnimeService.malScore(high))
    }
}
