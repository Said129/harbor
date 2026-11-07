import XCTest
@testable import Harbor

/// Desktop's card score chips (`components/pick-card.tsx`, `card-score-stack.tsx`, key gating in `views/settings/library-panel/cards-tab.tsx`),
/// through the pure policy in `Services/CardRatings.swift`.
final class CardRatingsTests: XCTestCase {
    private let everyProvider = Set(CardRatingProvider.allCases)

    private func omdb(rt: Int? = nil, imdb: String? = nil) -> OmdbScores {
        OmdbScores(imdbRating: imdb, rated: nil, imdbVotes: nil, rtCritics: rt, metascore: nil, certifiedFresh: false, fetchedAt: 0)
    }

    private func mdblist(score: Double? = nil, letterboxd: Double? = nil, trakt: Double? = nil, metacritic: Double? = nil, audience: Double? = nil) -> MdblistScores {
        MdblistScores(score: score, letterboxd: letterboxd, trakt: trakt, metacritic: metacritic, rtAudience: audience, simkl: nil)
    }

    func testWithoutKeysOnlyKeyFreeProvidersAreEnabled() {
        let enabled = CardRatingPolicy.enabled(selected: everyProvider, keys: [])
        XCTAssertEqual(enabled, [.imdb, .tmdb, .mal, .simkl])
    }

    func testOmdbKeyEnablesRottenTomatoesOnly() {
        let enabled = CardRatingPolicy.enabled(selected: [.rt, .metacritic], keys: [.omdb])
        XCTAssertEqual(enabled, [.rt])
    }

    func testMdblistKeyEnablesTheMdblistScoresButNotRottenTomatoes() {
        let enabled = CardRatingPolicy.enabled(selected: everyProvider, keys: [.mdblist])
        XCTAssertEqual(enabled, [.imdb, .tmdb, .mal, .simkl, .audience, .metacritic, .letterboxd, .mdblist, .trakt])
    }

    func testSelectionOnlyKeepsWhatIsSwitchedOn() {
        let enabled = CardRatingPolicy.enabled(selected: [.simkl, .trakt], keys: [.mdblist])
        XCTAssertEqual(enabled, [.simkl, .trakt])
    }

    func testOrderFollowsDesktopPushOrderWithSimklBeforeRottenTomatoes() {
        let enabled = CardRatingPolicy.enabled(selected: everyProvider, keys: [.omdb, .mdblist])
        XCTAssertEqual(enabled, CardRatingProvider.allCases)
        XCTAssertEqual(enabled.firstIndex(of: .simkl), 3)
        XCTAssertEqual(enabled.firstIndex(of: .rt), 4)
    }

    func testMissingKeyHintNamesTheKeyAScoreNeeds() {
        XCTAssertEqual(CardRatingPolicy.missingKeyHint(.rt, keys: []), "Cards need an OMDb key.")
        XCTAssertEqual(CardRatingPolicy.missingKeyHint(.trakt, keys: [.omdb]), "Cards need an MDBList key.")
        XCTAssertNil(CardRatingPolicy.missingKeyHint(.rt, keys: [.omdb]))
        XCTAssertNil(CardRatingPolicy.missingKeyHint(.simkl, keys: []))
    }

    func testBlankKeysDoNotCount() {
        XCTAssertEqual(CardRatingPolicy.keySources(omdb: "   ", mdblist: "abc123"), [.mdblist])
        XCTAssertEqual(CardRatingPolicy.keySources(omdb: "abc", mdblist: ""), [.omdb])
    }

    func testChipCountTakesOneSlotForImdbTmdbAndMal() {
        XCTAssertEqual(CardRatingPolicy.chipCount([.imdb, .tmdb, .simkl, .rt]), 3)
        XCTAssertEqual(CardRatingPolicy.chipCount([.mal, .imdb, .rt]), 2)
        XCTAssertEqual(CardRatingPolicy.chipCount([]), 0)
    }

    func testLimitRisesToTheCountWhenMoreChipsAreEnabled() {
        XCTAssertEqual(CardRatingPolicy.limitAfterEnabling(previous: 3, current: 4, limit: 3), 4)
        XCTAssertEqual(CardRatingPolicy.limitAfterEnabling(previous: 5, current: 7, limit: 3), 6)
        XCTAssertEqual(CardRatingPolicy.limitAfterEnabling(previous: 4, current: 3, limit: 3), 3)
        XCTAssertEqual(CardRatingPolicy.limitAfterEnabling(previous: 1, current: 2, limit: 5), 5)
    }

    func testChipsStopAtTheLimitAndNeverGoBelowOne() {
        let scores = CardRatingScores(omdb: omdb(rt: 92), mdblist: nil, simkl: 8.5)
        let enabled = CardRatingPolicy.enabled(selected: [.simkl, .rt, .imdb], keys: [.omdb])
        let two = CardRatingPolicy.chips(anime: false, inlineRating: "8.1", inlineSource: nil, scores: scores, enabled: enabled, limit: 2)
        XCTAssertEqual(two.map(\.text), ["8.1", "9"])
        let none = CardRatingPolicy.chips(anime: false, inlineRating: "8.1", inlineSource: nil, scores: scores, enabled: enabled, limit: 0)
        XCTAssertEqual(none.map(\.text), ["8.1"])
    }

    func testChipTextsFollowDesktopFormatting() {
        let scores = CardRatingScores(omdb: omdb(rt: 92),
                                      mdblist: mdblist(score: 7.6, letterboxd: 3.6, trakt: 88.2, metacritic: 78.4, audience: 85.4),
                                      simkl: 8.5)
        let enabled = CardRatingPolicy.enabled(selected: everyProvider, keys: [.omdb, .mdblist])
        let chips = CardRatingPolicy.chips(anime: false, inlineRating: "8.1", inlineSource: nil, scores: scores, enabled: enabled, limit: 10)
        XCTAssertEqual(chips.map(\.text), ["8.1", "9", "92%", "85%", "78", "1.8", "8", "88%"])
    }

    func testTmdbSourceShowsTheTmdbChipOnly() {
        let enabled = CardRatingPolicy.enabled(selected: [.imdb, .tmdb], keys: [])
        let chips = CardRatingPolicy.chips(anime: false, inlineRating: "7.9", inlineSource: "TMDB", scores: CardRatingScores(), enabled: enabled, limit: 3)
        XCTAssertEqual(chips, [CardRatingChip(provider: .tmdb, text: "7.9")])
    }

    func testAnimeCardsShowOnlyTheCatalogMalScore() {
        let enabled = CardRatingPolicy.enabled(selected: everyProvider, keys: [.omdb, .mdblist])
        let scores = CardRatingScores(omdb: omdb(rt: 90), mdblist: nil, simkl: 8.0)
        let chips = CardRatingPolicy.chips(anime: true, inlineRating: "8.7", inlineSource: nil, scores: scores, enabled: enabled, limit: 3)
        XCTAssertEqual(chips, [CardRatingChip(provider: .mal, text: "8.7")])
    }

    func testOnlyEnabledSourcesAreRequested() {
        XCTAssertEqual(CardRatingPolicy.needs(anime: true, enabled: [.mal], inlineRating: "8.7", inlineSource: nil), [])
        XCTAssertEqual(CardRatingPolicy.needs(anime: false, enabled: [.imdb], inlineRating: "8.1", inlineSource: nil), [])
        XCTAssertEqual(CardRatingPolicy.needs(anime: false, enabled: [.imdb], inlineRating: nil, inlineSource: nil), [.omdb])
        XCTAssertEqual(CardRatingPolicy.needs(anime: false, enabled: [.rt, .trakt], inlineRating: nil, inlineSource: nil), [.omdb, .mdblist])
        XCTAssertEqual(CardRatingPolicy.needs(anime: false, enabled: [.simkl], inlineRating: nil, inlineSource: nil), [.simkl])
    }

    func testOmdbPrefetchStopsAtNinetyPercentOfTheDailyAllowance() {
        XCTAssertTrue(OmdbBudget(used: 899).allowsPrefetch)
        XCTAssertFalse(OmdbBudget(used: 900).allowsPrefetch)
        XCTAssertFalse(OmdbBudget(used: 0, keyInvalid: true).allowsPrefetch)
    }

    func testImdbIDComesFromTheIdOrTheImdbField() {
        var fromField = Media(id: "kitsu:1", type: "series", name: "Show")
        fromField.imdbID = "tt0903747"
        XCTAssertEqual(CardRatingPolicy.imdbID(fromField), "tt0903747")
        XCTAssertEqual(CardRatingPolicy.imdbID(Media(id: "tt0111161", type: "movie", name: "Film")), "tt0111161")
        XCTAssertNil(CardRatingPolicy.imdbID(Media(id: "kitsu:1", type: "series", name: "Show")))
    }
}
