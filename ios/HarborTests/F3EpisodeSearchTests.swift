import XCTest
@testable import Harbor

final class F3EpisodeSearchTests: XCTestCase {
    private func episode(_ season: Int, _ number: Int, _ name: String?) -> Episode {
        Episode(id: "e\(season)x\(number)", season: season, episode: number, name: name, title: nil, thumbnail: nil, overview: nil,
                released: nil, imdbID: nil, imdbSeason: nil, imdbEpisode: nil)
    }

    func testEmptyQueryMatchesEveryEpisode() {
        XCTAssertTrue(EpisodeSearchRules.matches(episode(1, 1, "Pilot"), query: "   "))
    }

    func testTitleMatchIgnoresCaseAndAccents() {
        let item = episode(1, 2, "Café Night")
        XCTAssertTrue(EpisodeSearchRules.matches(item, query: "cafe"))
        XCTAssertTrue(EpisodeSearchRules.matches(item, query: "NIGHT"))
        XCTAssertFalse(EpisodeSearchRules.matches(item, query: "pilot"))
    }

    func testSeasonAndEpisodeCodesMatchOnlyThatEpisode() {
        let item = episode(2, 5, "Other")
        XCTAssertTrue(EpisodeSearchRules.matches(item, query: "2x5"))
        XCTAssertTrue(EpisodeSearchRules.matches(item, query: "S2E5"))
        XCTAssertFalse(EpisodeSearchRules.matches(item, query: "1x5"))
    }

    func testCoordinatesReadOnlyTheCodeForms() {
        XCTAssertNil(EpisodeSearchRules.coordinates("pilot"))
        XCTAssertNil(EpisodeSearchRules.coordinates("2"))
        XCTAssertEqual(EpisodeSearchRules.coordinates("s10e12")?.season, 10)
        XCTAssertEqual(EpisodeSearchRules.coordinates("s10e12")?.episode, 12)
    }
}
