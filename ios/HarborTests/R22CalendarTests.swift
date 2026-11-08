import XCTest
@testable import Harbor

/// Desktop's library release calendar rules: candidate selection, the episode skip and the duplicate key.
/// Fake titles only: no network, no UI.
final class R22CalendarTests: XCTestCase {
    private func entry(_ id: String, type: String = "series", name: String? = nil, mtime: Double = 0, temp: Bool = false, removed: Bool = false) -> LibraryCalendarEntry {
        LibraryCalendarEntry(media: Media(id: id, type: type, name: name ?? "Title " + id), type: type, mtime: mtime, temp: temp, removed: removed)
    }

    func testRemovedTitlesAreLeftOutAndTempTitlesSortLast() {
        let selected = LibraryCalendarCandidates.select([
            entry("tt1", mtime: 100, temp: true),
            entry("tt2", mtime: 50),
            entry("tt3", mtime: 10, removed: true),
            entry("tt4", mtime: 80),
        ])
        XCTAssertEqual(selected.map(\.id), ["tt4", "tt2", "tt1"])
    }

    func testSameTitleMergesTempMtimeAndNameFallback() {
        let selected = LibraryCalendarCandidates.select([
            entry("tt1", name: "", mtime: 10, temp: true),
            entry("tt1", name: "Real Name", mtime: 40, temp: false),
            entry("tt2", mtime: 30, temp: true),
            entry("tt2", mtime: 5, temp: true),
        ])
        XCTAssertEqual(selected.map(\.id), ["tt1", "tt2"])
        XCTAssertEqual(selected.first?.name, "Real Name")
    }

    func testSeriesAndMoviesAreCappedAtEightyEach() {
        let series = (0..<85).map { entry("tt\($0)", mtime: Double($0)) }
        let movies = (0..<85).map { entry("mv\($0)", type: "movie", mtime: Double($0)) }
        let selected = LibraryCalendarCandidates.select(series + movies)
        XCTAssertEqual(selected.filter { $0.type == "series" }.count, 80)
        XCTAssertEqual(selected.filter { $0.type == "movie" }.count, 80)
        XCTAssertEqual(selected.first?.id, "tt84")
    }

    func testSeasonZeroEpisodeZeroIsSkipped() {
        XCTAssertTrue(LibraryCalendarCandidates.skipsEpisode(season: 0, number: 0))
        XCTAssertFalse(LibraryCalendarCandidates.skipsEpisode(season: 0, number: 1))
        XCTAssertFalse(LibraryCalendarCandidates.skipsEpisode(season: nil, number: 0))
    }

    func testDedupeKeyNormalizesTheShowName() {
        let first = LibraryCalendarCandidates.dedupeKey(showName: "The Show: Part 1!", season: 1, episode: 2, day: "d1")
        let second = LibraryCalendarCandidates.dedupeKey(showName: "the show part 1", season: 1, episode: 2, day: "d1")
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, LibraryCalendarCandidates.dedupeKey(showName: "the show part 1", season: 1, episode: 3, day: "d1"))
    }

    func testDedupeKeepsTheFirstItemPerKey() {
        let kept = LibraryCalendarCandidates.dedupe(["a1", "a2", "b1"]) { String($0.prefix(1)) }
        XCTAssertEqual(kept, ["a1", "b1"])
    }

    func testMoodRailsStartWithTheActiveSeasonalRail() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 9))!
        let rails = MoodRails.pick(now: now, calendar: calendar)
        // Nov 8 is in the autumn seasonal, which also marks slow-burn as used. Morning rotates by the seed 20261108 % 5 = 3.
        XCTAssertEqual(rails.count, 6)
        XCTAssertEqual(rails.first?.id, "mood-autumn")
        XCTAssertEqual(rails.first?.title, "Cozy Autumn Nights")
        XCTAssertEqual(rails[1].title, "This Morning · Animation Night")
        XCTAssertEqual(rails[1].parameters["with_genres"], "16")
    }

    func testDailySeedAndRotate() {
        XCTAssertEqual(MoodRails.dailySeed(year: 2026, month: 11, day: 8), 20_261_108)
        XCTAssertEqual(MoodRails.rotate([1, 2, 3], by: -1), [3, 1, 2])
        XCTAssertEqual(MoodRails.rotate([1, 2, 3], by: 4), [2, 3, 1])
    }
}
