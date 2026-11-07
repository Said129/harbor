import XCTest
@testable import Harbor

/// Desktop's Wrapped aggregation (`src/lib/wrapped/aggregate.ts`, `archetype.ts`).
final class WatchStatisticsTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        return utc.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    /// The Nth day after 1 January 2026 at noon, in UTC.
    private func dayOffset(_ offset: Int) -> Date {
        utc.date(byAdding: .day, value: offset, to: date(2026, 1, 1)) ?? date(2026, 1, 1)
    }

    private func event(_ id: String, _ kind: WatchStatistics.Kind, _ when: Date, title: String? = nil) -> WatchStatistics.Event {
        WatchStatistics.Event(id: id, title: title ?? id, kind: kind, watchedAt: when, poster: nil)
    }

    private func stats(_ events: [WatchStatistics.Event]) -> WatchStatistics {
        WatchStatistics.make(events: events, source: .local, year: nil, calendar: utc)
    }

    func testHoursUseDesktopMinutesAndRoundToTheNearestHour() {
        // One movie (115 min) plus one episode (42 min) is 157 min, which rounds to 3 hours.
        let one = stats([event("tt1", .movie, dayOffset(0)), event("tt2", .series, dayOffset(1))])
        XCTAssertEqual(one.estimatedHours, 3)
        XCTAssertEqual(one.totalPlays, 2)
        XCTAssertEqual(one.totalTitles, 2)

        // Two movies (230 min) plus three episodes (126 min) is 356 min, which is 5.93 hours and rounds to 6.
        let two = stats([
            event("tt1", .movie, dayOffset(0)), event("tt2", .movie, dayOffset(1)),
            event("tt3", .series, dayOffset(2)), event("tt3", .series, dayOffset(3)), event("tt3", .series, dayOffset(4)),
        ])
        XCTAssertEqual(two.estimatedHours, 6)
        XCTAssertEqual(two.totalTitles, 3)
    }

    func testSplitCountsMoviesSeriesAndAnimeSeparately() {
        let result = stats([
            event("tt1", .movie, dayOffset(0)),
            event("tt2", .series, dayOffset(1)),
            event("kitsu:1", .anime, dayOffset(2)),
            event("kitsu:1", .anime, dayOffset(3)),
        ])
        XCTAssertEqual(result.split, WatchStatistics.Split(movies: 1, series: 1, anime: 2))
    }

    func testTopTitlesSortByCountAndKeepFirstSeenOrderOnTies() {
        // a, b, c, a, b, c, c: counts a=2, b=2, c=3. c ranks first, then a (seen before b).
        let result = stats([
            event("a", .series, dayOffset(0)), event("b", .series, dayOffset(1)), event("c", .series, dayOffset(2)),
            event("a", .series, dayOffset(3)), event("b", .series, dayOffset(4)), event("c", .series, dayOffset(5)),
            event("c", .series, dayOffset(6)),
        ])
        XCTAssertEqual(result.topTitles.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(result.topTitles.map(\.count), [3, 2, 2])
    }

    func testLongestBingeKeepsTheEarliestDayOnATie() {
        let result = stats([
            event("a", .series, date(2026, 1, 1, 9)), event("b", .series, date(2026, 1, 1, 20)),
            event("c", .series, date(2026, 1, 2, 9)), event("d", .series, date(2026, 1, 2, 20)),
            event("e", .series, date(2026, 1, 3, 9)),
        ])
        XCTAssertEqual(result.longestBinge?.count, 2)
        XCTAssertEqual(result.longestBinge?.day, utc.startOfDay(for: date(2026, 1, 1)))
        XCTAssertEqual(result.days.map(\.count), [2, 2, 1])
    }

    func testFirstAndLastPlayAreFoundRegardlessOfInputOrder() {
        let result = stats([
            event("late", .movie, dayOffset(9), title: "Late"),
            event("early", .movie, dayOffset(0), title: "Early"),
            event("middle", .series, dayOffset(4), title: "Middle"),
        ])
        XCTAssertEqual(result.firstPlay?.title, "Early")
        XCTAssertEqual(result.lastPlay?.title, "Late")
    }

    func testArchetypeAnimeIsChosenAtExactlyHalf() {
        let result = stats([event("kitsu:1", .anime, dayOffset(0)), event("tt2", .series, dayOffset(1))])
        XCTAssertEqual(result.archetype, .anime)
    }

    func testArchetypeBingerNeedsEightInOneDay() {
        let eight = stats((0..<8).map { event("s\($0)", .series, date(2026, 1, 1, 8 + $0)) })
        XCTAssertEqual(eight.archetype, .binger(8))
        XCTAssertEqual(eight.archetype.blurbVariables, ["n": "8"])

        let seven = stats((0..<7).map { event("s\($0)", .series, date(2026, 1, 1, 8 + $0)) })
        XCTAssertEqual(seven.archetype, .seriesSlayer)
    }

    func testArchetypeFilmBuffIsChosenAtExactlySixtyPercentMovies() {
        let result = stats([
            event("m1", .movie, dayOffset(0)), event("m2", .movie, dayOffset(1)), event("m3", .movie, dayOffset(2)),
            event("s1", .series, dayOffset(3)), event("s2", .series, dayOffset(4)),
        ])
        XCTAssertEqual(result.archetype, .filmBuff)
    }

    func testArchetypeSeriesSlayerIsChosenAtExactlySixtyPercentSeries() {
        let result = stats([
            event("s1", .series, dayOffset(0)), event("s2", .series, dayOffset(1)), event("s3", .series, dayOffset(2)),
            event("m1", .movie, dayOffset(3)), event("m2", .movie, dayOffset(4)),
        ])
        XCTAssertEqual(result.archetype, .seriesSlayer)
    }

    func testArchetypeExplorerNeedsSixtyTitles() {
        let balanced = (0..<60).map { index in
            event("t\(index)", index % 2 == 0 ? .movie : .series, dayOffset(index))
        }
        XCTAssertEqual(stats(balanced).archetype, .explorer)

        let fiftyNine = Array(balanced.prefix(59))
        XCTAssertEqual(stats(fiftyNine).archetype, .wellRounded)
    }

    func testYearViewCountsOnlyThatYearAndFallsBackToAllTimeWhenEmpty() {
        let lastYear = [event("old", .movie, date(2025, 6, 1)), event("older", .series, date(2025, 7, 1))]

        let scoped = WatchStatistics.make(events: lastYear, source: .local, year: 2026, calendar: utc)
        XCTAssertEqual(scoped.totalPlays, 0)
        XCTAssertNil(scoped.firstPlay)

        let resolved = WatchStatistics.resolved(events: lastYear, source: .local, year: 2026, calendar: utc)
        XCTAssertEqual(resolved.totalPlays, 2)
        XCTAssertNil(resolved.year)
    }

    func testEmptyInputGivesZeroedStatistics() {
        let result = stats([])
        XCTAssertEqual(result.totalPlays, 0)
        XCTAssertEqual(result.totalTitles, 0)
        XCTAssertEqual(result.estimatedHours, 0)
        XCTAssertTrue(result.topTitles.isEmpty)
        XCTAssertTrue(result.days.isEmpty)
        XCTAssertNil(result.longestBinge)
        XCTAssertNil(result.firstPlay)
        XCTAssertEqual(result.archetype, .wellRounded)
    }
}
