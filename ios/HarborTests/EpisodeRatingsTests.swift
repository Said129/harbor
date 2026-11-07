import XCTest
@testable import Harbor

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [URL] = []
    var urls: [URL] { lock.withLock { seen } }
    func add(_ url: URL) { lock.withLock { seen.append(url) } }
}

private func episode(_ season: Int?, _ number: Int?, imdbSeason: Int? = nil, imdbEpisode: Int? = nil) -> Episode {
    Episode(id: "e\(season ?? 0)x\(number ?? 0)", season: season, episode: number, name: nil, title: nil, thumbnail: nil, overview: nil, released: nil, imdbID: nil, imdbSeason: imdbSeason, imdbEpisode: imdbEpisode)
}

private func seasonRow(_ number: String, _ rating: String) -> JSONValue {
    var row: [String: JSONValue] = [:]
    row["Episode"] = .string(number); row["imdbRating"] = .string(rating)
    return .object(row)
}

private func seasonReply(_ rows: [JSONValue]) -> JSONValue {
    var reply: [String: JSONValue] = [:]
    reply["Response"] = .string("True"); reply["Season"] = .string("2"); reply["Episodes"] = .array(rows)
    return .object(reply)
}

private func omdbFailure(_ message: String) -> JSONValue {
    var reply: [String: JSONValue] = [:]
    reply["Response"] = .string("False"); reply["Error"] = .string(message)
    return .object(reply)
}

/// Episode ratings (Desktop's `harbor-imdb.ts` episodes, `omdbSeasonRatings` and `series-episode-row.tsx`).
final class EpisodeRatingsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func freshDefaults() -> UserDefaults {
        let name = "episode-ratings-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testTheCommunityRatingsAreReadKeptForAnHourAndAskedAgainAfterAFailureWithinAMinute() async {
        let log = RequestLog()
        var ratings: [String: JSONValue] = [:]
        ratings["1:1"] = .number(9.1); ratings["1:2"] = .string("8.6"); ratings["1:3"] = .number(0); ratings["1:4"] = .string("n/a"); ratings["2:1"] = .integer(8); ratings["x"] = .null
        let reply = JSONValue.object(["ratings": .object(ratings)])
        let service = HarborEpisodeRatings { url in log.add(url); return reply }
        let map = await service.ratings("tt0903747", now: now)
        XCTAssertEqual(map, ["1:1": 9.1, "1:2": 8.6, "2:1": 8], "Numbers and numeric text are read; zero, text and nulls are left out")
        XCTAssertEqual(log.urls.map(\.absoluteString), ["https://harborcommunity.site/api/imdb/episodes/tt0903747"])
        _ = await service.ratings("tt0903747", now: now.addingTimeInterval(59 * 60))
        XCTAssertEqual(log.urls.count, 1, "A good answer is kept for an hour")
        _ = await service.ratings("tt0903747", now: now.addingTimeInterval(61 * 60))
        XCTAssertEqual(log.urls.count, 2)

        let rejected = RequestLog()
        let failing = HarborEpisodeRatings { url in rejected.add(url); throw HarborError(code: "http-500") }
        let none = await failing.ratings("tt1", now: now)
        XCTAssertTrue(none.isEmpty)
        _ = await failing.ratings("tt1", now: now.addingTimeInterval(59))
        XCTAssertEqual(rejected.urls.count, 1, "A failure is remembered for a minute")
        _ = await failing.ratings("tt1", now: now.addingTimeInterval(61))
        XCTAssertEqual(rejected.urls.count, 2, "Then it is asked again")

        let invalid = RequestLog()
        let guarded = HarborEpisodeRatings { url in invalid.add(url); return reply }
        for id in ["tmdb:5", "tt12/../x", "", "tt"] {
            let found = await guarded.ratings(id, now: now)
            XCTAssertTrue(found.isEmpty, id)
        }
        XCTAssertTrue(invalid.urls.isEmpty, "Only an IMDb series id is asked for")
        XCTAssertNil(HarborEpisodeRatings.url("tt12 3"))
    }

    func testOmdbSeasonRepliesGiveEpisodeRatingsByNumber() {
        let reply = seasonReply([seasonRow("1", "8.5"), seasonRow("2", "N/A"), seasonRow("3", "7.25"), seasonRow("4", "0.0"), seasonRow("x", "9.9"), seasonRow("05", "9.0")])
        XCTAssertEqual(OmdbParser.seasonRatings(reply), [1: 8.5, 3: 7.25, 5: 9.0], "N/A, zero and a non-numeric episode are skipped")
        XCTAssertTrue(OmdbParser.seasonRatings(.object([:])).isEmpty)
        XCTAssertTrue(OmdbParser.seasonRatings(omdbFailure("Series or season not found!")).isEmpty)
    }

    func testOmdbSeasonRatingsAreCachedForTheSessionAndCountAgainstTheBudget() async throws {
        let log = RequestLog()
        let reply = seasonReply([seasonRow("1", "8.5"), seasonRow("2", "7.0")])
        let service = OmdbService(defaults: freshDefaults()) { url in log.add(url); return .json(reply) }
        let first = await service.seasonRatings(key: " abc ", imdbID: "tt1", season: 2, now: now)
        XCTAssertEqual(first, [1: 8.5, 2: 7.0])
        let query = try XCTUnwrap(URLComponents(url: try XCTUnwrap(log.urls.first), resolvingAgainstBaseURL: false))
        XCTAssertEqual(query.host, "www.omdbapi.com")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: (query.queryItems ?? []).map { ($0.name, $0.value ?? "") }), ["i": "tt1", "Season": "2", "apikey": "abc"])
        let again = await service.seasonRatings(key: "abc", imdbID: "tt1", season: 2, now: now.addingTimeInterval(86_400 * 10))
        XCTAssertEqual(again, first); XCTAssertEqual(log.urls.count, 1, "A season is kept for the session")
        let spent = await service.budget(now: now)
        XCTAssertEqual(spent.used, 1)
        _ = await service.seasonRatings(key: "abc", imdbID: "tt1", season: 3, now: now)
        XCTAssertEqual(log.urls.count, 2, "Another season is another request")

        let silent = RequestLog()
        let guarded = OmdbService(defaults: freshDefaults()) { url in silent.add(url); return .json(reply) }
        let none = await guarded.seasonRatings(key: "", imdbID: "tt1", season: 1, now: now)
        let notImdb = await guarded.seasonRatings(key: "abc", imdbID: "tmdb:1", season: 1, now: now)
        let special = await guarded.seasonRatings(key: "abc", imdbID: "tt1", season: 0, now: now)
        XCTAssertTrue(none.isEmpty && notImdb.isEmpty && special.isEmpty); XCTAssertTrue(silent.urls.isEmpty, "No key, no IMDb id or season 0 sends nothing")
    }

    func testARefusedKeyASpentAllowanceAndAMissAreHandledLikeDesktop() async {
        let refused = RequestLog()
        let unauthorized = OmdbService(defaults: freshDefaults()) { url in refused.add(url); return .unauthorized }
        let first = await unauthorized.seasonRatings(key: "bad", imdbID: "tt1", season: 1, now: now)
        XCTAssertTrue(first.isEmpty)
        let flagged = await unauthorized.budget(now: now)
        XCTAssertTrue(flagged.keyInvalid)
        _ = await unauthorized.seasonRatings(key: "bad", imdbID: "tt1", season: 2, now: now)
        XCTAssertEqual(refused.urls.count, 1, "A refused key is not tried again")

        let limit = RequestLog()
        let exhausted = OmdbService(defaults: freshDefaults()) { url in limit.add(url); return .json(omdbFailure("Request limit reached!")) }
        _ = await exhausted.seasonRatings(key: "abc", imdbID: "tt1", season: 1, now: now)
        let spent = await exhausted.budget(now: now)
        XCTAssertTrue(spent.exhausted); XCTAssertEqual(spent.used, spent.limit)
        _ = await exhausted.seasonRatings(key: "abc", imdbID: "tt1", season: 2, now: now)
        XCTAssertEqual(limit.urls.count, 1, "Nothing is sent once the allowance is spent")

        let missing = RequestLog()
        let miss = OmdbService(defaults: freshDefaults()) { url in missing.add(url); return .json(omdbFailure("Series or season not found!")) }
        let empty = await miss.seasonRatings(key: "abc", imdbID: "tt1", season: 1, now: now)
        XCTAssertTrue(empty.isEmpty)
        let counted = await miss.budget(now: now)
        XCTAssertEqual(counted.used, 1, "A miss still costs a request")
        _ = await miss.seasonRatings(key: "abc", imdbID: "tt1", season: 1, now: now)
        XCTAssertEqual(missing.urls.count, 2, "A miss is not kept")

        let offline = RequestLog()
        let down = OmdbService(defaults: freshDefaults()) { url in offline.add(url); return .failure }
        _ = await down.seasonRatings(key: "abc", imdbID: "tt1", season: 1, now: now)
        let free = await down.budget(now: now)
        XCTAssertEqual(free.used, 0, "A request that never arrived costs nothing")
    }

    func testEpisodeRatingsFollowIMDbNumberingAndPreferTheCommunity() {
        XCTAssertEqual(EpisodeRatings.key(episode(1, 2)), "1:2")
        XCTAssertEqual(EpisodeRatings.key(episode(1, 12, imdbSeason: 2, imdbEpisode: 1)), "2:1", "IMDb's own coordinates win when the source gives them")
        XCTAssertEqual(EpisodeRatings.key(episode(nil, nil)), "0:0")
        let merged = EpisodeRatings.merged(community: ["1:1": 9.0], seasons: [1: [1: 5.0, 2: 8.0], 2: [1: 7.0]])
        XCTAssertEqual(merged, ["1:1": 9.0, "1:2": 8.0, "2:1": 7.0], "OMDb fills what the community lacks and never replaces it")
        XCTAssertEqual(EpisodeRatings.merged(community: [:], seasons: [:]), [:])
        XCTAssertEqual(EpisodeRatings.rating(for: episode(1, 1), in: ["1:1": 9.1]), 9.1)
        XCTAssertNil(EpisodeRatings.rating(for: episode(1, 1), in: ["1:1": 0]), "A zero rating prints nothing")
        XCTAssertNil(EpisodeRatings.rating(for: episode(1, 2), in: ["1:1": 9.1]))
        XCTAssertEqual(EpisodeRatings.label(9.14), "9.1"); XCTAssertEqual(EpisodeRatings.label(8), "8.0")
        XCTAssertEqual(EpisodeRatings.seasons(of: [episode(0, 1), episode(1, 1), episode(3, 1), episode(nil, 1), episode(5, 1, imdbSeason: 2), episode(1, 2)]), [1, 2, 3],
                       "Specials and unnumbered episodes are not asked for; IMDb's season is used when given")
    }
}
