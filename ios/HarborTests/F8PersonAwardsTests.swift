import XCTest
@testable import Harbor

/// Person awards (Desktop's `useAwards(person.imdbId)` on views/person.tsx): the person's IMDb id and the query it may use.
final class F8PersonAwardsTests: XCTestCase {
    func testPersonIDIsRecognisedOnlyWithTheNmPrefix() {
        XCTAssertTrue(TitleAwardParser.isPersonID("nm0000138"))
        XCTAssertFalse(TitleAwardParser.isPersonID("tt0111161"))
        XCTAssertFalse(TitleAwardParser.isPersonID("nm"))
    }

    func testPersonQueryIsOnlyBuiltWhenThePersonPageAllowsIt() {
        XCTAssertNil(TitleAwardParser.query(imdbID: "nm0000138", nominations: false))
        let win = TitleAwardParser.query(imdbID: "nm0000138", nominations: false, allowsPerson: true)
        XCTAssertNotNil(win)
        XCTAssertTrue(win?.contains("\"nm0000138\"") ?? false)
        XCTAssertFalse(win?.contains("IMDB_ID") ?? true)
        XCTAssertNotNil(TitleAwardParser.query(imdbID: "nm0000138", nominations: true, allowsPerson: true))
    }

    func testPersonQueryStillRejectsMalformedIDs() {
        XCTAssertNil(TitleAwardParser.query(imdbID: "nm\"x", nominations: false, allowsPerson: true))
        XCTAssertNil(TitleAwardParser.query(imdbID: "xx0000138", nominations: false, allowsPerson: true))
    }

    func testProfileReadsTheImdbIDFromExternalIDs() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"id": 7, "name": "Actor A", "external_ids": {"imdb_id": "nm0000138"}}"#.utf8))
        let profile = try XCTUnwrap(TMDBPeople.profile(value, englishName: nil))
        XCTAssertEqual(profile.imdbID, "nm0000138")
    }

    func testProfileWithoutAnImdbIDHasNone() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"id": 7, "name": "Actor A", "external_ids": {"imdb_id": ""}}"#.utf8))
        let profile = try XCTUnwrap(TMDBPeople.profile(value, englishName: nil))
        XCTAssertNil(profile.imdbID)
    }
}
