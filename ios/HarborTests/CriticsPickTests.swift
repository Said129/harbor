import XCTest
@testable import Harbor

/// Desktop's Critics Pick rules (`lib/feed/sections.ts`, `views/discover.tsx`, `critics-pick.tsx`, `tmdb-critic.ts`) and OMDb use.
final class CriticsPickTests: XCTestCase {
    private let omdbHit = #"{"Title":"Example","imdbRating":"7.8","imdbVotes":"120,000","Rated":"R","Ratings":[{"Source":"Internet Movie Database","Value":"7.8/10"},{"Source":"Rotten Tomatoes","Value":"91%"},{"Source":"Metacritic","Value":"84/100"}],"Response":"True"}"#

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func media(_ id: String, background: String? = "https://img.example/bg.jpg", description: String? = "An overview.") -> Media {
        var value = Media(id: id, type: "movie", name: id)
        value.background = background
        value.description = description
        return value
    }

    private func configuration(tmdbKey: String = "tmdb-test-key") -> MetadataConfiguration {
        MetadataConfiguration(tmdbKey: tmdbKey, region: "US", language: "en-US", translateTitles: false)
    }

    // MARK: Day, page and queries

    func testDayOfYearAdvancesOneDayPerDay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let next = now.addingTimeInterval(86_400)
        XCTAssertEqual(CriticsPickRules.dayOfYear(now: next) - CriticsPickRules.dayOfYear(now: now), 1)
        XCTAssertTrue((1...366).contains(CriticsPickRules.dayOfYear(now: now)))
    }

    func testPageRotatesOverFivePagesByDayAndSource() {
        let first = CriticsPickRules.sources[0]
        XCTAssertEqual(CriticsPickRules.page(first, dayOfYear: 0), 1)
        XCTAssertEqual(CriticsPickRules.page(first, dayOfYear: 4), 5)
        XCTAssertEqual(CriticsPickRules.page(first, dayOfYear: 5), 1)
        XCTAssertEqual(CriticsPickRules.page(CriticsPickRules.sources[3], dayOfYear: 0), 4)
    }

    func testFourDesktopSourcesWithTheirFilters() {
        let sources = CriticsPickRules.sources
        XCTAssertEqual(sources.count, 4)
        XCTAssertEqual(sources[0].parameters["vote_count.gte"], "5000")
        XCTAssertEqual(sources[1].parameters["primary_release_date.gte"], "2018-01-01")
        XCTAssertEqual(sources[2].parameters["sort_by"], "vote_count.desc")
        XCTAssertEqual(sources[3].parameters["primary_release_date.lte"], "1999-12-31")
        let rail = CriticsPickRules.rail(sources[1])
        XCTAssertEqual(rail.path, "discover/movie")
        XCTAssertEqual(rail.kind, "movie")
    }

    func testCriticsPickAddsTheRegionOnlyWhenTheLocalePreferenceIsEnabled() {
        let source = CriticsPickRules.sources[0]
        let locale = DiscoveryAffinityRules.localeBias(preferredLanguages: ["es"], metadataLanguage: "en-US", region: "ES")
        let weighted = CriticsPickRules.rail(source, locale: locale, region: "ES")
        XCTAssertEqual(weighted.parameters["region"], "ES")
        XCTAssertEqual(weighted.parameters["vote_count.gte"], source.parameters["vote_count.gte"])
        XCTAssertEqual(CriticsPickRules.rail(source, region: "ES").parameters, source.parameters)
    }

    // MARK: Merge and pick

    func testMergeInterleavesListsAndDropsDuplicates() {
        let merged = CriticsPickRules.merge([[media("a"), media("b")], [media("b"), media("c")], [media("d")]])
        XCTAssertEqual(merged.map(\.id), ["a", "b", "d", "c"])
    }

    func testPickUsesOnlyTitlesWithArtworkAndDescriptionByDay() {
        let list = [media("full1"), media("nodesc", description: nil), media("nobg", background: nil), media("full2")]
        XCTAssertEqual(CriticsPickRules.pick(from: list, excludedIDs: [], featuredIDs: [], dayOfYear: 0)?.id, "full1")
        XCTAssertEqual(CriticsPickRules.pick(from: list, excludedIDs: [], featuredIDs: [], dayOfYear: 1)?.id, "full2")
        XCTAssertEqual(CriticsPickRules.pick(from: list, excludedIDs: [], featuredIDs: [], dayOfYear: 2)?.id, "full1")
    }

    func testPickSkipsFeaturedAndExcludedTitles() {
        let list = [media("full1"), media("full2")]
        XCTAssertEqual(CriticsPickRules.pick(from: list, excludedIDs: [], featuredIDs: ["full1"], dayOfYear: 0)?.id, "full2")
        XCTAssertEqual(CriticsPickRules.pick(from: list, excludedIDs: ["full1"], featuredIDs: [], dayOfYear: 0)?.id, "full2")
        XCTAssertNil(CriticsPickRules.pick(from: list, excludedIDs: ["full1", "full2"], featuredIDs: [], dayOfYear: 0))
    }

    func testPickFallsBackToFirstTitleWhenNoneHasArtworkAndDescription() {
        let list = [media("nodesc", description: nil), media("nobg", background: nil)]
        XCTAssertEqual(CriticsPickRules.pick(from: list, excludedIDs: [], featuredIDs: [], dayOfYear: 0)?.id, "nodesc")
    }

    // MARK: Quote text

    func testExcerptKeepsShortReviewWhole() {
        XCTAssertEqual(CriticsPickRules.excerpt("  Short review.  "), "Short review.")
    }

    func testExcerptStopsAtSentenceEndPastTheMiddle() {
        let text = String(repeating: "a", count: 200) + ". " + String(repeating: "b", count: 300)
        XCTAssertEqual(CriticsPickRules.excerpt(text), String(repeating: "a", count: 200) + ".")
    }

    func testExcerptCutsAtWordBoundaryWithEllipsis() {
        let result = CriticsPickRules.excerpt(String(repeating: "lorem ", count: 100))
        XCTAssertTrue(result.hasSuffix("lorem…"))
        XCTAssertEqual(result.count, 318)
    }

    func testFirstSentenceOfOverview() {
        XCTAssertEqual(CriticsPickRules.firstSentence("First line. Second line!"), "First line.")
        XCTAssertEqual(CriticsPickRules.firstSentence("No ending"), "No ending")
    }

    func testQuotePrefersReviewThenTaglineThenOverviewThenFallback() {
        let review = CriticsPickReview(author: "critic", rating: 8, content: "Great film.", url: nil)
        XCTAssertEqual(CriticsPickRules.quote(review: review, tagline: "Tag", overview: "A. B.", fallback: "F"), "Great film.")
        XCTAssertEqual(CriticsPickRules.quote(review: nil, tagline: " Tag ", overview: "A. B.", fallback: "F"), "Tag")
        XCTAssertEqual(CriticsPickRules.quote(review: nil, tagline: nil, overview: "A one. B two.", fallback: "F"), "A one.")
        XCTAssertEqual(CriticsPickRules.quote(review: nil, tagline: "", overview: nil, fallback: "F"), "F")
    }

    // MARK: TMDB details

    func testDetailsKeepLongOnePerAuthorBestRatedFirst() throws {
        let long = String(repeating: "review ", count: 25)
        let value = try json("""
        {"tagline":"  Tag line  ","overview":"","external_ids":{"imdb_id":"tt0111161"},
         "reviews":{"results":[
           {"author":"short","author_details":{"username":"shorty","rating":10},"content":"Too short.","url":"https://x/1"},
           {"author":"A","author_details":{"username":"critic-a","rating":7},"content":"\(long)","url":"https://x/2"},
           {"author":"B","author_details":{"username":"Critic-A","rating":9},"content":"\(long)","url":"https://x/3"},
           {"author":"C","author_details":{"username":"critic-b","rating":9},"content":"\(long)"},
           {"author":"D","author_details":{"rating":null},"content":"\(long)"}
         ]}}
        """)
        let details = CriticsPickDetails.parse(value)
        XCTAssertEqual(details.tagline, "Tag line")
        XCTAssertNil(details.overview)
        XCTAssertEqual(details.imdbID, "tt0111161")
        XCTAssertEqual(details.reviews.map(\.author), ["critic-b", "critic-a", "D"])
        XCTAssertEqual(details.reviews.first?.rating, 9)
    }

    func testDetailPathOnlyForTMDBMovieIDs() {
        XCTAssertEqual(CriticsPickRules.detailPath(media("tmdb:movie:603")), "movie/603")
        XCTAssertNil(CriticsPickRules.detailPath(media("tmdb:tv:1399")))
        XCTAssertNil(CriticsPickRules.detailPath(media("tt0133093")))
    }

    func testDetailURLCarriesKeyLanguageAndAppendedReviews() {
        let url = CriticsPickRules.detailURL(path: "movie/603", key: "k", language: "en-US")
        XCTAssertTrue(url?.hasPrefix("https://api.themoviedb.org/3/movie/603?") == true)
        XCTAssertTrue(url?.contains("api_key=k") == true)
        XCTAssertTrue(url?.contains("language=en-US") == true)
    }

    // MARK: OMDb

    func testOmdbCannedJSONGivesRottenTomatoesMetascoreAndIMDb() throws {
        guard case .scores(let scores) = OmdbParser.parse(try json(omdbHit), now: Date(timeIntervalSince1970: 0)) else {
            return XCTFail("Expected scores")
        }
        XCTAssertEqual(scores.rtCritics, 91)
        XCTAssertEqual(scores.metascore, 84)
        XCTAssertEqual(scores.imdbRating, "7.8")
        XCTAssertEqual(scores.imdbVotes, 120_000)
        XCTAssertTrue(scores.certifiedFresh)
    }

    func testOmdbMissInvalidKeyAndLimitAreClassified() throws {
        XCTAssertEqual(OmdbParser.parse(try json(#"{"Response":"False","Error":"Movie not found!"}"#)), .miss)
        XCTAssertEqual(OmdbParser.parse(try json(#"{"Response":"False","Error":"Invalid API key!"}"#)), .keyInvalid)
        XCTAssertEqual(OmdbParser.parse(try json(#"{"Response":"False","Error":"Request limit reached!"}"#)), .exhausted)
    }

    func testCardScoresHideRottenTomatoesWhenSettingIsOff() throws {
        guard case .scores(let omdb) = OmdbParser.parse(try json(omdbHit)) else { return XCTFail("Expected scores") }
        XCTAssertEqual(CriticsPickScores.from(omdb, showRottenTomatoes: true).rottenTomatoes, 91)
        XCTAssertNil(CriticsPickScores.from(omdb, showRottenTomatoes: false).rottenTomatoes)
        XCTAssertEqual(CriticsPickScores.from(omdb, showRottenTomatoes: false).metascore, 84)
    }

    func testOmdbServiceReturnsCannedScoresAndSpendsOneRequest() async throws {
        let body = try json(omdbHit)
        let name = "CriticsPickTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name) ?? UserDefaults.standard
        defer { defaults.removePersistentDomain(forName: name) }
        let service = OmdbService(defaults: defaults, fetch: { _ in OmdbResponse.json(body) })
        await service.prefetch(key: "test-key", imdbID: "tt0111161")
        let scores = await service.cached("tt0111161")
        XCTAssertEqual(scores?.rtCritics, 91)
        XCTAssertEqual(scores?.metascore, 84)
        let budget = await service.budget()
        XCTAssertEqual(budget.used, 1)
    }

    func testWatchedTitlesMatchByNormalizedNameAndSkipInThePick() {
        XCTAssertEqual(CriticsPickRules.titleKey("Heat (1995)"), "heat")
        XCTAssertEqual(CriticsPickRules.titleKey("The Wild-Bunch!"), "thewildbunch")
        XCTAssertEqual(CriticsPickRules.titleKey(nil), "")
        var heat = media("tmdb:movie:1")
        heat.name = "Heat (1995)"
        var ronin = media("tmdb:movie:2")
        ronin.name = "Ronin"
        let pick = CriticsPickRules.pick(from: [heat, ronin], excludedIDs: [], featuredIDs: [], excludedTitleKeys: ["heat"], dayOfYear: 0)
        XCTAssertEqual(pick?.id, "tmdb:movie:2")
    }

    func testOmdbIsNotAskedWithoutKeyOrIMDbID() async {
        let service = CriticsPickService(scores: { _, imdb in OmdbScores(imdbRating: imdb, rtCritics: 91, fetchedAt: 0) })
        let withID = CriticsPickDetails(tagline: nil, overview: nil, reviews: [], imdbID: "tt0111161")
        let withoutID = CriticsPickDetails()
        let keyless = await service.omdbScores(for: withID, key: "")
        let idless = await service.omdbScores(for: withoutID, key: "test-key")
        let asked = await service.omdbScores(for: withID, key: "test-key")
        XCTAssertNil(keyless)
        XCTAssertNil(idless)
        XCTAssertEqual(asked?.rtCritics, 91)
    }

    // MARK: Candidate list

    func testCandidatesReadFourQueriesAtTheirDayPagesInOrder() async {
        let service = CriticsPickService(discover: { rail, page, _ in
            [Media(id: "tmdb:movie:\(rail.id)-\(page)", type: "movie", name: "title")]
        })
        let list = await service.candidates(dayOfYear: 0, configuration: configuration())
        XCTAssertEqual(list.map(\.id), [
            "tmdb:movie:critics-pick-acclaimed-1",
            "tmdb:movie:critics-pick-recent-2",
            "tmdb:movie:critics-pick-popular-3",
            "tmdb:movie:critics-pick-classic-4"
        ])
    }

    func testCandidatesAreEmptyWithoutTMDBKey() async {
        let service = CriticsPickService(discover: { _, _, _ in
            [Media(id: "tmdb:movie:1", type: "movie", name: "title")]
        })
        let list = await service.candidates(dayOfYear: 0, configuration: configuration(tmdbKey: ""))
        XCTAssertTrue(list.isEmpty)
    }
}
