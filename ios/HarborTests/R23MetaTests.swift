import XCTest
@testable import Harbor

/// Metadata gaps closed against Desktop 0.9.132: OMDb awards, the custom-meta poster rule.
final class R23MetaTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    // MARK: OMDb awards (Desktop's parseAwards in lib/providers/omdb.ts)

    func testOmdbAwardsReadsWinsNominationsAndTotals() {
        let awards = OmdbAwardsParser.parse("Won 4 Oscars. 45 wins & 80 nominations.")
        XCTAssertEqual(awards?.oscarsWon, 4)
        XCTAssertEqual(awards?.oscarsNominated, 0)
        XCTAssertEqual(awards?.totalWins, 45)
        XCTAssertEqual(awards?.totalNominations, 80)
    }

    func testOmdbAwardsReadsNominationsAndTheOtherCeremonies() {
        let awards = OmdbAwardsParser.parse("Nominated for 2 Oscars. Won 1 Primetime Emmy. Nominated for 3 BAFTA Awards. Won 2 Golden Globes.")
        XCTAssertEqual(awards?.oscarsNominated, 2)
        XCTAssertEqual(awards?.emmysWon, 1)
        XCTAssertEqual(awards?.baftasNominated, 3)
        XCTAssertEqual(awards?.globesWon, 2)
        XCTAssertEqual(awards?.oscarsWon, 0)
    }

    func testOmdbAwardsIsNilWithoutACount() {
        XCTAssertNil(OmdbAwardsParser.parse(nil))
        XCTAssertNil(OmdbAwardsParser.parse(""))
        XCTAssertNil(OmdbAwardsParser.parse("N/A"))
        XCTAssertNil(OmdbAwardsParser.parse("Unknown"))
    }

    func testOmdbParserCarriesAwardsIntoScores() throws {
        let reply = try json(#"{"Response":"True","imdbRating":"7.1","imdbVotes":"1,000","Awards":"Won 1 Oscar. 3 wins & 5 nominations.","Ratings":[]}"#)
        guard case .scores(let scores) = OmdbParser.parse(reply, now: Date(timeIntervalSince1970: 0)) else { return XCTFail("Expected scores") }
        XCTAssertEqual(scores.awards?.oscarsWon, 1)
        XCTAssertEqual(scores.awards?.totalNominations, 5)
    }

    // MARK: Custom-meta poster rule (Desktop's resolveMeta in lib/meta-resource.ts)

    private let cinemetaWithPoster = MetaPosterPreference.MetaAnswer(isCinemeta: true, hasPoster: true)
    private let cinemetaWithoutPoster = MetaPosterPreference.MetaAnswer(isCinemeta: true, hasPoster: false)
    private let customWithPoster = MetaPosterPreference.MetaAnswer(isCinemeta: false, hasPoster: true)
    private let customWithoutPoster = MetaPosterPreference.MetaAnswer(isCinemeta: false, hasPoster: false)

    func testPreferredCustomAnswerWithoutPosterIsFilledFromCinemeta() {
        let choice = MetaPosterPreference.choose([cinemetaWithPoster, customWithoutPoster], preferCustom: true)
        XCTAssertEqual(choice, .init(index: 1, fillArtwork: true))
    }

    func testPreferredCustomPosterWinsOverCinemeta() {
        let choice = MetaPosterPreference.choose([customWithoutPoster, customWithPoster, cinemetaWithPoster], preferCustom: true)
        XCTAssertEqual(choice, .init(index: 1, fillArtwork: false))
    }

    func testWithoutThePreferenceCinemetaWithPosterWins() {
        let choice = MetaPosterPreference.choose([cinemetaWithPoster, customWithoutPoster], preferCustom: false)
        XCTAssertEqual(choice, .init(index: 0, fillArtwork: false))
    }

    func testWithoutThePreferenceCustomPosterBeatsCinemetaWithoutPoster() {
        let choice = MetaPosterPreference.choose([customWithPoster, cinemetaWithoutPoster], preferCustom: false)
        XCTAssertEqual(choice, .init(index: 0, fillArtwork: false))
        let cinemetaFirst = MetaPosterPreference.choose([cinemetaWithoutPoster, customWithPoster], preferCustom: false)
        XCTAssertEqual(cinemetaFirst, .init(index: 1, fillArtwork: false))
    }

    func testCinemetaWithoutPosterIsReturnedWhenNothingElseHasOne() {
        XCTAssertEqual(MetaPosterPreference.choose([cinemetaWithoutPoster], preferCustom: false), .init(index: 0, fillArtwork: false))
        XCTAssertEqual(MetaPosterPreference.choose([customWithoutPoster], preferCustom: false), .init(index: nil, fillArtwork: false))
        XCTAssertEqual(MetaPosterPreference.choose([], preferCustom: true), .init(index: nil, fillArtwork: false))
    }

    // MARK: Subtitle auto-selection order (Desktop's rankSubtitleCandidates in lib/subtitles/candidate-ranking.ts)

    private func candidate(_ url: String, lang: String = "en", forced: Bool = false, foreignOnly: Bool = false, downloads: Int = 0,
                           confidence: String? = nil, score: Double? = nil) -> SubtitleProviderCandidate {
        SubtitleProviderCandidate(subtitle: PlaybackSource.Subtitle(url: url, lang: lang), provider: .wyzie, forced: forced,
                                  foreignOnly: foreignOnly, downloads: downloads, matchConfidence: confidence, matchScore: score)
    }

    func testForcedAndForeignOnlyTracksAreNeverAutoPicked() {
        let plain = candidate("https://example.test/plain.srt")
        let ranked = SubtitleCandidateRanking.rank([candidate("https://example.test/forced.srt", forced: true), candidate("https://example.test/foreign.srt", foreignOnly: true), plain], preferredLanguages: [])
        XCTAssertEqual(ranked.map(\.subtitle.url), [plain.subtitle.url])
    }

    func testPreferredLanguagesDropOthersAndExactLanguageComesFirst() {
        let german = candidate("https://example.test/de.srt", lang: "de")
        let english = candidate("https://example.test/en.srt", lang: "en")
        let ranked = SubtitleCandidateRanking.rank([german, english], preferredLanguages: ["en"])
        XCTAssertEqual(ranked.map(\.subtitle.url), [english.subtitle.url])
    }

    func testExactProviderMatchBeatsHighAndDownloadsBreakTies() {
        let exact = candidate("https://example.test/exact.srt", confidence: "exact", score: 0.5)
        let high = candidate("https://example.test/high.srt", confidence: "high", score: 0.9)
        XCTAssertEqual(SubtitleCandidateRanking.rank([high, exact], preferredLanguages: []).map(\.subtitle.url), [exact.subtitle.url, high.subtitle.url])
        let fewer = candidate("https://example.test/few.srt", downloads: 10, confidence: "medium")
        let more = candidate("https://example.test/more.srt", downloads: 50, confidence: "medium")
        XCTAssertEqual(SubtitleCandidateRanking.rank([fewer, more], preferredLanguages: []).map(\.subtitle.url), [more.subtitle.url, fewer.subtitle.url])
    }

    // MARK: Wikidata people awards (Desktop's fetchAwards kind and collapseAwards key in lib/providers/wikidata.ts)

    func testPersonAwardKindFollowsTheIMDbPrefix() {
        XCTAssertEqual(PersonAwardRules.kind(imdbID: "nm0000123", isSeries: true), "person")
        XCTAssertEqual(PersonAwardRules.kind(imdbID: "tt0000123", isSeries: true), "series")
        XCTAssertEqual(PersonAwardRules.kind(imdbID: "tt0000123", isSeries: false), "movie")
    }

    func testPersonAwardKeyKeepsTheWorkAndFallsBackToItsTitle() {
        XCTAssertEqual(PersonAwardRules.collapseKey(awardName: "Academy Award for Best Actor", category: "Best Actor", workIMDb: "tt0111161", workTitle: "Film"),
                       "academy award for best actor|best actor|tt0111161")
        XCTAssertEqual(PersonAwardRules.collapseKey(awardName: "Saturn Award", category: nil, workIMDb: nil, workTitle: "Film"), "saturn award||Film")
    }

    func testProviderScoreAbove100IsReadAsAPercentage() {
        XCTAssertEqual(SubtitleCandidateRanking.providerScore(candidate("https://example.test/a.srt", score: 85)), 0.85, accuracy: 0.0001)
        XCTAssertEqual(SubtitleCandidateRanking.providerScore(candidate("https://example.test/b.srt", score: 2)), 0.02, accuracy: 0.0001)
        XCTAssertEqual(SubtitleCandidateRanking.providerScore(candidate("https://example.test/c.srt")), 0)
    }
}
