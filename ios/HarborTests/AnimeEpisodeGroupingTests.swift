import XCTest
@testable import Harbor

final class AnimeEpisodeGroupingTests: XCTestCase {
    private func json(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func fixture() throws -> (Media, [Episode], JSONValue) {
        let source = try XCTUnwrap(Media.parse(json("dbs-source"), kind: "series"))
        let canonical = try XCTUnwrap(Media.parse(json("dbs-canonical"), kind: "series"))
        return (source, canonical.videos ?? [], try json("dbs-mapping"))
    }
    func testBothPresentationsRetainProviderSeasonsArtworkAndTheSamePlaybackIdentity() throws {
        let (source, canonical, mapping) = try fixture()
        let variants = AnimeEpisodeService.variants(mapping: mapping, canonical: canonical, original: source.videos ?? [], animeIdentity: false)
        XCTAssertTrue(variants.allowsContinuous)
        XCTAssertEqual(variants.seasons.map(\.season), source.videos?.map(\.season))
        XCTAssertEqual(variants.seasons.map(\.episode), source.videos?.map(\.episode))
        let target = ResumeTarget(id: source.id, season: 5, episode: 23, videoId: "tt4644488:5:23")
        for grouping in [AnimeEpisodeGrouping.seasons, .continuous, .seasons] {
            var media = source; media.videos = variants.episodes(grouping)
            let selected = try XCTUnwrap(EpisodePresentation.episode(in: media, target: target))
            XCTAssertEqual(selected.id, "tt4644488:5:23"); XCTAssertEqual(selected.watchedKey, "5:23")
            XCTAssertEqual(EpisodePresentation.coordinates(in: media, target: target)?.caption, grouping == .seasons ? "T5 · E23" : "T1 · E99")
            let next = try XCTUnwrap(EpisodeSequence.adjacent(media.videos ?? [], current: target).next)
            XCTAssertEqual(next.id, "tt4644488:5:24")
            XCTAssertEqual(next.listedEpisode, grouping == .seasons ? 24 : 100)
            XCTAssertEqual(URL(string: selected.thumbnail ?? "")?.host, "artworks.thetvdb.com")
            XCTAssertEqual(media.videos?.map(\.id), source.videos?.map(\.id))
            XCTAssertEqual(media.videos?.map(\.watchedKey), source.videos?.map(\.watchedKey))
        }
        XCTAssertEqual(variants.seasons.map(\.thumbnail), variants.continuous.map(\.thumbnail))
        XCTAssertEqual(variants.episodes(.continuous).filter { $0.season == 0 }.count, 2)
    }
    func testPersistedForcedPresentationIsRestoredEvenWhenTheMappingIsUnavailable() throws {
        let (source, canonical, mapping) = try fixture()
        let old = AnimeEpisodeService.applying(mapping, canonical: canonical, to: source.videos ?? [], animeIdentity: false)
        XCTAssertEqual(old.first { $0.id == "tt4644488:5:23" }?.listedEpisode, 99)
        let restored = AnimeEpisodeService.variants(mapping: .null, canonical: [], original: old, animeIdentity: false)
        XCTAssertFalse(restored.allowsContinuous)
        XCTAssertEqual(restored.episodes(.seasons), restored.episodes(.continuous))
        XCTAssertEqual(restored.seasons.map(\.listedSeason), source.videos?.map(\.season))
        XCTAssertEqual(restored.seasons.map(\.listedEpisode), source.videos?.map(\.episode))
        XCTAssertEqual(restored.seasons.map(\.thumbnail), old.map(\.thumbnail))
    }
    func testAnIncompleteMappingOrAlreadyContinuousProviderDoesNotInventAnotherOrder() throws {
        let (source, canonical, mapping) = try fixture()
        var incomplete = source.videos ?? []; incomplete.append(Episode(id: "sequel:6:1", season: 6, episode: 1))
        let partial = AnimeEpisodeService.variants(mapping: mapping, canonical: canonical, original: incomplete, animeIdentity: false)
        XCTAssertFalse(partial.allowsContinuous)
        XCTAssertEqual(partial.episodes(.continuous), partial.seasons)
        XCTAssertEqual(partial.seasons.map(\.listedSeason), incomplete.map(\.season))
        let native = AnimeEpisodeService.variants(mapping: mapping, canonical: canonical, original: canonical, animeIdentity: true)
        XCTAssertFalse(native.allowsContinuous)
        XCTAssertEqual(native.seasons.map(\.listedEpisode), canonical.map(\.episode))
    }
}
