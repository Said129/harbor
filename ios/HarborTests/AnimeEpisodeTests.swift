import XCTest
@testable import Harbor

final class AnimeEpisodeTests: XCTestCase {
    private func json(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func corrected() throws -> (Media, [Episode]) {
        let source = try XCTUnwrap(Media.parse(json("dbs-source"), kind: "series"))
        let canonical = try XCTUnwrap(Media.parse(json("dbs-canonical"), kind: "series"))
        return (source, AnimeEpisodeService.applying(try json("dbs-mapping"), canonical: canonical.videos ?? [], to: source.videos ?? [], animeIdentity: false))
    }
    func testSuperHasOneContinuousSeasonAndArtworkPastFourteen() throws {
        let (_, episodes) = try corrected()
        let ordinary = episodes.filter { ($0.season ?? 0) > 0 }
        XCTAssertEqual(ordinary.count, 131)
        XCTAssertEqual(Set(ordinary.compactMap(\.listedSeason)), [1])
        XCTAssertEqual(Set(ordinary.compactMap(\.listedEpisode)), Set(1...131))
        for number in [15, 77, 131] {
            let episode = try XCTUnwrap(ordinary.first { $0.listedEpisode == number })
            XCTAssertEqual(URL(string: episode.thumbnail ?? "")?.host, "artworks.thetvdb.com")
        }
        XCTAssertEqual(episodes.filter { $0.season == 0 }.count, 2, "Specials must stay separate")
    }
    func testPresentationKeepsOriginalStreamsResumeWatchedAndNextEpisode() throws {
        let (source, episodes) = try corrected()
        XCTAssertEqual(episodes.map(\.id), source.videos?.map(\.id))
        XCTAssertEqual(episodes.map(\.watchedKey), source.videos?.map(\.watchedKey))
        let fifteen = try XCTUnwrap(episodes.first { $0.listedEpisode == 15 && $0.season != 0 })
        XCTAssertEqual(fifteen.season, 2); XCTAssertEqual(fifteen.episode, 1)
        var media = source; media.videos = episodes
        XCTAssertEqual(StreamRequestPolicy.ids(media, videoID: fifteen.id, season: fifteen.season, episode: fifteen.episode).first, fifteen.id)
        let target = ResumeTarget(id: media.id, season: fifteen.season, episode: fifteen.episode, videoId: fifteen.id)
        let adjacent = EpisodeSequence.adjacent(episodes, current: target)
        XCTAssertEqual(adjacent.previous?.listedEpisode, 14); XCTAssertEqual(adjacent.next?.listedEpisode, 16)
        let old = try JSONDecoder().decode(Episode.self, from: Data(#"{"id":"old:2:1","season":2,"episode":1}"#.utf8))
        XCTAssertNil(old.displaySeason); XCTAssertEqual(old.listedSeason, 2)
        XCTAssertEqual(try JSONDecoder().decode(Episode.self, from: JSONEncoder().encode(fifteen)), fifteen)
    }
    func testIncompleteOrAmbiguousMappingNeverCollapsesRealSeasons() throws {
        let source = try XCTUnwrap(Media.parse(json("dbs-source"), kind: "series"))
        let canonical = try XCTUnwrap(Media.parse(json("dbs-canonical"), kind: "series"))
        var originals = source.videos ?? []
        originals.append(Episode(id: "sequel:6:1", season: 6, episode: 1))
        let partial = AnimeEpisodeService.applying(try json("dbs-mapping"), canonical: canonical.videos ?? [], to: originals, animeIdentity: false)
        XCTAssertTrue(partial.allSatisfy { $0.displaySeason == nil })
        let unknown = AnimeEpisodeService.applying(.null, canonical: canonical.videos ?? [], to: originals, animeIdentity: false)
        XCTAssertEqual(unknown, originals)
        var repeated = source.videos ?? []; repeated.append(repeated[10])
        XCTAssertTrue(AnimeEpisodeService.applying(try json("dbs-mapping"), canonical: canonical.videos ?? [], to: repeated, animeIdentity: false).allSatisfy { $0.displaySeason == nil })
    }
    func testAlreadyCanonicalAnimeAndGenuineMultipleSeasonsKeepTheirOrder() throws {
        let canonical = try XCTUnwrap(Media.parse(json("dbs-canonical"), kind: "series"))
        let mapped = AnimeEpisodeService.applying(try json("dbs-mapping"), canonical: canonical.videos ?? [], to: canonical.videos ?? [], animeIdentity: true)
        XCTAssertEqual(mapped.count, 131); XCTAssertEqual(mapped.last?.listedEpisode, 131)
        XCTAssertEqual(mapped.map(\.id), canonical.videos?.map(\.id))
        let real = [Episode(id: "a", season: 1, episode: 1), Episode(id: "b", season: 2, episode: 1)]
        XCTAssertEqual(AnimeEpisodeService.applying(try json("dbs-mapping"), canonical: real, to: real, animeIdentity: false), real, "Duplicate per-season numbers cannot establish a continuous canonical order")
    }
    @MainActor func testPrepareOrdinaryAnimeUISettings() {
        UserDefaults.standard.set(false, forKey: "interface.autoRotateBanners")
        UserDefaults.standard.set(false, forKey: "hideSpoilers")
        UserDefaults.standard.set(AnimeEpisodeGrouping.seasons.rawValue, forKey: AnimeEpisodeGrouping.preferenceKey)
    }
}
