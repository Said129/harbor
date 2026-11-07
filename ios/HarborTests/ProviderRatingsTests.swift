import XCTest
@testable import Harbor

private final class FetchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [URL] = []
    var urls: [URL] { lock.withLock { seen } }
    func add(_ url: URL) { lock.withLock { seen.append(url) } }
}

/// Desktop's OMDb and MDBList providers (`lib/providers/omdb.ts`, `mdblist.ts`) and the ratings row of a detail page
/// (`views/detail/hero-ratings.tsx`).
final class ProviderRatingsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func omdbReply(rt: String? = "87%", metacritic: String? = "82/100", votes: String = "1,234,567", rating: String = "8.1", rated: String = "PG-13") -> JSONValue {
        var ratings: [JSONValue] = [.object(["Source": .string("Internet Movie Database"), "Value": .string("8.1/10")])]
        if let rt { ratings.append(.object(["Source": .string("Rotten Tomatoes"), "Value": .string(rt)])) }
        if let metacritic { ratings.append(.object(["Source": .string("Metacritic"), "Value": .string(metacritic)])) }
        return .object(["Response": .string("True"), "imdbRating": .string(rating), "imdbVotes": .string(votes), "Rated": .string(rated), "Ratings": .array(ratings)])
    }
    private func omdbError(_ message: String) -> JSONValue { .object(["Response": .string("False"), "Error": .string(message)]) }
    private func scores(_ json: JSONValue) -> OmdbScores? {
        if case .scores(let found) = OmdbParser.parse(json, now: now) { return found }
        return nil
    }
    private func freshDefaults() -> UserDefaults {
        let name = "provider-ratings-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testAnOmdbReplyIsReadWithItsScores() throws {
        let found = try XCTUnwrap(scores(omdbReply()))
        XCTAssertEqual(found.imdbRating, "8.1"); XCTAssertEqual(found.rated, "PG-13"); XCTAssertEqual(found.imdbVotes, 1_234_567)
        XCTAssertEqual(found.rtCritics, 87); XCTAssertEqual(found.metascore, 82); XCTAssertTrue(found.certifiedFresh)
        XCTAssertEqual(found.fetchedAt, 1_700_000_000_000, "Milliseconds since 1970, as on Desktop")

        let bare = try XCTUnwrap(scores(omdbReply(rt: nil, metacritic: nil, votes: "N/A", rating: "N/A", rated: "Not Rated")))
        XCTAssertNil(bare.imdbRating); XCTAssertNil(bare.rated); XCTAssertNil(bare.imdbVotes)
        XCTAssertNil(bare.rtCritics); XCTAssertNil(bare.metascore); XCTAssertFalse(bare.certifiedFresh)
        for unrated in ["N/A", " unrated ", "NR", ""] { XCTAssertNil(try XCTUnwrap(scores(omdbReply(rated: unrated))).rated, "'\(unrated)' is no rating") }
        XCTAssertEqual(try XCTUnwrap(scores(omdbReply(rated: " TV-MA "))).rated, "TV-MA")
    }

    func testCertifiedFreshNeedsBothTheCriticsScoreAndEnoughVotes() throws {
        XCTAssertTrue(try XCTUnwrap(scores(omdbReply(rt: "75%", votes: "50,000"))).certifiedFresh)
        XCTAssertFalse(try XCTUnwrap(scores(omdbReply(rt: "74%", votes: "900,000"))).certifiedFresh)
        XCTAssertFalse(try XCTUnwrap(scores(omdbReply(rt: "95%", votes: "49,999"))).certifiedFresh)
        XCTAssertFalse(try XCTUnwrap(scores(omdbReply(rt: nil, votes: "900,000"))).certifiedFresh)
    }

    func testOmdbErrorsAreToldApart() {
        for message in ["Invalid API key!", "No API key provided.", "The API key is not activated"] {
            XCTAssertEqual(OmdbParser.parse(omdbError(message), now: now), .keyInvalid, message)
        }
        for message in ["Request limit reached!", "Daily limit exceeded"] {
            XCTAssertEqual(OmdbParser.parse(omdbError(message), now: now), .exhausted, message)
        }
        for message in ["Movie not found!", "Incorrect IMDb ID.", ""] {
            XCTAssertEqual(OmdbParser.parse(omdbError(message), now: now), .miss, message)
        }
    }

    func testTheDailyAllowanceStartsAtUTCMidnightAndKeepsARefusedKey() {
        let budget = OmdbBudget.fresh(now: now)
        XCTAssertEqual(budget.limit, 1_000); XCTAssertEqual(budget.resetAt, 1_700_006_400_000)
        var spent = budget
        for (used, prefetch) in [(0, true), (899, true), (900, false), (1_000, false)] {
            spent.used = used
            XCTAssertEqual(spent.allowsPrefetch, prefetch, "\(used) used")
        }
        spent.used = 1_000; spent.exhausted = true; spent.keyInvalid = true
        XCTAssertEqual(spent.current(at: now.addingTimeInterval(6_000)), spent, "Nothing changes before midnight")
        let next = spent.current(at: now.addingTimeInterval(6_400))
        XCTAssertEqual(next.used, 0); XCTAssertFalse(next.exhausted); XCTAssertTrue(next.keyInvalid, "A refused key stays refused across midnight")
        XCTAssertEqual(next.resetAt, 1_700_092_800_000)
    }

    func testOmdbScoresAreFetchedOnceThenServedFromTheCacheForNinetyDays() async throws {
        let log = FetchLog(), reply = omdbReply(), defaults = freshDefaults()
        let service = OmdbService(defaults: defaults) { url in log.add(url); return .json(reply) }
        let first = await service.scores(key: " abc12345 ", imdbID: "tt0111161", type: "movie", now: now)
        XCTAssertEqual(first?.rtCritics, 87)
        let again = await service.scores(key: "abc12345", imdbID: "tt0111161", now: now.addingTimeInterval(3_600))
        XCTAssertEqual(again, first); XCTAssertEqual(log.urls.count, 1, "The second look comes from the cache")
        let spent = await service.budget(now: now)
        XCTAssertEqual(spent.used, 1)
        let query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(log.urls.first), resolvingAgainstBaseURL: false))
        XCTAssertEqual(query.host, "www.omdbapi.com")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: (query.queryItems ?? []).map { ($0.name, $0.value ?? "") }), ["i": "tt0111161", "apikey": "abc12345", "type": "movie"])

        let restarted = OmdbService(defaults: defaults) { url in log.add(url); return .failure }
        let kept = await restarted.cached("tt0111161", now: now.addingTimeInterval(86_400))
        XCTAssertEqual(kept, first, "The cache survives a restart")

        let stale = await service.scores(key: "abc12345", imdbID: "tt0111161", now: now.addingTimeInterval(91 * 86_400))
        XCTAssertEqual(stale?.rtCritics, 87); XCTAssertEqual(log.urls.count, 2, "After 90 days the title is asked for again")

        let nothing = await service.scores(key: "", imdbID: "tt0111161", now: now)
        let notImdb = await service.scores(key: "abc12345", imdbID: "tmdb:603", now: now)
        XCTAssertNil(nothing); XCTAssertNil(notImdb); XCTAssertEqual(log.urls.count, 2, "No key or no IMDb id sends nothing")
    }

    func testARefusedKeyStopsFurtherRequestsUntilTheBudgetIsReset() async {
        let log = FetchLog()
        let service = OmdbService(defaults: freshDefaults()) { url in log.add(url); return .unauthorized }
        let refused = await service.scores(key: "wrong", imdbID: "tt0111161", now: now)
        XCTAssertNil(refused)
        let flagged = await service.budget(now: now)
        XCTAssertTrue(flagged.keyInvalid); XCTAssertTrue(flagged.blocked)
        let blocked = await service.scores(key: "wrong", imdbID: "tt0068646", now: now)
        XCTAssertNil(blocked); XCTAssertEqual(log.urls.count, 1, "A refused key is not tried again")
        await service.resetBudget(now: now)
        let reset = await service.budget(now: now)
        XCTAssertFalse(reset.keyInvalid); XCTAssertEqual(reset.used, 0)
        _ = await service.scores(key: "right", imdbID: "tt0068646", now: now)
        XCTAssertEqual(log.urls.count, 2, "Saving a new key lets requests through again")
    }

    func testMissesAndTheDailyLimitAreRemembered() async {
        let log = FetchLog(), missing = omdbError("Incorrect IMDb ID."), limit = omdbError("Request limit reached!")
        let service = OmdbService(defaults: freshDefaults()) { url in
            log.add(url)
            return .json(url.absoluteString.contains("tt0000001") ? missing : limit)
        }
        let miss = await service.scores(key: "abc12345", imdbID: "tt0000001", now: now)
        XCTAssertNil(miss)
        let afterMiss = await service.budget(now: now)
        XCTAssertEqual(afterMiss.used, 1, "A miss still costs a request")
        await service.prefetch(key: "abc12345", imdbID: "tt0000001", now: now.addingTimeInterval(3_600))
        XCTAssertEqual(log.urls.count, 1, "Prefetch skips a title that missed in the last day")
        await service.prefetch(key: "abc12345", imdbID: "tt0000001", now: now.addingTimeInterval(86_400 + 1))
        XCTAssertEqual(log.urls.count, 2, "A day later it is tried again")

        let exhausted = await service.scores(key: "abc12345", imdbID: "tt0000002", now: now.addingTimeInterval(86_400 + 2))
        XCTAssertNil(exhausted)
        let spent = await service.budget(now: now.addingTimeInterval(86_400 + 2))
        XCTAssertTrue(spent.exhausted); XCTAssertEqual(spent.used, spent.limit); XCTAssertFalse(spent.keyInvalid)
        let blocked = await service.scores(key: "abc12345", imdbID: "tt0000003", now: now.addingTimeInterval(86_400 + 3))
        XCTAssertNil(blocked); XCTAssertEqual(log.urls.count, 3, "Nothing more is sent once the day's allowance is spent")
    }

    func testPrefetchLeavesTheLastTenthOfTheAllowanceForOpenedPages() async {
        let log = FetchLog(), reply = omdbReply(), defaults = freshDefaults()
        var budget = OmdbBudget.fresh(now: now); budget.used = 900
        defaults.set(try? JSONEncoder().encode(budget), forKey: "omdb.budget.v1")
        let service = OmdbService(defaults: defaults) { url in log.add(url); return .json(reply) }
        await service.prefetch(key: "abc12345", imdbID: "tt0111161", now: now)
        XCTAssertEqual(log.urls.count, 0)
        let opened = await service.scores(key: "abc12345", imdbID: "tt0111161", now: now)
        XCTAssertEqual(opened?.rtCritics, 87, "Opening the page still spends from the reserve"); XCTAssertEqual(log.urls.count, 1)
    }

    private func mdblistRow(_ source: String, _ value: JSONValue) -> JSONValue { .object(["source": .string(source), "value": value]) }

    func testAnMdblistReplyIsReadWithItsScores() throws {
        let json = JSONValue.object(["score_average": .integer(71), "ratings": .array([
            mdblistRow("letterboxd", .number(3.9)), mdblistRow("trakt", .integer(82)), mdblistRow("metacritic", .integer(74)),
            mdblistRow("tomatoesaudience", .integer(91)), mdblistRow("simkl", .number(78.5)), mdblistRow("imdb", .number(8.1))])])
        let found = try XCTUnwrap(MdblistParser.parse(json))
        XCTAssertEqual(found.score, 71); XCTAssertEqual(found.letterboxd, 3.9); XCTAssertEqual(found.trakt, 82); XCTAssertEqual(found.metacritic, 74)
        XCTAssertEqual(found.rtAudience, 91); XCTAssertEqual(try XCTUnwrap(found.simkl), 7.85, accuracy: 0.0001, "SIMKL's percentage becomes a score out of 10")
        XCTAssertFalse(found.isEmpty)

        let aliases = try XCTUnwrap(MdblistParser.parse(.object(["scoreaverage": .integer(0), "score": .integer(64), "ratings": .array([
            mdblistRow("audience", .integer(0)), mdblistRow("popcorn", .integer(88)), mdblistRow("simkl", .number(7.2)), mdblistRow("trakt", .string("77"))])])))
        XCTAssertEqual(aliases.score, 64, "Zero is skipped for the next field")
        XCTAssertEqual(aliases.rtAudience, 88, "The popcorn row stands in when the audience row has nothing")
        XCTAssertEqual(try XCTUnwrap(aliases.simkl), 7.2, accuracy: 0.0001); XCTAssertEqual(aliases.trakt, 77)

        let empty = try XCTUnwrap(MdblistParser.parse(.object(["ratings": .array([])])))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertNil(MdblistParser.parse(.object(["error": .string("Invalid API key")])), "Without a ratings list it is an error page")
    }

    func testMdblistTriesTheLegacyEndpointAndRemembersResultsForADayAndFailuresForAMinute() async {
        let log = FetchLog()
        let good = JSONValue.object(["ratings": .array([mdblistRow("trakt", .integer(80))])])
        let refusal = JSONValue.object(["error": .string("nope")])
        let service = MdblistService { url in
            log.add(url)
            return url.host == "mdblist.com" ? good : refusal
        }
        let first = await service.scores(key: " k1 ", imdbID: "tt0111161", type: "movie", now: now)
        XCTAssertEqual(first?.trakt, 80)
        XCTAssertEqual(log.urls.map { $0.host }, ["api.mdblist.com", "mdblist.com"], "The legacy endpoint answers when the new one has no ratings")
        XCTAssertEqual(log.urls.first?.path, "/imdb/movie/tt0111161")
        XCTAssertEqual(URLComponents(url: log.urls[0], resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "apikey", value: "k1")])
        XCTAssertEqual(Set((URLComponents(url: log.urls[1], resolvingAgainstBaseURL: false)?.queryItems ?? []).map { "\($0.name)=\($0.value ?? "")" }), ["apikey=k1", "i=tt0111161"])
        _ = await service.scores(key: "k1", imdbID: "tt0111161", type: "movie", now: now.addingTimeInterval(3_600))
        XCTAssertEqual(log.urls.count, 2, "A result is kept for a day")
        _ = await service.scores(key: "k1", imdbID: "tt0111161", type: "movie", now: now.addingTimeInterval(86_401))
        XCTAssertEqual(log.urls.count, 4, "After a day both endpoints are asked again")
        _ = await service.scores(key: "k2", imdbID: "tt0111161", type: "movie", now: now.addingTimeInterval(86_402))
        XCTAssertEqual(log.urls.count, 6, "A corrected key does not reuse the earlier answer")

        let failing = FetchLog()
        let down = MdblistService { url in failing.add(url); return nil }
        let none = await down.scores(key: "k1", imdbID: "tt0111161", type: "show", now: now)
        XCTAssertNil(none); XCTAssertEqual(failing.urls.count, 2)
        XCTAssertEqual(failing.urls.first?.path, "/imdb/show/tt0111161")
        _ = await down.scores(key: "k1", imdbID: "tt0111161", type: "show", now: now.addingTimeInterval(30))
        XCTAssertEqual(failing.urls.count, 2, "A failure is not retried for a minute")
        _ = await down.scores(key: "k1", imdbID: "tt0111161", type: "show", now: now.addingTimeInterval(61))
        XCTAssertEqual(failing.urls.count, 4, "Then it is")
        let noKey = await down.scores(key: "  ", imdbID: "tt0111161", now: now)
        let noImdb = await down.scores(key: "k1", imdbID: "123", now: now)
        XCTAssertNil(noKey); XCTAssertNil(noImdb); XCTAssertEqual(failing.urls.count, 4)
    }

    func testTheRatingsRowFollowsDesktopsOrderLinksAndRounding() throws {
        let omdb = try XCTUnwrap(scores(omdbReply(rt: "93%", metacritic: "70/100")))
        let mdblist = MdblistScores(score: 71.5, letterboxd: 3.94, trakt: 81.6, metacritic: 74.4, rtAudience: 90.5, simkl: 7.86)
        let items = DetailRatings.items(omdb: omdb, mdblist: mdblist, imdbID: "tt0111161", isShow: false, hidden: [])
        XCTAssertEqual(items.map(\.id), ["rt", "audience", "letterboxd", "metacritic", "trakt", "simkl", "mdblist"])
        XCTAssertEqual(items.map(\.value), ["93%", "91%", "3.9", "74", "82%", "7.9", "72"])
        XCTAssertEqual(items.map(\.label), ["Rotten Tomatoes Critics", "Rotten Tomatoes Audience", "Letterboxd", "Metacritic", "Trakt", "SIMKL", "MDBList"])
        XCTAssertEqual(items.map { $0.link?.absoluteString }, [nil, nil, "https://letterboxd.com/imdb/tt0111161/", nil, "https://trakt.tv/search/imdb/tt0111161",
                                                                 "https://api.simkl.com/redirect?to=simkl&imdb=tt0111161", "https://mdblist.com/movie/tt0111161"])
        XCTAssertEqual(DetailRatings.items(omdb: nil, mdblist: mdblist, imdbID: "tt0111161", isShow: true, hidden: []).last?.link?.absoluteString, "https://mdblist.com/show/tt0111161")
        XCTAssertEqual(DetailRatings.items(omdb: omdb, mdblist: nil, imdbID: nil, isShow: false, hidden: []).map(\.id), ["rt", "metacritic"], "OMDb's Metascore stands in without MDBList")
        XCTAssertEqual(DetailRatings.items(omdb: omdb, mdblist: nil, imdbID: nil, isShow: false, hidden: []).last?.value, "70")

        let shown = DetailRatings.items(omdb: omdb, mdblist: mdblist, imdbID: "tt0111161", isShow: false, hidden: ["rt", "trakt", "mdblist", "imdb"])
        XCTAssertEqual(shown.map(\.id), ["audience", "letterboxd", "metacritic", "simkl"], "Providers turned off in the matrix are left out")
        XCTAssertTrue(DetailRatings.items(omdb: nil, mdblist: nil, imdbID: "tt0111161", isShow: false, hidden: []).isEmpty)
        XCTAssertTrue(DetailRatings.items(omdb: nil, mdblist: MdblistScores(), imdbID: nil, isShow: false, hidden: []).isEmpty)
    }

    func testSimklCommunityRatingsAreAskedInBatchesAndRemembered() async throws {
        let log = FetchLog()
        let service = SimklCommunityRatings { url in
            log.add(url)
            let specs = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ids" }?.value?.split(separator: ",").map(String.init) ?? []
            var ratings: [String: JSONValue] = [:]
            for spec in specs { ratings[spec] = spec == "imdb:tt1" ? .object(["rating": .number(9.1), "votes": .integer(10)]) : .null }
            return .object(["ratings": .object(ratings)])
        }
        let first = await service.rating("imdb:TT1")
        XCTAssertEqual(first, 9.1)
        let query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(log.urls.first), resolvingAgainstBaseURL: false))
        XCTAssertEqual(query.host, "harborcommunity.site"); XCTAssertEqual(query.path, "/api/simkl/ratings")
        XCTAssertEqual(query.queryItems?.first { $0.name == "ids" }?.value, "imdb:tt1", "Specs are asked in lower case")
        let again = await service.rating("imdb:tt1")
        XCTAssertEqual(again, 9.1); XCTAssertEqual(log.urls.count, 1, "A score is remembered")

        let mixed = await service.ratings(["imdb:tt1", "imdb:tt2", "imdb:tt3", "imdb:TT2"])
        XCTAssertEqual(mixed, ["imdb:tt1": 9.1], "A title without a score is left out")
        XCTAssertEqual(log.urls.count, 2, "Only the specs not known yet are asked, together")
        XCTAssertEqual(URLComponents(url: log.urls[1], resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ids" }?.value, "imdb:tt2,imdb:tt3")
        _ = await service.ratings(["imdb:tt2", "imdb:tt3"])
        XCTAssertEqual(log.urls.count, 2, "Having no score is remembered too")

        let many = (0..<130).map { "mal:\($0 + 100)" }
        _ = await service.ratings(many)
        XCTAssertEqual(log.urls.count, 4, "130 specs go out as 120 and 10")
        let sizes = log.urls.suffix(2).map { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ids" }?.value?.split(separator: ",").count ?? 0 }
        XCTAssertEqual(sizes, [120, 10])
    }

    func testSimklCommunityRatingsRememberHTTPErrorsButNotNetworkFailures() async {
        let server = FetchLog(), network = FetchLog()
        let refused = SimklCommunityRatings { url in server.add(url); throw HarborError(code: "http-500") }
        let none = await refused.rating("imdb:tt1")
        XCTAssertNil(none)
        _ = await refused.rating("imdb:tt1")
        XCTAssertEqual(server.urls.count, 1, "An answer with an error status counts as no score")

        let offline = SimklCommunityRatings { url in network.add(url); throw HarborError(code: "network") }
        _ = await offline.rating("imdb:tt1")
        _ = await offline.rating("imdb:tt1")
        XCTAssertEqual(network.urls.count, 2, "A request that never arrived is asked again")
        let empty = await offline.ratings(["", ""])
        XCTAssertTrue(empty.isEmpty); XCTAssertEqual(network.urls.count, 2, "Empty specs send nothing")
    }

    func testTheSimklChipPrefersTheCommunityScoreAndNeedsNoKey() {
        let mdblist = MdblistScores(simkl: 7.2)
        XCTAssertEqual(DetailRatings.items(omdb: nil, mdblist: mdblist, simkl: 9.14, imdbID: "tt1", isShow: false, hidden: []).map(\.value), ["9.1"])
        XCTAssertEqual(DetailRatings.items(omdb: nil, mdblist: mdblist, imdbID: "tt1", isShow: false, hidden: []).map(\.value), ["7.2"], "Without SIMKL's own score MDBList's copy is shown")
        let alone = DetailRatings.items(omdb: nil, mdblist: nil, simkl: 8.0, imdbID: "tt1", isShow: true, hidden: [])
        XCTAssertEqual(alone.map(\.id), ["simkl"]); XCTAssertEqual(alone.first?.value, "8.0")
        XCTAssertEqual(alone.first?.link?.absoluteString, "https://api.simkl.com/redirect?to=simkl&imdb=tt1")
        XCTAssertTrue(DetailRatings.items(omdb: nil, mdblist: mdblist, simkl: 9.1, imdbID: "tt1", isShow: false, hidden: ["simkl"]).isEmpty)
    }

    func testTheRatingsMatrixListsDesktopsProvidersAndMetacriticColours() {
        XCTAssertEqual(DetailRatings.sources.map(\.id), ["imdb", "tmdb", "rt", "audience", "metacritic", "letterboxd", "mdblist", "trakt", "simkl"])
        XCTAssertEqual(DetailRatings.metacriticBand(61), "green"); XCTAssertEqual(DetailRatings.metacriticBand(60), "amber")
        XCTAssertEqual(DetailRatings.metacriticBand(40), "amber"); XCTAssertEqual(DetailRatings.metacriticBand(39), "red")
        XCTAssertEqual(DetailRatings.rounded(72.5), 73); XCTAssertEqual(DetailRatings.rounded(72.49), 72)
    }
}
