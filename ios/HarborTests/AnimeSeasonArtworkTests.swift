import XCTest
@testable import Harbor

private actor SeasonArtworkFixture {
    private(set) var calls = 0
    func fetch(_ media: Media, configuration: MetadataConfiguration) async throws -> Media {
        calls += 1
        try await Task.sleep(for: .milliseconds(20))
        var result = media, details = MediaDetails()
        LocalizedMetadataText.apply(.object(["overview": .string("Sinopsis de la serie"), "seasons": .array([
            .object(["season_number": .integer(2), "overview": .string("Sinopsis de la segunda temporada")])])]), language: configuration.language, to: &details)
        result.details = details; return result
    }
}
@MainActor private final class SeasonArtworkContext { var revision = UUID() }

final class AnimeSeasonArtworkTests: XCTestCase {
    private func entry(_ id: Int, date: String? = "2020-01-01", year: Int = 2020, format: String = "TV", background: Bool = true, current: Bool = false) -> AnimeFranchiseEntry {
        var media = Media(id: "kitsu:\(id)", type: format.lowercased() == "movie" ? "movie" : "series", name: "Synthetic season \(id)")
        media.background = background ? "https://example.invalid/season-\(id).jpg" : nil
        media.logo = "https://example.invalid/logo-\(id).png"; media.description = "Entry synopsis \(id)"
        return AnimeFranchiseEntry(media: media, year: year, startDate: date, episodeCount: 12, subtype: format, current: current, upcoming: false)
    }
    func testNearestSeasonArtworkExcludesCurrentSideFormatsAndMissingImages() {
        let root = entry(1, current: true), candidate = entry(2, date: "2020-01-10")
        let ignored = ["OVA", "ona", "special", "Music", "movie"].enumerated().map { entry($0.offset + 10, format: $0.element) }
        let entries = [root, entry(3, background: false)] + ignored + [candidate, entry(4, date: "2020-02-01")]
        XCTAssertEqual(AnimeSeasonArtwork.entry(from: "2020-01-01", franchise: entries, anchorID: root.id)?.id, candidate.id)
        XCTAssertNil(AnimeSeasonArtwork.entry(from: nil, franchise: entries, anchorID: root.id))
        XCTAssertNil(AnimeSeasonArtwork.entry(from: "not-a-date", franchise: entries, anchorID: root.id))
        XCTAssertNil(AnimeSeasonArtwork.entry(from: "2020-01-01", franchise: [candidate], anchorID: root.id))
    }
    func testArtworkDateWindowIncludesExactlyOneHundredFiftyDaysAndUsesJuneThirtyForYears() {
        let root = entry(1, current: true), candidate = entry(2, date: "2020-05-30")
        XCTAssertEqual(AnimeSeasonArtwork.entry(from: "2020-01-01", franchise: [root, candidate], anchorID: root.id)?.id, candidate.id)
        XCTAssertNil(AnimeSeasonArtwork.entry(from: "2020-01-01", franchise: [root, entry(3, date: "2020-05-31")], anchorID: root.id))
        XCTAssertEqual(AnimeSeasonArtwork.entry(from: nil, year: "2020", franchise: [root, entry(4, date: "2020-06-30"), candidate], anchorID: root.id)?.id, "kitsu:4")
        XCTAssertEqual(AnimeSeasonArtwork.entry(from: "invalid", year: "2020", franchise: [root, entry(4, date: nil)], anchorID: root.id)?.id, "kitsu:4")
        XCTAssertEqual(AnimeSeasonArtwork.entry(from: "2020-06", franchise: [root, entry(4, date: "2020-06-01")], anchorID: root.id)?.id, "kitsu:4")
    }
    func testNearestTieKeepsReferenceOrderAndNeverOverridesTheSelectedAnchor() {
        let first = entry(2), second = entry(3)
        XCTAssertEqual(AnimeSeasonArtwork.entry(from: "2020-01-01", franchise: [second, first], anchorID: "kitsu:1")?.id, second.id)
        XCTAssertNil(AnimeSeasonArtwork.entry(from: "2020-01-01", franchise: [first, second], anchorID: first.id))
        XCTAssertEqual(AnimeSeasonArtwork.entry(from: "2020-01-01", franchise: [entry(1), entry(2, current: true)], anchorID: "kitsu:2")?.id, "kitsu:1", "Current flags belong to the active entry when switching back")
    }
    func testSeasonOverviewUsesOnlyTheMatchedSourceAndReferenceTieOrderWithoutChangingEpisodes() throws {
        var root = entry(1, current: true).media, details = MediaDetails()
        details.overviewLanguage = "es-ES"; details.localizedOverview = "Sinopsis localizada de la serie"
        details.seasonOverviews = [2: "Segunda temporada", 3: "Tercera temporada"]
        root.details = details
        var second = Episode(id: "duplicate", season: 1, episode: 1, imdbSeason: 2); second.sourceMetaID = "kitsu:2"
        var third = Episode(id: "duplicate", season: 1, episode: 2, imdbSeason: 3); third.sourceMetaID = "kitsu:2"
        var foreign = Episode(id: "duplicate", season: 1, episode: 3, imdbSeason: 3); foreign.sourceMetaID = "kitsu:9"
        let original = [second, third, foreign, foreign], snapshot = original
        let art = try XCTUnwrap(AnimeSeasonArtwork.presentation(entry(2), root: root, episodes: original, language: "es-MX"))
        XCTAssertEqual(art.description, "Segunda temporada"); XCTAssertEqual(art.entryID, "kitsu:2")
        XCTAssertEqual(art.background, entry(2).media.background); XCTAssertEqual(art.logo, entry(2).media.logo)
        XCTAssertEqual(AnimeSeasonArtwork.presentation(entry(2), root: root, episodes: [third, second], language: "es-ES")?.description, "Tercera temporada")
        XCTAssertEqual(original, snapshot)
        XCTAssertEqual(root.id, "kitsu:1"); XCTAssertEqual(original.map(\.watchedKey), ["1:1", "1:2", "1:3", "1:3"])
    }
    func testSynopsisFallbackKeepsLanguageIsolationAndOlderCachedDetailsDecode() throws {
        var root = entry(1).media, details = MediaDetails()
        details.overviewLanguage = "es-ES"; details.localizedOverview = "Sinopsis traducida"; root.details = details
        XCTAssertEqual(AnimeSeasonArtwork.presentation(entry(2), root: root, episodes: [], language: "es")?.description, "Sinopsis traducida")
        XCTAssertEqual(AnimeSeasonArtwork.presentation(entry(2), root: root, episodes: [], language: "fr")?.description, entry(2).media.description)
        XCTAssertEqual(AnimeSeasonArtwork.presentation(entry(2), root: root, episodes: [], language: "en")?.description, entry(2).media.description)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(details)) as? [String: Any])
        for key in ["overviewLanguage", "localizedOverview", "seasonOverviews"] { legacy.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(MediaDetails.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.overviewLanguage); XCTAssertNil(decoded.localizedOverview); XCTAssertNil(decoded.seasonOverviews)
    }
    func testLocalizedTMDBSeasonParserRejectsUntranslatedScriptsAndRetainsSpecialSeasons() {
        var details = MediaDetails()
        let response: JSONValue = .object(["overview": .string("日本語のあらすじ"), "seasons": .array([
            .object(["season_number": .integer(0), "overview": .string("Especiales de la serie")]),
            .object(["season_number": .integer(2), "overview": .string("Segunda temporada")]),
            .object(["season_number": .integer(3), "overview": .string("日本語のあらすじ")]),
            .object(["season_number": .integer(4), "overview": .string("")])])])
        LocalizedMetadataText.apply(response, language: "es-ES", to: &details)
        XCTAssertNil(details.localizedOverview); XCTAssertEqual(details.seasonOverviews, [0: "Especiales de la serie", 2: "Segunda temporada"])
        for (language, text) in [("ar", "قصة المسلسل"), ("ru", "Описание сериала"), ("ja", "日本語"), ("zh", "中文"), ("ko", "한국어"), ("hi", "कहानी")] {
            XCTAssertTrue(LocalizedMetadataText.accepts(text, language: language)); XCTAssertFalse(LocalizedMetadataText.accepts("English fallback", language: language))
        }
        XCTAssertTrue(LocalizedMetadataText.accepts("English fallback", language: "es"), "Keep Desktop's script heuristic rather than inventing language detection")
        XCTAssertTrue(LocalizedMetadataText.accepts("日本語", language: "en")); XCTAssertFalse(LocalizedMetadataText.accepts("", language: "en"))
    }
    @MainActor private func makeModel(context: SeasonArtworkContext) -> DetailModel {
        var root = entry(1, current: true).media
        root.imdbID = "tt1234567"; root.videos = [Episode(id: "kitsu:1:1", season: 1, episode: 1)]
        let model = DetailModel(root, service: HarborService(), metadataLoaded: true, contextRevision: { context.revision })
        model.franchise = AnimeFranchise(currentID: root.id, rootID: root.id, entries: [entry(1, current: true), entry(2)], complete: true)
        model.activeFranchiseEntryID = root.id; return model
    }
    @MainActor func testOptionalSeasonMetadataLoadsOnceWithoutReplacingPlaybackIdentityAndCanRetryAfterFailure() async throws {
        let context = SeasonArtworkContext(), library = LibraryModel()
        let model = makeModel(context: context), fixture = SeasonArtworkFixture()
        let configuration = MetadataConfiguration(tmdbKey: "owned-test-key", region: "ES", language: "es-ES", translateTitles: true)
        let before = model.media.videos
        await model.loadSeasonArtworkMetadata(configuration: configuration, owner: library.owner, library: library, fetch: { _, _ in throw HarborError(code: "http-503") })
        XCTAssertNil(model.media.details); XCTAssertNil(model.error)
        for _ in 0..<2 { await model.loadSeasonArtworkMetadata(configuration: configuration, owner: library.owner, library: library, fetch: { try await fixture.fetch($0, configuration: $1) }) }
        let calls = await fixture.calls; XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.media.id, "kitsu:1"); XCTAssertEqual(model.media.videos, before)
        XCTAssertEqual(model.media.details?.seasonOverviews?[2], "Sinopsis de la segunda temporada")
    }
    @MainActor func testSeasonMetadataCannotPublishAfterCancellationOwnerOrActivationChanges() async {
        let context = SeasonArtworkContext()
        let fixture = SeasonArtworkFixture(), configuration = MetadataConfiguration(tmdbKey: "owned-test-key", region: "ES", language: "es-ES", translateTitles: true)
        for mode in 0..<3 {
            let library = LibraryModel(), model = makeModel(context: context)
            let owner = library.owner
            let task = Task { await model.loadSeasonArtworkMetadata(configuration: configuration, owner: owner, library: library, fetch: { media, config in
                if mode == 1 { await library.setSession(nil, guestOwner: "another-owner", synchronize: false) }
                if mode == 2 { await MainActor.run { context.revision = UUID() } }
                return try await fixture.fetch(media, configuration: config)
            }) }
            if mode == 0 { task.cancel() }
            await task.value
            XCTAssertNil(model.media.details); XCTAssertNil(model.error)
        }
    }
}
