import XCTest
@testable import Harbor

/// Desktop's library release alerts (`webhook-engine.ts`, `calendar.ts` `fireWebhook`): the dedupe key, the fourteen-day window,
/// the lead time, the text, and the scheduler that owns only its own pending requests.
@MainActor
final class EpisodeAlertsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func settings(enabled: Bool = true, lead: Int = 15, movies: Bool = true, series: Bool = true, anime: Bool = true) -> EpisodeAlertSettings {
        EpisodeAlertSettings(enabled: enabled, leadMinutes: lead, movies: movies, series: series, anime: anime, library: true)
    }

    private func episode(_ at: Date, season: Int = 1, number: Int = 2, title: String = "Show", hasTime: Bool = true, kind: EpisodeAlertKind = .series) -> EpisodeAlertEvent {
        EpisodeAlertEvent(id: "tt0000001:\(season):\(number)", title: title, season: season, episode: number, date: at, hasTime: hasTime, kind: kind)
    }

    private func movie(_ at: Date) -> EpisodeAlertEvent {
        EpisodeAlertEvent(id: "tt0000009", title: "Film", season: nil, episode: nil, date: at, hasTime: true, kind: .movie)
    }

    func testTimedReleaseFiresLeadMinutesBeforeWithDesktopKey() {
        let release = now.addingTimeInterval(3 * 3600)
        let planned = EpisodeAlertPlanner.plan([episode(release)], settings: settings(lead: 15), now: now, calendar: utcCalendar)
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.identifier, "library:desktop:tt0000001:1:2")
        XCTAssertEqual(planned.first?.fireDate, release.addingTimeInterval(-15 * 60))
        XCTAssertEqual(planned.first?.title, "📺 Show S01E02")
        XCTAssertTrue(planned.first?.body.hasSuffix(CalendarTime.timeLabel(release, calendar: utcCalendar)) ?? false)
    }

    func testEpisodeTitleIsAppendedAsDesktopDoes() {
        var event = episode(now.addingTimeInterval(3 * 3600))
        event.episodeTitle = "Pilot"
        let planned = EpisodeAlertPlanner.plan([event], settings: settings(), now: now, calendar: utcCalendar)
        XCTAssertEqual(planned.first?.title, "📺 Show S01E02: Pilot")
    }

    func testAnimeAndMovieUseTheirOwnIconsAndNoEpisodeLabel() {
        let release = now.addingTimeInterval(3 * 3600)
        let anime = EpisodeAlertPlanner.plan([episode(release, kind: .anime)], settings: settings(), now: now, calendar: utcCalendar)
        XCTAssertEqual(anime.first?.title, "🍙 Show S01E02")
        let film = EpisodeAlertPlanner.plan([movie(release)], settings: settings(), now: now, calendar: utcCalendar)
        XCTAssertEqual(film.first?.title, "🎬 Film")
        XCTAssertEqual(film.first?.identifier, "library:desktop:tt0000009")
    }

    func testDateOnlyReleaseFiresAtNineOnItsDay() {
        let day = utcCalendar.startOfDay(for: utcCalendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let planned = EpisodeAlertPlanner.plan([episode(day, hasTime: false)], settings: settings(lead: 60), now: now, calendar: utcCalendar)
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.fireDate, utcCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: day))
        XCTAssertFalse(planned.first?.body.contains("·") ?? true)
    }

    func testReleasesAlreadyPastOrLeadTimeAlreadyStartedAreNotScheduled() {
        let past = now.addingTimeInterval(-3600)
        let soon = now.addingTimeInterval(10 * 60)
        let planned = EpisodeAlertPlanner.plan([episode(past, number: 1), episode(soon, number: 2)], settings: settings(lead: 15), now: now, calendar: utcCalendar)
        XCTAssertTrue(planned.isEmpty)
    }

    func testReleasesOutsideTheFourteenDayWindowAreNotScheduled() {
        let later = now.addingTimeInterval(15 * 86_400)
        let planned = EpisodeAlertPlanner.plan([episode(later)], settings: settings(), now: now, calendar: utcCalendar)
        XCTAssertTrue(planned.isEmpty)
        let inside = EpisodeAlertPlanner.plan([episode(now.addingTimeInterval(10 * 86_400))], settings: settings(), now: now, calendar: utcCalendar)
        XCTAssertEqual(inside.count, 1)
    }

    func testAlreadyAlertedIdentifiersAreNotPlannedAgain() {
        let release = now.addingTimeInterval(3 * 3600)
        let planned = EpisodeAlertPlanner.plan([episode(release)], settings: settings(lead: 0), now: now, calendar: utcCalendar,
                                               alreadyAlerted: ["library:desktop:tt0000001:1:2"])
        XCTAssertTrue(planned.isEmpty)
    }

    func testLibraryAnimationGenreCountsAsAnime() {
        var media = Media(id: "tt0000042", type: "series", name: "Cartoon")
        media.genres = ["Animation", "Comedy"]
        let release = ReleaseEvent(media: media, episode: Episode(id: "e1", season: 1, episode: 2), date: now.addingTimeInterval(3600))
        let alert = EpisodeAlertRefresh.alertEvent(release, calendar: utcCalendar)
        XCTAssertEqual(alert?.kind, .anime)
        XCTAssertEqual(alert?.id, "tt0000042:1:2")
    }

    func testDateOnlyLibraryReleaseKeepsItsDay() {
        var media = Media(id: "tt0000043", type: "series", name: "Show")
        media.genres = ["Drama"]
        let release = ReleaseEvent(media: media, episode: Episode(id: "e2", season: 2, episode: 4, released: "2026-11-20"), date: now)
        let alert = EpisodeAlertRefresh.alertEvent(release, calendar: utcCalendar)
        XCTAssertEqual(alert?.kind, .series)
        XCTAssertEqual(alert?.hasTime, false)
        XCTAssertEqual(alert?.date, CalendarTime.startOfDay("2026-11-20", calendar: utcCalendar))
    }

    func testKindSwitchesLeaveOutTheirReleases() {
        let release = now.addingTimeInterval(3 * 3600)
        let planned = EpisodeAlertPlanner.plan([movie(release), episode(release, kind: .anime), episode(release, number: 3)],
                                               settings: settings(movies: false, series: true, anime: false), now: now, calendar: utcCalendar)
        XCTAssertEqual(planned.map(\.identifier), ["library:desktop:tt0000001:1:3"])
    }

    func testDisabledPlansNothing() {
        let planned = EpisodeAlertPlanner.plan([episode(now.addingTimeInterval(3 * 3600))], settings: settings(enabled: false), now: now, calendar: utcCalendar)
        XCTAssertTrue(planned.isEmpty)
    }

    func testPlanIsCappedAtSixtyEarliestFirst() {
        let events = (0..<70).map { index in
            EpisodeAlertEvent(id: "tt\(index):1:1", title: "Show", season: 1, episode: 1, date: now.addingTimeInterval(3600 + Double(index) * 60),
                              hasTime: true, kind: .series)
        }
        let planned = EpisodeAlertPlanner.plan(events, settings: settings(lead: 0), now: now, calendar: utcCalendar)
        XCTAssertEqual(planned.count, EpisodeAlertPlanner.maxPending)
        XCTAssertEqual(planned.first?.identifier, "library:desktop:tt0:1:1")
        XCTAssertEqual(planned.last?.identifier, "library:desktop:tt59:1:1")
        let fires = planned.map(\.fireDate)
        XCTAssertEqual(fires, fires.sorted())
    }

    func testPreferenceDefaultsMatchDesktop() {
        let settings = EpisodeAlertSettings()
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.leadMinutes, 15)
        XCTAssertTrue(settings.movies && settings.series && settings.anime && settings.library)
    }

    func testSchedulerReplacesOnlyItsOwnPendingRequests() async throws {
        let center = FakeEpisodeAlertCenter()
        center.pending = ["library:desktop:old:1:1", "harbor-sports-abc-def"]
        let scheduler = EpisodeAlertScheduler(center: center)
        let planned = EpisodeAlertPlanner.plan([episode(now.addingTimeInterval(3 * 3600))], settings: settings(), now: now, calendar: utcCalendar)
        try await scheduler.replace(with: planned)
        XCTAssertEqual(center.removed, ["library:desktop:old:1:1"])
        XCTAssertEqual(center.added.map(\.identifier), ["library:desktop:tt0000001:1:2"])
        XCTAssertEqual(center.pending, ["harbor-sports-abc-def"])
    }

    func testRemoveAllKeepsOtherPendingRequests() async {
        let center = FakeEpisodeAlertCenter()
        center.pending = ["library:desktop:tt0000001:1:2", "harbor-sports-abc-def"]
        let scheduler = EpisodeAlertScheduler(center: center)
        await scheduler.removeAll()
        XCTAssertEqual(center.pending, ["harbor-sports-abc-def"])
    }

    func testDeniedAuthorizationIsReported() async {
        let center = FakeEpisodeAlertCenter()
        center.granted = false
        let scheduler = EpisodeAlertScheduler(center: center)
        let granted = await scheduler.requestAuthorization()
        XCTAssertFalse(granted)
    }
}

/// Records what the scheduler asks of the system notification center.
@MainActor
private final class FakeEpisodeAlertCenter: EpisodeAlertNotificationCenter {
    var granted = true
    var authorized = true
    var pending: [String] = []
    var added: [PlannedEpisodeAlert] = []
    var removed: [String] = []
    var delivered: [String] = []

    func isAuthorized() async -> Bool { authorized }
    func requestAuthorization() async -> Bool { granted }
    func pendingIdentifiers() async -> [String] { pending }
    func deliveredIdentifiers() async -> [String] { delivered }
    func add(_ alert: PlannedEpisodeAlert) async throws { added.append(alert) }
    func remove(identifiers: [String]) {
        removed += identifiers
        pending.removeAll { identifiers.contains($0) }
    }
}
