import XCTest
@testable import Harbor

/// My Simkl (Desktop's `calendarSource` "simkl"): which Simkl titles become calendar candidates, and when the source is offered.
@MainActor
final class F8CalendarSimklTests: XCTestCase {
    private func parsed(_ text: String, kind: SimklMediaKind) throws -> SimklListItem? {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        return SimklListItem.parse(value, kind: kind)
    }

    func testWatchingShowWithImdbBecomesASeriesCandidate() throws {
        let item = try XCTUnwrap(parsed(#"{"show": {"title": "Show A", "ids": {"simkl": 1, "imdb": "tt1234567"}}, "status": "watching"}"#, kind: .show))
        let entries = LibraryCalendarCandidates.entries(simkl: [item])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.media.id, "tt1234567")
        XCTAssertEqual(entries.first?.type, "series")
    }

    func testPlanToWatchMovieWithTmdbBecomesAMovieCandidate() throws {
        let item = try XCTUnwrap(parsed(#"{"movie": {"title": "Film C", "ids": {"simkl": 3, "tmdb": "550"}}, "status": "plantowatch"}"#, kind: .movie))
        let entries = LibraryCalendarCandidates.entries(simkl: [item])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.media.id, "tmdb:movie:550")
        XCTAssertEqual(entries.first?.type, "movie")
    }

    func testCompletedTitlesAreLeftOut() throws {
        let item = try XCTUnwrap(parsed(#"{"show": {"title": "Show B", "ids": {"simkl": 2, "imdb": "tt7654321"}}, "status": "completed"}"#, kind: .show))
        XCTAssertTrue(LibraryCalendarCandidates.entries(simkl: [item]).isEmpty)
    }

    func testTitlesWithOnlyASimklIdAreLeftOut() throws {
        let item = try XCTUnwrap(parsed(#"{"show": {"title": "Show D", "ids": {"simkl": 4}}, "status": "watching"}"#, kind: .show))
        XCTAssertTrue(LibraryCalendarCandidates.entries(simkl: [item]).isEmpty)
    }

    func testCalendarSourceFollowsTheProfile() {
        XCTAssertTrue(ProfileSettingsStore.keys.contains("calendar.source"), "Desktop's calendarSource is a profile setting")
    }

    func testMySimklIsOfferedOnlyWithASimklAccount() {
        XCTAssertFalse(CalendarSource.offered(traktConnected: true, simklConnected: false).contains(.simkl))
        XCTAssertTrue(CalendarSource.offered(traktConnected: false, simklConnected: true).contains(.simkl))
        XCTAssertEqual(CalendarSource.simkl.rawValue, "simkl")
    }
}
