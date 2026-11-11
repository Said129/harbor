import XCTest
@testable import Harbor

final class F3SearchGenreTests: XCTestCase {
    func testGenreTilesAreTheMovieGenres() {
        XCTAssertFalse(SearchRanking.genreSuggestions.isEmpty)
        XCTAssertEqual(SearchRanking.genreSuggestions, CustomCalendar.movieGenres.map(\.0))
    }

    func testEveryGenreTileIsRecognizedAsAGenreSearch() {
        for name in SearchRanking.genreSuggestions {
            XCTAssertEqual(SearchRanking.intent(name), .genre(name: name, isSeries: false))
        }
    }
}
