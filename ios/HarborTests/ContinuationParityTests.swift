import XCTest
@testable import Harbor

final class ContinuationParityTests: XCTestCase {
    private func json(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func superMedia() throws -> Media {
        var source = try XCTUnwrap(Media.parse(json("dbs-source"), kind: "series"))
        let canonical = try XCTUnwrap(Media.parse(json("dbs-canonical"), kind: "series"))
        source.videos = AnimeEpisodeService.applying(try json("dbs-mapping"), canonical: canonical.videos ?? [], to: source.videos ?? [], animeIdentity: false)
        return source
    }
    private func record(offset: Int64 = 323_000) -> LibraryRecord {
        LibraryRecord(raw: .object([
            "_id": .string("tt4644488"), "type": .string("series"), "name": .string("Dragon Ball Super"),
            "removed": .bool(false), "temp": .bool(false), "_mtime": .string("2026-10-17T10:00:00Z"),
            "state": .object(["season": .integer(5), "episode": .integer(23), "video_id": .string("tt4644488:5:23"), "timeOffset": .integer(offset), "duration": .integer(1_400_000)])
        ]))
    }
    func testPlaybackAndContinueWatchingUseAbsoluteEpisodeNinetyNine() throws {
        let media = try superMedia(), record = record()
        let target = ResumeTarget(id: media.id, season: 5, episode: 23, videoId: "tt4644488:5:23")
        let coordinates = try XCTUnwrap(EpisodePresentation.coordinates(in: media, target: target))
        XCTAssertEqual(coordinates.caption, "T1 · E99")
        let presentation = ContinueWatchingPresentation(record: record, media: media, watched: [])
        XCTAssertEqual(presentation.coordinates(record: record, media: media)?.compactCaption, "S1E99")
        XCTAssertFalse(presentation.upNext)
        XCTAssertEqual(presentation.progress, record.progress)
        XCTAssertEqual(target.season, 5); XCTAssertEqual(target.episode, 23)
        XCTAssertEqual(presentation.episode?.id, "tt4644488:5:23")
        XCTAssertEqual(presentation.episode?.watchedKey, "5:23")
        let finished = self.record(offset: 1_390_000)
        let next = ContinueWatchingPresentation(record: finished, media: media, watched: [])
        XCTAssertTrue(next.upNext)
        XCTAssertEqual(next.coordinates(record: finished, media: media)?.caption, "T1 · E100")
        XCTAssertEqual(next.episode?.id, "tt4644488:5:24")
    }
    func testEpisodePresentationFallsBackWithoutInventingCoordinates() throws {
        let target = ResumeTarget(id: "real-series", season: 5, episode: 23, videoId: "real-series:5:23")
        let ordinary = Media(id: target.id, type: "series", name: "Series", videos: [Episode(id: target.videoId!, season: 5, episode: 23)])
        XCTAssertEqual(EpisodePresentation.coordinates(in: ordinary, target: target)?.caption, "T5 · E23")
        XCTAssertEqual(EpisodePresentation.coordinates(in: try superMedia(), target: target)?.caption, "T5 · E23", "A different title cannot supply presentation coordinates")
        XCTAssertNil(EpisodePresentation.coordinates(in: nil, target: ResumeTarget(id: "movie")))
        let special = Episode(id: "special", season: 0, episode: 1)
        XCTAssertEqual(EpisodePresentation.coordinates(episode: special)?.caption, "T0 · E1")
        var ambiguous = ordinary
        ambiguous.videos?.append(Episode(id: "other", season: 5, episode: 23, displaySeason: 1, displayEpisode: 99))
        XCTAssertNil(EpisodePresentation.episode(in: ambiguous, target: ResumeTarget(id: target.id, season: 5, episode: 23)))
    }
    @MainActor func testAnimeSelectionRecognizesIMDbAndKeepsDesktopShowsMembership() {
        let imdb = record()
        XCTAssertFalse(ContinueWatchingSelection.includes(imdb, kind: "anime", detectedAnime: []))
        XCTAssertTrue(ContinueWatchingSelection.includes(imdb, kind: "anime", detectedAnime: [imdb.id]))
        XCTAssertTrue(ContinueWatchingSelection.includes(imdb, kind: "series", detectedAnime: [imdb.id]))
        var flagged = imdb.raw.objectValue; flagged["isAnime"] = .bool(true)
        XCTAssertTrue(ContinueWatchingSelection.includes(LibraryRecord(raw: .object(flagged)), kind: "anime", detectedAnime: []))
        var kitsu = flagged; kitsu["_id"] = .string("kitsu:10879")
        XCTAssertTrue(ContinueWatchingSelection.includes(LibraryRecord(raw: .object(kitsu)), kind: "anime", detectedAnime: []))
        XCTAssertFalse(ContinueWatchingSelection.includes(LibraryRecord(raw: .object(kitsu)), kind: "series", detectedAnime: []))
        let japanese = Media(id: "tt4644488", type: "series", name: "Anime", country: "Japan, USA", genres: ["Animation"])
        XCTAssertTrue(AnimeLibraryDetection.hasDirectEvidence(japanese))
        let western = Media(id: "tt0096697", type: "series", name: "Animation", country: "USA", genres: ["Animation"])
        XCTAssertFalse(AnimeLibraryDetection.hasDirectEvidence(western))
    }
    @MainActor func testAnimeDetectionValidatesMappingAndCoalescesConcurrentChecks() async {
        actor Counter {
            var calls = 0
            func check() async -> Bool { calls += 1; try? await Task.sleep(for: .milliseconds(30)); return true }
            func count() -> Int { calls }
        }
        let detector = AnimeLibraryDetection(), counter = Counter()
        let unknown = Media(id: "tt4644488", type: "series", name: "Anime", genres: ["Animation"])
        async let first: Void = detector.detect(unknown, mapping: { _ in await counter.check() })
        async let second: Void = detector.detect(unknown, mapping: { _ in await counter.check() })
        _ = await (first, second)
        let calls = await counter.count()
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(detector.identifiers.contains(unknown.id))
        let western = Media(id: "tt0096697", type: "series", name: "Animation", country: "USA", genres: ["Animation"])
        await detector.detect(western, mapping: { _ in false })
        XCTAssertFalse(detector.identifiers.contains(western.id))
        await detector.detect(Media(id: "tt0944947", type: "series", name: "Live action", country: "USA", genres: ["Drama"]), mapping: { _ in XCTFail("A known live-action title needs no mapping request"); return true })
    }
    @MainActor func testPrepareOrdinaryContinuationUI() async throws {
        let raw = record().raw
        try await LibraryCache().save([raw], owner: "guest")
        let library = LibraryModel(); await library.setSession(nil)
        library.showContinuing(try XCTUnwrap(library.items.first))
        let defaults = UserDefaults.standard
        defaults.set("es", forKey: "uiLanguage")
        defaults.set(false, forKey: "interface.autoRotateBanners")
        defaults.set(false, forKey: "hideSpoilers")
    }
}
