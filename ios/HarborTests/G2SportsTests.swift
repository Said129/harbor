import XCTest
@testable import Harbor

final class G2SportsTests: XCTestCase {
    private func makeLeague() -> SportsLeague {
        SportsLeague(id: "EPL", title: "Premier League", path: "soccer/eng.1", group: "soccer", logo: nil)
    }

    private func makeEvent(_ id: String, state: String, date: Date) -> SportsEvent {
        SportsEvent(id: id, eventID: id, league: makeLeague(), title: id, date: date, state: state, status: "", sides: [], venue: "", broadcasts: [], link: nil)
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testNCAASoccerLeaguesUseDesktopLabels() {
        // Desktop's English catalog translates "Soccer" to "Football", so its English label for these leagues reads Football;
        // the sport word comes from the catalog so every other language gets its own word for soccer.
        XCTAssertEqual(SportsRules.leagueTitle(id: "NCAAMSOCCER", title: "NCAA Men's Football", language: "en"), "NCAA Men's Football")
        XCTAssertEqual(SportsRules.leagueTitle(id: "NCAAWSOCCER", title: "NCAA Women's Football", language: "en"), "NCAA Women's Football")
        XCTAssertEqual(SportsRules.leagueTitle(id: "NCAAF", title: "NCAA Football", language: "en"), "NCAA Football")
    }

    func testFinishedGamesSortNewestFirstAfterLiveAndUpcoming() {
        let oldFinal = makeEvent("post-old", state: "post", date: date("2026-11-01T20:00:00Z"))
        let newFinal = makeEvent("post-new", state: "post", date: date("2026-11-03T20:00:00Z"))
        let laterUpcoming = makeEvent("pre-late", state: "pre", date: date("2026-11-06T20:00:00Z"))
        let soonUpcoming = makeEvent("pre-soon", state: "pre", date: date("2026-11-05T20:00:00Z"))
        let live = makeEvent("in", state: "in", date: date("2026-11-04T20:00:00Z"))
        let ordered = SportsRules.ordered([oldFinal, laterUpcoming, newFinal, live, soonUpcoming])
        XCTAssertEqual(ordered.map(\.id), ["in", "pre-soon", "pre-late", "post-new", "post-old"])
    }

    func testLiveRangeCoversYesterdayAndToday() {
        XCTAssertEqual(SportsRules.liveRange(today: "20260101"), "20251231-20260101")
        XCTAssertEqual(SportsRules.liveRange(today: "20261108"), "20261107-20261108")
    }

    func testRequestDateUsesRangeForLiveScopeAndToday() {
        XCTAssertEqual(SportsRules.requestDate(selected: "20261105", today: "20261108", state: "all"), "20261105")
        XCTAssertEqual(SportsRules.requestDate(selected: "20261105", today: "20261108", state: "in"), "20261107-20261108")
        XCTAssertEqual(SportsRules.requestDate(selected: "20261108", today: "20261108", state: "post"), "20261107-20261108")
    }

    func testIncludesKeepsSelectedDayAndLiveGamesOnly() {
        // Live games from yesterday still show on today's view.
        XCTAssertTrue(SportsRules.includes(eventDay: "20261107", eventState: "in", selected: "20261108", today: "20261108", state: "all"))
        // Finished games from yesterday do not.
        XCTAssertFalse(SportsRules.includes(eventDay: "20261107", eventState: "post", selected: "20261108", today: "20261108", state: "all"))
        XCTAssertTrue(SportsRules.includes(eventDay: "20261107", eventState: "post", selected: "20261107", today: "20261108", state: "all"))
        // Live scope shows live games whatever their day.
        XCTAssertTrue(SportsRules.includes(eventDay: "20261104", eventState: "in", selected: "20261108", today: "20261108", state: "in"))
        XCTAssertFalse(SportsRules.includes(eventDay: "20261108", eventState: "pre", selected: "20261108", today: "20261108", state: "in"))
    }

    func testTimelineKindFollowsDesktopOrder() {
        XCTAssertEqual(SportsTimelineKind.classify("Goal"), .goal)
        XCTAssertEqual(SportsTimelineKind.classify("Own Goal"), .goal)
        XCTAssertEqual(SportsTimelineKind.classify("Yellow Card"), .yellowCard)
        XCTAssertEqual(SportsTimelineKind.classify("Red Card"), .redCard)
        XCTAssertEqual(SportsTimelineKind.classify("Substitution"), .substitution)
        XCTAssertEqual(SportsTimelineKind.classify("Penalty - Missed"), .other)
        XCTAssertEqual(SportsTimelineKind.classify(""), .other)
    }

    func testReminderLeadOptionsAndDefaultMatchDesktop() {
        XCTAssertEqual(SportsRules.reminderLeads, [5, 15, 60, 1440])
        XCTAssertEqual(SportsRules.defaultReminderLead, 15)
    }

    func testReminderResyncsWhenStartTimeMoves() {
        let fireAt1945 = date("2026-11-08T19:45:00Z")
        let movedGame = makeEvent("moved", state: "pre", date: date("2026-11-08T21:00:00Z"))
        let sameGame = makeEvent("same", state: "pre", date: date("2026-11-08T20:00:00Z"))
        let finished = makeEvent("done", state: "post", date: date("2026-11-08T21:00:00Z"))
        XCTAssertTrue(SportsRules.reminderNeedsResync(scheduledFire: fireAt1945, event: movedGame, minutes: 15))
        XCTAssertFalse(SportsRules.reminderNeedsResync(scheduledFire: fireAt1945, event: sameGame, minutes: 15))
        XCTAssertFalse(SportsRules.reminderNeedsResync(scheduledFire: fireAt1945, event: finished, minutes: 15))
        XCTAssertFalse(SportsRules.reminderNeedsResync(scheduledFire: nil, event: movedGame, minutes: 15))
    }
}
