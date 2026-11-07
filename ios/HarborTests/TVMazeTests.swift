import XCTest
@testable import Harbor

/// Desktop's TVMaze client (`src/lib/providers/tvmaze.ts`) with canned replies: lookup, parsing, caches and airtimes.
final class TVMazeTests: XCTestCase {
    private let showURL = "https://api.tvmaze.com/lookup/shows?imdb=tt0903747"
    private let episodesURL = "https://api.tvmaze.com/shows/169/episodes"
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private var newYorkCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private let showText = """
    {"id":169,"name":"Breaking Bad","genres":["Drama","Crime"],"image":{"medium":"https://static.tvmaze.com/m.jpg","original":"https://static.tvmaze.com/o.jpg"}}
    """

    private let episodesText = """
    [
      {"season":1,"number":1,"name":"Pilot","airdate":"2008-01-20","airstamp":"2008-01-20T22:00:00-05:00","image":{"medium":"m.jpg","original":"o.jpg"},"summary":"<p>Walter <b>White</b></p>"},
      {"season":1,"number":2,"name":"Cat's in the Bag...","airdate":"2008-01-27","airstamp":null,"image":null,"summary":null},
      {"season":2,"number":1,"name":"Seven Thirty-Seven","airdate":"","summary":null}
    ]
    """

    private func script(withShow: Bool = true, withEpisodes: Bool = true) throws -> TVMazeScript {
        var replies: [String: JSONValue] = [:]
        if withShow { replies[showURL] = try json(showText) }
        if withEpisodes { replies[episodesURL] = try json(episodesText) }
        return TVMazeScript(replies)
    }

    func testLookupReadsIdNameAndOriginalImage() throws {
        let show = try XCTUnwrap(TVMazeRules.show(try json(showText)))
        XCTAssertEqual(show.id, 169)
        XCTAssertEqual(show.name, "Breaking Bad")
        XCTAssertEqual(show.image, "https://static.tvmaze.com/o.jpg")
        XCTAssertFalse(show.isAnime)
    }

    func testAnimeIsAGenreMatchedWithoutCase() throws {
        let anime = try json(#"{"id":7,"name":"Show","genres":["Action","ANIME"],"image":null}"#)
        let show = try XCTUnwrap(TVMazeRules.show(anime))
        XCTAssertTrue(show.isAnime)
        XCTAssertNil(show.image)
    }

    func testShowWithoutIdIsNil() throws {
        XCTAssertNil(TVMazeRules.show(try json(#"{"name":"No id"}"#)))
    }

    func testLookupURLsByIMDbAndTVDB() {
        XCTAssertEqual(TVMazeRules.lookupURL(imdb: "tt0903747")?.absoluteString, showURL)
        XCTAssertEqual(TVMazeRules.lookupURL(tvdb: 81189)?.absoluteString, "https://api.tvmaze.com/lookup/shows?thetvdb=81189")
    }

    func testEpisodesKeepDatedRowsAndStripSummaryTags() throws {
        let episodes = TVMazeRules.episodes(try json(episodesText))
        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(episodes[0].summary, "Walter White")
        XCTAssertEqual(episodes[0].image, "o.jpg")
        XCTAssertNil(episodes[1].image)
        XCTAssertEqual(episodes[1].airdate, "2008-01-27")
    }

    func testAirtimeWithAirstampUsesTheDeviceDayAndHour() throws {
        let pilot = try XCTUnwrap(TVMazeRules.episodes(try json(episodesText)).first)
        let airtime = TVMazeRules.airtime(pilot, calendar: utcCalendar)
        XCTAssertEqual(airtime.date, "2008-01-21")
        XCTAssertEqual(airtime.time, "3:00 AM")
        XCTAssertEqual(airtime.atMs, 1_200_884_400_000)
    }

    func testAirtimeInNewYorkKeepsTheNetworkDay() throws {
        let pilot = try XCTUnwrap(TVMazeRules.episodes(try json(episodesText)).first)
        let airtime = TVMazeRules.airtime(pilot, calendar: newYorkCalendar)
        XCTAssertEqual(airtime.date, "2008-01-20")
        XCTAssertEqual(airtime.time, "10:00 PM")
    }

    func testAirtimeWithoutAirstampKeepsOnlyTheAirdate() throws {
        let second = TVMazeRules.episodes(try json(episodesText))[1]
        let airtime = TVMazeRules.airtime(second, calendar: utcCalendar)
        XCTAssertEqual(airtime, TVMazeAirtime(date: "2008-01-27", time: nil, atMs: nil))
    }

    func testShowLookupIsCachedAfterTheFirstReply() async throws {
        let counter = try script()
        let service = TVMazeService(transport: ScriptedTVMaze(script: counter))
        let first = await service.lookupShow(imdb: "tt0903747")
        let second = await service.lookupShow(imdb: "tt0903747")
        XCTAssertEqual(first?.id, 169)
        XCTAssertEqual(second, first)
        let lookups = await counter.count(showURL)
        XCTAssertEqual(lookups, 1)
    }

    func testShowLookupByTVDBIdIsCachedSeparately() async throws {
        let tvdbURL = "https://api.tvmaze.com/lookup/shows?thetvdb=81189"
        let counter = try script()
        let reply = try json(showText)
        await counter.set(tvdbURL, reply)
        let service = TVMazeService(transport: ScriptedTVMaze(script: counter))
        let byTVDB = await service.lookupShow(tvdb: 81189)
        _ = await service.lookupShow(tvdb: 81189)
        XCTAssertEqual(byTVDB?.id, 169)
        let lookups = await counter.count(tvdbURL)
        XCTAssertEqual(lookups, 1)
    }

    func testMissingShowIsNotCached() async throws {
        let counter = try script(withShow: false)
        let service = TVMazeService(transport: ScriptedTVMaze(script: counter))
        let missed = await service.lookupShow(imdb: "tt0903747")
        XCTAssertNil(missed)
        let reply = try json(showText)
        await counter.set(showURL, reply)
        let found = await service.lookupShow(imdb: "tt0903747")
        XCTAssertEqual(found?.name, "Breaking Bad")
        let lookups = await counter.count(showURL)
        XCTAssertEqual(lookups, 2)
    }

    func testEpisodesAreReusedForSixHours() async throws {
        let counter = try script()
        let service = TVMazeService(transport: ScriptedTVMaze(script: counter))
        _ = await service.episodes(showID: 169, now: start)
        let later = await service.episodes(showID: 169, now: start.addingTimeInterval(5 * 3_600))
        XCTAssertEqual(later.count, 2)
        let fetches = await counter.count(episodesURL)
        XCTAssertEqual(fetches, 1)
    }

    func testFailedRefreshAnswersTheStaleEpisodeList() async throws {
        let counter = try script()
        let service = TVMazeService(transport: ScriptedTVMaze(script: counter))
        _ = await service.episodes(showID: 169, now: start)
        await counter.set(episodesURL, nil)
        let stale = await service.episodes(showID: 169, now: start.addingTimeInterval(7 * 3_600))
        XCTAssertEqual(stale.map(\.name), ["Pilot", "Cat's in the Bag..."])
    }

    func testFailedFirstFetchIsEmpty() async throws {
        let counter = try script(withEpisodes: false)
        let service = TVMazeService(transport: ScriptedTVMaze(script: counter))
        let episodes = await service.episodes(showID: 169, now: start)
        XCTAssertTrue(episodes.isEmpty)
    }

    func testCalendarHookFindsTheAirtimeByIMDbId() async throws {
        let counter = try script()
        let service = TVMazeService(transport: ScriptedTVMaze(script: counter))
        let airtime = await service.airtime(imdb: "tt0903747", season: 1, number: 1, calendar: utcCalendar, now: start)
        XCTAssertEqual(airtime?.date, "2008-01-21")
        XCTAssertEqual(airtime?.time, "3:00 AM")
        let missing = await service.airtime(imdb: "tt0903747", season: 9, number: 1, calendar: utcCalendar, now: start)
        XCTAssertNil(missing)
    }

    func testUpcomingKeepsOnlyEpisodesInTheWindow() async throws {
        let counter = try script()
        let service = TVMazeService(transport: ScriptedTVMaze(script: counter))
        let result = await service.upcoming(imdb: "tt0903747", inWindow: { $0 >= "2008-01-25" && $0 <= "2008-02-10" }, now: start)
        XCTAssertEqual(result?.show.id, 169)
        XCTAssertEqual(result?.episodes.map(\.number), [2])
    }
}

/// Replies by URL, and the URLs asked for, so tests can count network calls and change the reply between them.
private actor TVMazeScript {
    private var replies: [String: JSONValue]
    private var calls: [String] = []

    init(_ replies: [String: JSONValue]) {
        self.replies = replies
    }

    func set(_ url: String, _ value: JSONValue?) {
        replies[url] = value
    }

    func reply(_ url: String) -> JSONValue? {
        calls.append(url)
        return replies[url]
    }

    func count(_ url: String) -> Int {
        calls.filter { $0 == url }.count
    }
}

private struct ScriptedTVMaze: TVMazeTransport {
    let script: TVMazeScript

    func json(_ url: URL) async -> JSONValue? {
        await script.reply(url.absoluteString)
    }
}
