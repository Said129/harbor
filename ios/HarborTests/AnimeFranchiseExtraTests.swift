import XCTest
@testable import Harbor

private actor ExtraMetadataFixture {
    private var replies: [String: Media]
    private var counts: [String: Int] = [:]
    init(_ replies: [String: Media]) { self.replies = replies }
    func replace(_ id: String, with media: Media) { replies[id] = media }
    func calls(_ id: String) -> Int { counts[id] ?? 0 }
    func fetch(_ entry: AnimeFranchiseEntry) async throws -> Media {
        counts[entry.id, default: 0] += 1
        try await Task.sleep(for: .milliseconds(10))
        guard let media = replies[entry.id] else { throw HarborError(code: "http-404") }
        return media
    }
}

@MainActor private final class ExtraTestContext { var revision = UUID() }

final class AnimeFranchiseExtraTests: XCTestCase {
    private func entry(_ id: Int, name: String = "Synthetic Movie", date: String? = "2020-01-01", movie: Bool = true) -> AnimeFranchiseEntry {
        AnimeFranchiseEntry(media: Media(id: "kitsu:\(id)", type: movie ? "movie" : "series", name: name), year: 2020,
            startDate: date, episodeCount: movie ? 1 : 12, subtype: movie ? "movie" : "TV", current: false, upcoming: false)
    }
    private func row(_ id: Int, season: Int, number: Int, name: String, date: String = "2020-01-01") throws -> TVDBOrderEpisode {
        try XCTUnwrap(TVDBOrderEpisode(.object(["id": .integer(Int64(id)), "seasonNumber": .integer(Int64(season)),
            "number": .integer(Int64(number)), "name": .string(name), "aired": .string(date)])))
    }
    private func order(_ canonical: [TVDBOrderEpisode], dvd: [TVDBOrderEpisode]? = nil) throws -> TVDBEpisodeOrder {
        try XCTUnwrap(TVDBEpisodeOrder.build(seriesID: 42, kind: dvd == nil ? .aired : .dvd, canonical: canonical, alternative: dvd ?? canonical, series: .null))
    }
    private func extra(_ entry: AnimeFranchiseEntry, name: String? = nil, date: String = "2020-01-01") throws -> AnimeFranchiseExtra {
        let provider = try order([row(501, season: 0, number: 7, name: name ?? entry.media.name, date: date)])
        let slot = try XCTUnwrap(provider.seasons.first?.episodes.first)
        return AnimeFranchiseExtra(entry: entry, slot: slot)
    }
    @MainActor private func makeModel(_ item: AnimeFranchiseEntry, context: ExtraTestContext) -> DetailModel {
        var root = Media(id: "kitsu:1", type: "series", name: "Synthetic Main Series")
        root.videos = [Episode(id: "kitsu:1:1", season: 1, episode: 1), Episode(id: "kitsu:1:2", season: 1, episode: 2)]
        let model = DetailModel(root, service: HarborService(), metadataLoaded: true, contextRevision: { context.revision })
        model.franchise = AnimeFranchise(currentID: root.id, rootID: root.id, entries: [entry(1, movie: false), item], complete: true)
        model.activeFranchiseEntryID = root.id
        return model
    }

    func testExtraMatchingUsesUnicodeTitleBeforeDateAndClaimsEachRealEntryOnce() throws {
        let byDate = entry(2, name: "A different movie"), byTitle = entry(3, name: "Pokémon: CAFÉ Ⅱ", date: "2021-05-01")
        let target = try extra(byTitle, name: "Poke\u{301}mon Cafe\u{301} Ⅱ")
        let match = AnimeFranchiseExtra.match(target.slot, entries: [byDate, byTitle, entry(4, name: target.name, movie: false)], claimed: [])
        XCTAssertEqual(match?.entry.id, byTitle.id)
        XCTAssertNil(AnimeFranchiseExtra.match(target.slot, entries: [byTitle], claimed: [byTitle.id]))
        XCTAssertNil(AnimeFranchiseExtra.match(target.slot, entries: [entry(4, name: target.name, movie: false)], claimed: []))
    }

    func testExtraDateFallbackIncludesOneDayAndRejectsInvalidOrMoreDistantDates() throws {
        let item = entry(2, name: "Distinct title"), target = try extra(item, name: "Provider special", date: "2020-01-02")
        XCTAssertEqual(AnimeFranchiseExtra.match(target.slot, entries: [item], claimed: [])?.entry.id, item.id)
        XCTAssertNil(AnimeFranchiseExtra.match(try extra(item, name: "Provider special", date: "2020-01-03").slot, entries: [item], claimed: []))
        XCTAssertNil(AnimeFranchiseExtra.match(target.slot, entries: [entry(3, date: "not-a-date")], claimed: []))
        XCTAssertNil(AnimeFranchiseExtra.match(try extra(item, name: "", date: "invalid").slot, entries: [entry(3, name: "", date: nil)], claimed: []))
    }

    func testDVDExtraRowsKeepProviderOrderAndNeverEnterTheSourceWatchedArray() throws {
        let movie = entry(2), source = [Episode(id: "show:1:1", season: 1, episode: 1), Episode(id: "show:1:2", season: 1, episode: 2)]
        let canonical = try [row(101, season: 1, number: 1, name: "One"), row(102, season: 1, number: 2, name: "Two"), row(501, season: 0, number: 1, name: movie.media.name)]
        let dvd = try [row(102, season: 1, number: 1, name: "Two"), row(501, season: 1, number: 2, name: movie.media.name), row(101, season: 1, number: 3, name: "One")]
        let projected = try XCTUnwrap(EpisodeOrderProjection.build(order(canonical, dvd: dvd), source: source, animeIdentity: false, franchise: [movie]))
        let section = try XCTUnwrap(projected.sections.first)
        XCTAssertEqual(section.rows.map(\.id), ["episode:show:1:2", "franchise:kitsu:2|501", "episode:show:1:1"])
        XCTAssertEqual(section.count, 3); XCTAssertTrue(projected.unmatchedProviderIDs.isEmpty)
        XCTAssertEqual(projected.videos.map(\.id), source.map(\.id)); XCTAssertEqual(projected.videos.map(\.watchedKey), source.map(\.watchedKey))
        XCTAssertEqual(section.episodes.count, 2, "A TVDB slot is not a source-provider stream ID")
    }

    func testARealSourceEpisodeWinsOverAnExtraWithTheSameNameAndDate() throws {
        let item = entry(2), source = [Episode(id: "show:0:7", season: 0, episode: 7)]
        let projected = try XCTUnwrap(EpisodeOrderProjection.build(order([row(501, season: 0, number: 7, name: item.media.name)]), source: source, animeIdentity: false, franchise: [item]))
        XCTAssertEqual(projected.sections.first?.rows.first?.id, "episode:show:0:7")
        XCTAssertEqual(projected.sections.first?.count, 1)
        let movieOnly = try XCTUnwrap(EpisodeOrderProjection.build(order([row(501, season: 0, number: 7, name: item.media.name)]), source: [], animeIdentity: true, franchise: [item]))
        XCTAssertTrue(movieOnly.videos.isEmpty); XCTAssertEqual(movieOnly.sections.first?.count, 1)
    }

    func testOneOffPresentationKeepsActualVideoIDsAndDoesNotTreatEverySeriesAsAnime() {
        var anime = entry(2).media
        XCTAssertTrue(AnimeOneOffPresentation.isOneOff(anime)); XCTAssertNil(AnimeOneOffPresentation.playbackEpisode(anime))
        anime.videos = [Episode(id: "kitsu:2", season: nil, episode: nil)]
        XCTAssertNil(AnimeOneOffPresentation.playbackEpisode(anime))
        anime.videos = [Episode(id: "kitsu:2:9", season: 1, episode: 9)]
        XCTAssertEqual(AnimeOneOffPresentation.playbackEpisode(anime)?.id, "kitsu:2:9")
        var series = Media(id: "tt1234567", type: "series", name: "Ordinary show", genres: ["Animation"])
        series.videos = [Episode(id: "tt1234567:1:1", season: 1, episode: 1)]
        XCTAssertFalse(AnimeOneOffPresentation.isOneOff(series))
        series.country = "Japan"; XCTAssertTrue(AnimeOneOffPresentation.isOneOff(series))
        XCTAssertFalse(AnimeOneOffPresentation.isOneOff(series, declaredEpisodes: 12), "A partially loaded series is not a movie")
        series.videos?.append(Episode(id: "tt1234567:1:2", season: 1, episode: 2))
        XCTAssertFalse(AnimeOneOffPresentation.isOneOff(series))
        series.videos = []
        XCTAssertFalse(AnimeOneOffPresentation.isOneOff(series))
        XCTAssertTrue(AnimeOneOffPresentation.isOneOff(series, declaredEpisodes: 1))
    }

    @MainActor func testCurrentMovieDoesNotRequestEpisodeOrdersOrOptionalEpisodeArtwork() async {
        var movie = entry(2).media; movie.videos = [Episode(id: movie.id, season: 1, episode: 1)]
        let context = ExtraTestContext(), library = LibraryModel()
        let model = DetailModel(movie, service: HarborService(), metadataLoaded: true, contextRevision: { context.revision })
        let unchanged = AnimeEpisodeVariants(seasons: movie.videos ?? [], continuous: movie.videos ?? [])
        await model.loadAnimeEpisodes(owner: library.owner, library: library, fetch: { _ in XCTFail("Movies do not need episodic mapping requests"); return unchanged },
            supplement: { value, _ in XCTFail("Movies do not need optional episode still requests"); return value })
        XCTAssertTrue(model.isAnimeOneOff); XCTAssertFalse(model.canLoadEpisodeOrder)
        XCTAssertEqual(model.media.videos?.map(\.id), [movie.id])
    }

    func testPublicMetadataAcceptsAnActualMovieWithoutEpisodesAndRejectsWrongIdentities() async throws {
        let item = entry(2), fixture = ExtraMetadataFixture(["kitsu:2": Media(id: "kitsu:999", type: "movie", name: "Wrong")])
        let provider = AnimeFranchiseEpisodeService(fetch: { try await fixture.fetch($0) })
        do { _ = try await provider.metadata(for: item, language: "es"); XCTFail("Wrong metadata identity accepted") } catch {}
        await fixture.replace(item.id, with: item.media)
        async let first = provider.metadata(for: item, language: "es")
        async let second = provider.metadata(for: item, language: "es")
        let (a, b) = try await (first, second)
        XCTAssertEqual(a.id, item.id); XCTAssertEqual(a, b); XCTAssertNil(a.videos)
        let calls = await fixture.calls(item.id); XCTAssertEqual(calls, 2)
        let seasons = await provider.entries([item], language: "es")
        XCTAssertTrue(seasons.sources.isEmpty); XCTAssertEqual(seasons.missing, [item.id], "Movies remain outside ordinary season pooling")
    }

    @MainActor func testMovieSelectionRoutesItsActualResumeSubtitleAndProgressIdentityWithoutChangingTheMainSeries() async throws {
        let item = entry(2), context = ExtraTestContext(), library = LibraryModel(), model = makeModel(item, context: context)
        var movie = item.media; movie.imdbID = "tt1234567"; movie.behaviorHints = Media.BehaviorHints(defaultVideoId: item.id)
        movie.videos = [Episode(id: item.id, season: 1, episode: 1)]
        let forged = MediaPlaybackSelection(media: movie, episode: nil)
        await model.findStreams([], selection: forged); XCTAssertNil(model.selectedPlaybackMedia)
        let actualMovie = movie
        let provider = AnimeFranchiseEpisodeService(fetch: { _ in actualMovie })
        let result = await model.resolveFranchiseExtra(try extra(item), language: "es", owner: library.owner, library: library, provider: provider)
        let selected = try XCTUnwrap(result)
        XCTAssertNil(selected.episode); XCTAssertEqual(model.media.id, "kitsu:1"); XCTAssertEqual(model.media.videos?.count, 2)
        await model.findStreams([], selection: selected)
        XCTAssertEqual(model.selectedPlaybackMedia?.id, item.id)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("extra-resume-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = UserDefaults.standard, oldResume = defaults.object(forKey: "resumePlayback"), oldPrompt = defaults.object(forKey: "resumePrompt")
        defaults.set(true, forKey: "resumePlayback"); defaults.set(false, forKey: "resumePrompt")
        defer { defaults.set(oldResume, forKey: "resumePlayback"); defaults.set(oldPrompt, forKey: "resumePrompt") }
        let resume = ResumeStore(fileURL: file); try await resume.load()
        _ = try await resume.save(ResumeTarget(id: item.id, season: 1, episode: 1, videoId: item.id), snapshot: ResumeSnapshot(positionMs: 60_000, durationMs: 6_000_000, timestampMs: 1, exiting: true))
        _ = try await resume.save(ResumeTarget(id: item.id, season: 1, episode: 999, videoId: item.id + ":999"), snapshot: ResumeSnapshot(positionMs: 600_000, durationMs: 6_000_000, timestampMs: 3, exiting: true))
        await model.play(StreamOffer(id: 0, raw: .object(["addonId": .string("owned-test-source"), "addonName": .string("Owned synthetic source"), "url": .string("https://example.invalid/owned-movie.mkv")])), resume: resume, library: library)
        let session = try XCTUnwrap(model.playback, model.error ?? "No playback session was published")
        XCTAssertEqual(session.target.id, item.id); XCTAssertNil(session.target.videoId); XCTAssertEqual(session.startMs, 60_000)
        _ = try await resume.save(ResumeTarget(id: item.id), snapshot: ResumeSnapshot(positionMs: 0, durationMs: 6_000_000, timestampMs: 4, exiting: true))
        let reset = try await resume.position(session.target, media: selected.media)
        XCTAssertEqual(reset.ms, 0, "A newer restart must beat the preserved legacy movie key")
        let request = try XCTUnwrap(session.subtitleRequest)
        XCTAssertEqual(request.media.id, item.id); XCTAssertEqual(request.videoID, item.id); XCTAssertNil(request.episode)
        XCTAssertEqual(StreamRequestPolicy.ids(request.media, videoID: request.videoID, season: nil, episode: nil), [item.id, "tt1234567"])
        var fields: [String: JSONValue] = [:]
        try LibraryPlayback.apply(ResumeSnapshot(positionMs: 100_000, durationMs: 100_000, timestampMs: 2, exiting: true), target: session.target, media: selected.media, to: &fields)
        XCTAssertEqual(fields["state"]?["video_id"].string, item.id)
        XCTAssertNil(fields["state"]?["season"].integer); XCTAssertEqual(model.media.id, "kitsu:1")
        XCTAssertEqual(try WatchedCodec.decode(fields["state"]?["watched"].string, videos: selected.media.videos ?? []), ["1:1"])
        var legacy = LibraryRecord.new(selected.media)
        legacy["videos"] = try .encoded(selected.media.videos ?? [])
        legacy["state"] = .object(["video_id": .string(item.id), "season": .integer(1), "episode": .integer(1), "timeOffset": .integer(60_000), "duration": .integer(6_000_000)])
        XCTAssertEqual(LibraryRecord(raw: .object(legacy)).resume(for: session.target)?.entry.ms, 60_000)
        legacy["type"] = .string("series")
        XCTAssertNil(LibraryRecord(raw: .object(legacy)).resume(for: session.target), "Series never adopt a different episode's implicit movie position")
    }

    @MainActor func testSpecialSelectionUsesTheProvidersActualEpisodeInsteadOfGuessingEpisodeOneOrTheTVDBNumber() async throws {
        let item = entry(2), context = ExtraTestContext(), library = LibraryModel(), model = makeModel(item, context: context)
        var source = Media(id: item.id, type: "series", name: "Synthetic OVA")
        source.videos = [Episode(id: "kitsu:2:9", season: 1, episode: 9)]
        let actualSource = source
        let provider = AnimeFranchiseEpisodeService(fetch: { _ in actualSource })
        let result = await model.resolveFranchiseExtra(try extra(item), language: "es", owner: library.owner, library: library, provider: provider)
        let selected = try XCTUnwrap(result)
        XCTAssertEqual(selected.episode?.id, "kitsu:2:9"); XCTAssertEqual(selected.episode?.watchedKey, "1:9")
        XCTAssertEqual(selected.episode?.listedSeason, 0); XCTAssertEqual(selected.episode?.listedEpisode, 7)
        XCTAssertEqual(selected.media.videos?.first?.sourceMetaID, item.id)
        XCTAssertEqual(model.sourceMedia(for: selected.episode)?.id, item.id)
        XCTAssertEqual(model.media.id, "kitsu:1")
    }

    @MainActor func testExtraLoadingRejectsUnknownOwnersEntriesStaleActivationsAndCancelledResults() async throws {
        let item = entry(2), context = ExtraTestContext(), library = LibraryModel(), model = makeModel(item, context: context)
        let provider = AnimeFranchiseEpisodeService(fetch: { item in
            await MainActor.run { context.revision = UUID() }; return item.media
        })
        let slot = try extra(item)
        let wrongOwner = await model.resolveFranchiseExtra(slot, language: "es", owner: "other", library: library, provider: provider)
        XCTAssertNil(wrongOwner)
        let unknown = await model.resolveFranchiseExtra(try extra(entry(999)), language: "es", owner: library.owner, library: library, provider: provider)
        XCTAssertNil(unknown)
        let stale = await model.resolveFranchiseExtra(slot, language: "es", owner: library.owner, library: library, provider: provider)
        XCTAssertNil(stale); XCTAssertTrue(model.loadingExtraEntries.isEmpty)
        let cancelled = Task { await model.resolveFranchiseExtra(slot, language: "es", owner: library.owner, library: library, provider: provider) }
        cancelled.cancel(); let result = await cancelled.value
        XCTAssertNil(result); XCTAssertTrue(model.loadingExtraEntries.isEmpty); XCTAssertNil(model.error)
        XCTAssertEqual(model.media.id, "kitsu:1")
    }
}
