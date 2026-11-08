import XCTest
@testable import Harbor

/// The R21 detail helpers (episode runtime and New badge, random episode, season marking, Simkl watched keys, title logo),
/// checked with a fixed UTC calendar and no network or UI.
final class R21DetailTests: XCTestCase {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "UTC")!
        return value
    }()
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))! }

    func testDaysFromTodayCountsCalendarDays() {
        XCTAssertEqual(EpisodeDetailPolicy.daysFromToday("2026-11-08", calendar: calendar, now: now), 0)
        XCTAssertEqual(EpisodeDetailPolicy.daysFromToday("2026-11-10T20:00:00Z", calendar: calendar, now: now), 2)
        XCTAssertEqual(EpisodeDetailPolicy.daysFromToday("2026-11-05", calendar: calendar, now: now), -3)
        XCTAssertNil(EpisodeDetailPolicy.daysFromToday(nil, calendar: calendar, now: now))
        XCTAssertNil(EpisodeDetailPolicy.daysFromToday("2026/11/08", calendar: calendar, now: now))
    }

    func testNewBadgeCoversThreeDaysAfterTheAirDate() {
        XCTAssertTrue(EpisodeDetailPolicy.isNew("2026-11-08", calendar: calendar, now: now))
        XCTAssertTrue(EpisodeDetailPolicy.isNew("2026-11-05", calendar: calendar, now: now))
        XCTAssertFalse(EpisodeDetailPolicy.isNew("2026-11-04", calendar: calendar, now: now))
        XCTAssertFalse(EpisodeDetailPolicy.isNew("2026-11-09", calendar: calendar, now: now))
        XCTAssertFalse(EpisodeDetailPolicy.isNew(nil, calendar: calendar, now: now))
    }

    func testRuntimeMinutesRoundsOnlyPositiveRuntimes() {
        XCTAssertNil(EpisodeDetailPolicy.runtimeMinutes(nil))
        XCTAssertNil(EpisodeDetailPolicy.runtimeMinutes(0))
        XCTAssertNil(EpisodeDetailPolicy.runtimeMinutes(.nan))
        XCTAssertEqual(EpisodeDetailPolicy.runtimeMinutes(44.6), 45)
    }

    func testRandomEpisodePrefersAiredNumberedEpisodes() {
        let episodes = [
            Episode(id: "special", season: 0, episode: 1, released: "2026-01-01"),
            Episode(id: "aired", season: 1, episode: 1, released: "2026-01-01"),
            Episode(id: "future", season: 2, episode: 1, released: "2027-01-01"),
        ]
        XCTAssertEqual(EpisodeDetailPolicy.randomEpisode(episodes, calendar: calendar, now: now, roll: { _ in 0 })?.id, "aired")
        XCTAssertEqual(EpisodeDetailPolicy.randomEpisode(episodes, calendar: calendar, now: now, roll: { $0 - 1 })?.id, "aired")
        let upcoming = [Episode(id: "later", season: 1, episode: 1, released: "2027-01-01")]
        XCTAssertEqual(EpisodeDetailPolicy.randomEpisode(upcoming, calendar: calendar, now: now, roll: { _ in 0 })?.id, "later")
        XCTAssertNil(EpisodeDetailPolicy.randomEpisode([Episode(id: "special", season: 0, episode: 1)], calendar: calendar, now: now))
    }

    func testMarkSeasonIgnoresUnairedEpisodesWhenMarkingWatched() {
        let aired = Episode(id: "a", season: 1, episode: 1, released: "2026-11-01")
        let upcoming = Episode(id: "u", season: 1, episode: 2, released: "2027-01-01")
        XCTAssertFalse(SeasonWatchPolicy.allWatched([], watched: [], now: now))
        XCTAssertTrue(SeasonWatchPolicy.allWatched([aired, upcoming], watched: ["1:1"], now: now))
        XCTAssertFalse(SeasonWatchPolicy.allWatched([aired, upcoming], watched: [], now: now))
        XCTAssertEqual(SeasonWatchPolicy.targets([aired, upcoming], marking: true, now: now).map(\.id), ["a"])
        XCTAssertEqual(SeasonWatchPolicy.targets([aired, upcoming], marking: false, now: now).map(\.id), ["a", "u"])
    }

    func testAiredOnlyKeepsUndatedEpisodesBeforeTheLastAiredOne() {
        let undated = Episode(id: "n", season: 1, episode: 1)
        let aired = Episode(id: "a", season: 1, episode: 2, released: "2026-11-01")
        let upcoming = Episode(id: "u", season: 1, episode: 3, released: "2027-01-01")
        XCTAssertEqual(SeasonWatchPolicy.airedOnly([undated, aired, upcoming], now: now).map(\.id), ["n", "a"])
        XCTAssertEqual(SeasonWatchPolicy.airedOnly([aired, undated, upcoming], now: now).map(\.id), ["a"])
        XCTAssertEqual(SeasonWatchPolicy.airedOnly([undated], now: now).map(\.id), ["n"])
    }

    func testSimklWatchedKeysComeFromTheMatchingTitleOnly() {
        let ids = SimklIdentifiers(.object(["imdb": .string("tt1234567")]))
        let item = SimklListItem(kind: .show, ids: ids, title: "Show", status: .watching, watchedEpisodes: ["1:2", "2:1"])
        var snapshot = SimklLibrarySnapshot()
        snapshot.items[item.id] = item
        XCTAssertEqual(SimklWatchedEpisodes.keys(in: snapshot, for: Media(id: "tt1234567", type: "series", name: "Show")), ["1:2", "2:1"])
        XCTAssertEqual(SimklWatchedEpisodes.keys(in: snapshot, for: Media(id: "tt7654321", type: "series", name: "Other")), [])
    }

    func testTitleLogoFollowsDesktopOrder() {
        XCTAssertEqual(TitleLogoPolicy.logo(pinned: "p", season: "s", resolved: "r", fallback: "f"), "p")
        XCTAssertEqual(TitleLogoPolicy.logo(pinned: nil, season: "s", resolved: "r", fallback: "f"), "s")
        XCTAssertEqual(TitleLogoPolicy.logo(pinned: nil, season: "", resolved: "r", fallback: "f"), "r")
        XCTAssertEqual(TitleLogoPolicy.logo(pinned: nil, season: nil, resolved: nil, fallback: "f"), "f")
        XCTAssertNil(TitleLogoPolicy.logo(pinned: "", season: nil, resolved: nil, fallback: nil))
    }
}
