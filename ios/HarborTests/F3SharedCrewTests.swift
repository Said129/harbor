import XCTest
@testable import Harbor

final class F3SharedCrewTests: XCTestCase {
    func testQueryNeedsAnIMDbID() {
        XCTAssertNil(SharedCrewService.query(imdbID: "tmdb:movie:603"))
        XCTAssertNil(SharedCrewService.request(imdbID: ""))
    }

    func testQueryUsesTheIDAndTheMinimumShared() {
        let text = SharedCrewService.query(imdbID: "tt0133093") ?? ""
        XCTAssertTrue(text.contains("wdt:P345 \"tt0133093\""))
        XCTAssertTrue(text.contains("HAVING(COUNT(DISTINCT ?person) >= 3)"))
    }

    func testRequestCarriesTheQueryAsJSON() {
        let request = SharedCrewService.request(imdbID: "tt0133093")
        let url = request?.url?.absoluteString ?? ""
        XCTAssertTrue(url.hasPrefix("https://query.wikidata.org/sparql?"))
        XCTAssertTrue(url.contains("format=json"))
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Accept"), "application/sparql-results+json")
    }

    func testParsesRowsAndKeepsOnlyFilmsWithThreeSharedCrew() {
        let json = """
        {"results":{"bindings":[
          {"otherLabel":{"value":"The Matrix Reloaded"},"tmdb":{"value":"604"},"shared":{"value":"4"},"who":{"value":"Lana Wachowski | Keanu Reeves"}},
          {"otherLabel":{"value":"Two Shared"},"tmdb":{"value":"605"},"shared":{"value":"2"},"who":{"value":"Someone"}},
          {"otherLabel":{"value":"http://bad"},"tmdb":{"value":"606"},"shared":{"value":"5"}},
          {"otherLabel":{"value":"No Tmdb"},"shared":{"value":"5"}}
        ]}}
        """
        let films = SharedCrewService.films(from: Data(json.utf8))
        XCTAssertEqual(films.count, 2)
        XCTAssertEqual(films.first?.metaId, "tmdb:movie:604")
        XCTAssertEqual(films.first?.who, ["Lana Wachowski", "Keanu Reeves"])
        XCTAssertEqual(SharedCrewRules.films(films).map(\.name), ["The Matrix Reloaded"])
    }

    func testInvalidJSONGivesNoFilms() {
        XCTAssertTrue(SharedCrewService.films(from: Data("not json".utf8)).isEmpty)
    }

    func testCrewLineUsesDesktopWording() {
        XCTAssertNil(SharedCrewRules.line(count: 0) { key, _ in key })
        XCTAssertEqual(SharedCrewRules.line(count: 1) { key, _ in key }, "Shares crew with 1 other film")
        let plural = SharedCrewRules.line(count: 3) { key, values in key.replacingOccurrences(of: "{n}", with: values["n"] ?? "") }
        XCTAssertEqual(plural, "Shares crew with 3 other films")
    }
}
