import XCTest
@testable import Harbor

private actor EntryEpisodeFixture {
    private var available: Set<String>
    private var calls: [String: Int] = [:]
    private var active = 0
    private var maximum = 0
    init(_ ids: Set<String>) { available = ids }
    func enable(_ id: String) { available.insert(id) }
    func stats() -> ([String: Int], Int) { (calls, maximum) }
    func fetch(_ entry: AnimeFranchiseEntry) async throws -> Media {
        calls[entry.id, default: 0] += 1; active += 1; maximum = max(maximum, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(10))
        guard available.contains(entry.id) else { throw HarborError(code: "http-404") }
        var media = entry.media
        media.videos = [Episode(id: entry.id + ":1", season: 1, episode: 1)]
        return media
    }
}

@MainActor private final class PoolTestContext { var revision = UUID() }

final class AnimeEpisodePoolTests: XCTestCase {
    private func media(_ id: Int, season: Int, count: Int = 2) -> Media {
        var value = Media(id: "kitsu:\(id)", type: "series", name: "Synthetic Season \(id)")
        value.videos = (1...count).map { (number: Int) in Episode(id: "kitsu:\(id):\(number)", season: 1, episode: number, imdbSeason: season, imdbEpisode: number, tvdbSeriesID: 42) }
        return value
    }
    private func entry(_ id: Int) -> AnimeFranchiseEntry {
        AnimeFranchiseEntry(media: media(id, season: id), year: 2020, startDate: "2020-01-01", episodeCount: 2, subtype: "TV", current: false, upcoming: false)
    }
    private func order(_ rows: [(Int, Int, Int, Int)]) throws -> TVDBEpisodeOrder {
        let values = try rows.map { id, season, number, absolute in
            try XCTUnwrap(TVDBOrderEpisode(.object(["id": .integer(Int64(id)), "seasonNumber": .integer(Int64(season)),
                "number": .integer(Int64(number)), "absoluteNumber": .integer(Int64(absolute))])))
        }
        return try XCTUnwrap(TVDBEpisodeOrder.build(seriesID: 42, kind: .aired, canonical: values, alternative: values, series: .null))
    }
    private func projection(_ pool: AnimeEpisodePool) throws -> EpisodeOrderProjection {
        try XCTUnwrap(EpisodeOrderProjection.build(order([(101, 1, 1, 1), (102, 1, 2, 2), (201, 2, 1, 3), (202, 2, 2, 4)]), source: pool.episodes, animeIdentity: true))
    }
    private func mapping(_ episodes: String, kitsu: Int = 1) throws -> JSONValue {
        let text = #"{"mappings":{"kitsu_id":KITSU,"thetvdb_id":42,"imdb_id":"tt1234567"},"episodes":EPISODES}"#
            .replacingOccurrences(of: "KITSU", with: String(kitsu)).replacingOccurrences(of: "EPISODES", with: episodes)
        return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testSourceArraysKeepTheirOrderIDsAndIndependentWatchedBitsets() throws {
        var first = media(1, season: 1); first.videos?.reverse()
        let second = media(2, season: 2), pool = AnimeEpisodePool(current: first, others: [second])
        let projected = try projection(pool)
        let selected = try XCTUnwrap(projected.sections.last?.episodes.first)
        let source = try XCTUnwrap(pool.source(for: selected, presentation: projected))
        XCTAssertEqual(source.id, second.id)
        XCTAssertEqual(source.videos?.map(\.id), second.videos?.map(\.id))
        XCTAssertEqual(source.videos?.map(\.watchedKey), ["1:1", "1:2"])
        XCTAssertEqual(source.videos?.first?.listedSeason, 2)
        XCTAssertEqual(pool.sources[first.id]?.videos?.map(\.id), first.videos?.map(\.id))
        let encoded = try WatchedCodec.encode(["1:1"], videos: source.videos ?? [])
        XCTAssertEqual(try WatchedCodec.decode(encoded, videos: second.videos ?? []), ["1:1"])
        XCTAssertEqual(source.videos?.count, 2); XCTAssertEqual(projected.videos.count, 4)
    }

    func testNextAndPreviousCrossCourBoundaryWithoutCollidingOnRawSeasonOne() throws {
        let pool = AnimeEpisodePool(current: media(1, season: 1), others: [media(2, season: 2)])
        let projected = try projection(pool)
        let end = ResumeTarget(id: "kitsu:1", season: 1, episode: 2, videoId: "kitsu:1:2")
        let next = try XCTUnwrap(EpisodeSequence.adjacent(projected.videos, current: end, presentation: projected).next)
        XCTAssertEqual(next.id, "kitsu:2:1"); XCTAssertEqual(next.sourceMetaID, "kitsu:2")
        XCTAssertEqual(next.watchedKey, "1:1"); XCTAssertEqual(next.listedSeason, 2)
        let target = ResumeTarget(id: "kitsu:2", season: 1, episode: 1, videoId: next.id)
        XCTAssertFalse(pool.episodes[0].belongs(to: target))
        XCTAssertEqual(EpisodeSequence.adjacent(projected.videos, current: target, presentation: projected).previous?.id, "kitsu:1:2")
        XCTAssertEqual(EpisodeSequence.adjacent(projected.videos, current: target, presentation: projected).next?.id, "kitsu:2:2")
    }

    func testIdenticalVideoIDsInDifferentSourcesRetainDifferentNavigationIdentity() throws {
        var first = media(1, season: 1, count: 1), second = media(2, season: 2, count: 1)
        first.videos?[0] = Episode(id: "shared-video", season: 1, episode: 1, imdbSeason: 1, imdbEpisode: 1)
        second.videos?[0] = Episode(id: "shared-video", season: 1, episode: 1, imdbSeason: 2, imdbEpisode: 1)
        let pool = AnimeEpisodePool(current: first, others: [second])
        let projected = try XCTUnwrap(EpisodeOrderProjection.build(order([(1, 1, 1, 1), (2, 2, 1, 2)]), source: pool.episodes, animeIdentity: true))
        XCTAssertEqual(Set(projected.videos.map(\.routingKey)).count, 2)
        XCTAssertEqual(EpisodeSequence.ordered(projected.videos, presentation: projected).count, 2)
        let target = ResumeTarget(id: second.id, season: 1, episode: 1, videoId: "shared-video")
        XCTAssertEqual(projected.videos.filter { $0.belongs(to: target) }.count, 1)
        XCTAssertEqual(EpisodeSequence.adjacent(projected.videos, current: target, presentation: projected).previous?.sourceMetaID, first.id)
    }

    func testResumeAndWatchedUseTheActualSourceInsteadOfAnotherCoursMatchingPair() throws {
        let pool = AnimeEpisodePool(current: media(1, season: 1), others: [media(2, season: 2)])
        let projected = try projection(pool)
        let finished = LibraryRecord(raw: .object(["_id": .string("kitsu:1"), "state": .object([
            "video_id": .string("kitsu:1:2"), "season": .integer(1), "episode": .integer(2),
            "timeOffset": .integer(100_000), "duration": .integer(100_000), "flaggedWatched": .integer(1)])]))
        let watched: [String: Set<String>] = ["kitsu:1": ["1:1", "1:2"], "kitsu:2": ["1:1"]]
        let next = EpisodeSequence.startingEpisode(projected.videos, record: finished, watched: [], presentation: projected, watchedBySource: watched)
        XCTAssertEqual(next?.id, "kitsu:2:2")
        var partial = finished.raw.objectValue
        partial["state"] = .object(["video_id": .string("kitsu:1:2"), "season": .integer(1), "episode": .integer(2), "timeOffset": .integer(20_000), "duration": .integer(100_000)])
        XCTAssertEqual(EpisodeSequence.startingEpisode(projected.videos, record: LibraryRecord(raw: .object(partial)), watched: [], presentation: projected, watchedBySource: watched)?.id, "kitsu:1:2")
        XCTAssertEqual(EpisodeSequence.startingEpisode(projected.videos, record: nil, watched: [], presentation: projected,
            watchedBySource: ["kitsu:1": [], "kitsu:2": ["1:1"]])?.id, "kitsu:1:1")
    }

    func testPairCorrectsStaleTVDBIDAndForeignSeriesDoesNotStealASlot() throws {
        var first = media(1, season: 1)
        first.videos?[1].tvdbEpisodeID = 101
        var foreign = media(3, season: 2, count: 1); foreign.videos?[0].tvdbSeriesID = 999
        let pool = AnimeEpisodePool(current: first, others: [foreign])
        let projected = try XCTUnwrap(EpisodeOrderProjection.build(order([(101, 1, 1, 1), (102, 1, 2, 2), (201, 2, 1, 3)]), source: pool.episodes, animeIdentity: true, currentSourceID: first.id))
        XCTAssertEqual(projected.sections[0].episodes.map(\.id), ["kitsu:1:1", "kitsu:1:2"])
        XCTAssertEqual(projected.unmatchedProviderIDs, [201])
        XCTAssertEqual(projected.sections.count, 1)
        XCTAssertEqual(projected.unmatchedFranchiseSourceKeys, ["kitsu:3|kitsu:3:1"])
        XCTAssertTrue(projected.applies(to: projected.videos)); XCTAssertFalse(projected.applies(to: pool.episodes))
        XCTAssertEqual(pool.sources[foreign.id]?.videos?.count, 1, "The sibling remains accessible through its own real metadata")
    }

    func testExplicitFranchiseAbsoluteNumbersAreUsedWithoutBorrowingCourLocalNumbers() throws {
        var first = media(1, season: 1, count: 1), second = media(2, season: 1, count: 1)
        first.videos?[0].imdbSeason = nil; first.videos?[0].imdbEpisode = nil; first.videos?[0].absoluteNumber = 13
        second.videos?[0].imdbSeason = nil; second.videos?[0].imdbEpisode = nil; second.videos?[0].absoluteNumber = 25
        let pool = AnimeEpisodePool(current: first, others: [second])
        let projected = try XCTUnwrap(EpisodeOrderProjection.build(order([(1, 1, 1, 1), (13, 2, 1, 13), (25, 3, 1, 25)]), source: pool.episodes, animeIdentity: true))
        XCTAssertEqual(projected.unmatchedProviderIDs, [1])
        XCTAssertEqual(projected.sections.map(\.number), [2, 3])
        XCTAssertEqual(projected.sections.map { $0.episodes.first?.sourceMetaID }, [first.id, second.id])
    }

    func testMappingRejectsShiftedAndDuplicateIDsAndAllowsVerifiedDifferentLocalNumber() throws {
        let original = media(1, season: 1, count: 3).videos ?? []
        let value = try mapping(#"{"1":{"seasonNumber":1,"episodeNumber":1,"tvdbId":101,"absoluteEpisodeNumber":1},"2":{"seasonNumber":1,"episodeNumber":2,"tvdbId":101,"absoluteEpisodeNumber":2},"3":{"seasonNumber":1,"episodeNumber":2,"tvdbId":103,"absoluteEpisodeNumber":3}}"#)
        let result = AnimeEpisodeService.applying(value, canonical: original, to: original, animeIdentity: true)
        XCTAssertEqual(result[0].tvdbEpisodeID, 101); XCTAssertNil(result[1].tvdbEpisodeID)
        XCTAssertNil(result[2].tvdbEpisodeID); XCTAssertNil(result[2].verifiedIMDBCoordinates)
        let raw = [Episode(id: "kitsu:1:14", season: 1, episode: 14)]
        let verified = AnimeEpisodeService.applying(try mapping(#"{"14":{"seasonNumber":2,"episodeNumber":1,"tvdbId":201,"absoluteEpisodeNumber":14}}"#), canonical: raw, to: raw, animeIdentity: true)
        var source = media(1, season: 1); source.videos = verified
        XCTAssertEqual(verified[0].watchedKey, "1:14"); XCTAssertEqual(verified[0].verifiedIMDBCoordinates, true)
        XCTAssertEqual(StreamRequestPolicy.ids(source, videoID: raw[0].id, season: 1, episode: 14), ["kitsu:1:14", "tt1234567:2:1"])
    }

    func testHunterMappingGuardKeepsAnotherArcsImageAndIdentityOutOfEpisodeFiftyNine() throws {
        let source = [Episode(id: "kitsu:6448:59", season: 1, episode: 59, thumbnail: "https://example.invalid/correct.jpg")]
        let value = try mapping(#"{"59":{"seasonNumber":2,"episodeNumber":59,"tvdbId":4798644,"absoluteEpisodeNumber":117,"image":"https://example.invalid/wrong.jpg"}}"#, kitsu: 6448)
        let result = AnimeEpisodeService.applying(value, canonical: source, to: source, animeIdentity: true)
        XCTAssertEqual(result[0].thumbnail, source[0].thumbnail)
        XCTAssertNil(result[0].tvdbEpisodeID); XCTAssertNil(result[0].absoluteNumber); XCTAssertNil(result[0].imdbSeason)
        XCTAssertEqual(result[0].id, source[0].id); XCTAssertEqual(result[0].watchedKey, source[0].watchedKey)
    }

    func testPublicEntriesCoalesceBoundConcurrencyAndRetryOnlyTheFailedEntry() async throws {
        let entries = (1...8).map(entry), transport = EntryEpisodeFixture(Set((1...7).map { "kitsu:\($0)" }))
        let service = AnimeFranchiseEpisodeService(fetch: { try await transport.fetch($0) })
        async let first = service.entries(entries, language: "es-ES")
        async let second = service.entries(entries, language: "es-ES")
        let (a, b) = await (first, second)
        XCTAssertEqual(a.sources.map(\.id), b.sources.map(\.id)); XCTAssertEqual(a.missing, ["kitsu:8"])
        let (calls, maximum) = await transport.stats()
        XCTAssertLessThanOrEqual(maximum, 4)
        for number in 1...7 { XCTAssertEqual(calls["kitsu:\(number)"], 1) }
        await transport.enable("kitsu:8")
        let recovered = await service.entries(entries, language: "es-ES")
        XCTAssertTrue(recovered.missing.isEmpty); XCTAssertEqual(recovered.sources.count, 8)
        let (retries, _) = await transport.stats()
        for number in 1...7 { XCTAssertEqual(retries["kitsu:\(number)"], 1) }
        XCTAssertEqual(retries["kitsu:8"], (calls["kitsu:8"] ?? 0) + 1)
    }

    @MainActor func testDetailRoutesTheActualSessionResumeSubtitlesAndMetadataToTheSelectedEntry() async throws {
        let root = media(1, season: 1), child = media(2, season: 2), library = LibraryModel(), context = PoolTestContext()
        let model = DetailModel(root, service: HarborService(), metadataLoaded: true, contextRevision: { context.revision })
        model.franchise = AnimeFranchise(currentID: root.id, rootID: root.id, entries: [entry(1), entry(2)], complete: true)
        model.activeFranchiseEntryID = root.id
        let variants = AnimeEpisodeVariants(seasons: root.videos ?? [], continuous: root.videos ?? [])
        await model.loadAnimeEpisodes(owner: library.owner, library: library, fetch: { _ in variants }, supplement: { value, _ in value })
        await model.loadFranchiseEpisodes(language: "es-ES", owner: library.owner, library: library, provider: AnimeFranchiseEpisodeService(fetch: { _ in child }))
        let pool = try XCTUnwrap(model.episodePool), episode = try XCTUnwrap(pool.episodes.first { $0.sourceMetaID == child.id })
        XCTAssertEqual(model.media.videos?.count, 2)
        XCTAssertNil(model.sourceMedia(for: Episode(id: episode.id, season: 1, episode: 1, sourceMetaID: "kitsu:999")))
        await model.findStreams([], episode: episode)
        XCTAssertEqual(model.selectedPlaybackMedia?.id, child.id)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pool-resume-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = UserDefaults.standard, savedResume = defaults.object(forKey: "resumePlayback"), savedPrompt = defaults.object(forKey: "resumePrompt")
        defaults.set(true, forKey: "resumePlayback"); defaults.set(false, forKey: "resumePrompt")
        defer { defaults.set(savedResume, forKey: "resumePlayback"); defaults.set(savedPrompt, forKey: "resumePrompt") }
        let resume = ResumeStore(fileURL: file); try await resume.load()
        _ = try await resume.save(ResumeTarget(id: root.id, season: 1, episode: 1, videoId: "kitsu:1:1"), snapshot: ResumeSnapshot(positionMs: 30_000, durationMs: 1_000_000, timestampMs: 1, exiting: true))
        _ = try await resume.save(ResumeTarget(id: child.id, season: 1, episode: 1, videoId: episode.id), snapshot: ResumeSnapshot(positionMs: 60_000, durationMs: 1_000_000, timestampMs: 1, exiting: true))
        await model.play(StreamOffer(id: 0, raw: .object(["addonId": .string("owned-test-source"), "addonName": .string("Owned synthetic source"), "url": .string("https://example.invalid/owned-synthetic.mkv")])), resume: resume, library: library)
        let session = try XCTUnwrap(model.playback, model.error ?? "No playback session was published")
        XCTAssertEqual(session.target.id, child.id); XCTAssertEqual(session.target.videoId, episode.id)
        XCTAssertEqual(session.startMs, 60_000); XCTAssertEqual(session.media?.id, child.id)
        XCTAssertEqual(session.subtitleRequest?.media.id, child.id); XCTAssertEqual(session.subtitleRequest?.videoID, episode.id)
    }

    @MainActor func testLatePublicPoolCannotAttachAfterTheSameOwnersProfileActivationChanges() async throws {
        let root = media(1, season: 1), child = media(2, season: 2), library = LibraryModel(), context = PoolTestContext()
        let model = DetailModel(root, service: HarborService(), metadataLoaded: true, contextRevision: { context.revision })
        model.franchise = AnimeFranchise(currentID: root.id, rootID: root.id, entries: [entry(1), entry(2)], complete: true)
        model.activeFranchiseEntryID = root.id
        let variants = AnimeEpisodeVariants(seasons: root.videos ?? [], continuous: root.videos ?? [])
        await model.loadAnimeEpisodes(owner: library.owner, library: library, fetch: { _ in variants }, supplement: { value, _ in value })
        let provider = AnimeFranchiseEpisodeService(fetch: { _ in
            await MainActor.run { context.revision = UUID() }; return child
        })
        await model.loadFranchiseEpisodes(language: "es-ES", owner: library.owner, library: library, provider: provider)
        XCTAssertNil(model.episodePool); XCTAssertFalse(model.loadingEpisodePool)
        XCTAssertEqual(model.media.id, root.id)
    }
}
