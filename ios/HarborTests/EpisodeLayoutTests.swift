import XCTest
@testable import Harbor

private func episodeGroup(_ id: String, type: Int64, count: Int64) -> JSONValue {
    .object(["id": .string(id), "name": .string("Group " + id), "type": .integer(type), "group_count": .integer(count)])
}

private func episodeGroupRef(_ season: Int64, _ episode: Int64) -> JSONValue {
    .object(["season_number": .integer(season), "episode_number": .integer(episode)])
}

private func storyArc(_ id: String, order: Int64, episodes: [JSONValue]) -> JSONValue {
    .object(["id": .string(id), "name": .string("Arc " + id), "order": .integer(order), "episodes": .array(episodes)])
}

private func video(_ season: Int, _ episode: Int) -> Episode {
    Episode(id: "e\(season)x\(episode)", season: season, episode: episode, name: nil, title: nil, thumbnail: nil, overview: nil, released: nil, imdbID: nil, imdbSeason: nil, imdbEpisode: nil)
}

final class EpisodeLayoutTests: XCTestCase {
    func testLayoutFallsBackToListForMissingOrUnknownValues() {
        XCTAssertEqual(EpisodeLayoutPolicy.layout(nil), .list)
        XCTAssertEqual(EpisodeLayoutPolicy.layout("bogus"), .list)
        XCTAssertEqual(EpisodeLayoutPolicy.layout("strip"), .strip)
        XCTAssertEqual(EpisodeLayoutPolicy.layout("grid"), .grid)
        XCTAssertEqual(EpisodeLayoutPolicy.Layout.allCases.map(\.rawValue), ["list", "strip", "grid"])
    }

    func testDesktopDefaultsAndChoices() {
        XCTAssertEqual(EpisodeLayoutPolicy.defaultLayout, .list)
        XCTAssertEqual(EpisodeLayoutPolicy.defaultCardScale, 1)
        XCTAssertEqual(EpisodeLayoutPolicy.cardScaleChoices, [1, 1.2, 1.45])
    }

    func testCardScaleFallsBackToOne() {
        XCTAssertEqual(EpisodeLayoutPolicy.cardScale(nil), 1)
        XCTAssertEqual(EpisodeLayoutPolicy.cardScale(0), 1)
        XCTAssertEqual(EpisodeLayoutPolicy.cardScale(-2), 1)
        XCTAssertEqual(EpisodeLayoutPolicy.cardScale(Double.nan), 1)
        XCTAssertEqual(EpisodeLayoutPolicy.cardScale(1.45), 1.45)
    }

    func testStripAndGridWidthsScaleLikeDesktop() {
        XCTAssertEqual(EpisodeLayoutPolicy.stripWidth(1), 244)
        XCTAssertEqual(EpisodeLayoutPolicy.stripWidth(1.2), 293)
        XCTAssertEqual(EpisodeLayoutPolicy.stripWidth(1.45), 354)
        XCTAssertEqual(EpisodeLayoutPolicy.stripWidth(nil), 244)
        XCTAssertEqual(EpisodeLayoutPolicy.gridMinimumWidth(1), 232)
        XCTAssertEqual(EpisodeLayoutPolicy.gridMinimumWidth(1.2), 278)
        XCTAssertEqual(EpisodeLayoutPolicy.gridMinimumWidth(1.45), 336)
        XCTAssertEqual(EpisodeLayoutPolicy.gridMinimumWidth(0), 232)
    }

    func testTVIDComesFromTMDBMediaIDsOnly() {
        XCTAssertEqual(EpisodeArcPolicy.tvID(forMediaID: "tmdb:tv:1429"), 1429)
        XCTAssertNil(EpisodeArcPolicy.tvID(forMediaID: "tmdb:movie:1429"))
        XCTAssertNil(EpisodeArcPolicy.tvID(forMediaID: "tt0388629"))
        XCTAssertNil(EpisodeArcPolicy.tvID(forMediaID: "tmdb:tv:0"))
    }

    func testStoryGroupPicksTheLargestTypeFiveGroup() {
        let results: JSONValue = .object(["results": .array([
            episodeGroup("a", type: 5, count: 3), episodeGroup("b", type: 6, count: 9), episodeGroup("c", type: 5, count: 7)
        ])])
        XCTAssertEqual(EpisodeArcPolicy.storyGroup(results)?.id, "c")
        XCTAssertEqual(EpisodeArcPolicy.storyGroup(results)?.name, "Group c")
    }

    func testStoryGroupTieKeepsTMDBOrderAndNoStoryGroupIsNil() {
        let tied: JSONValue = .object(["results": .array([episodeGroup("x", type: 5, count: 4), episodeGroup("y", type: 5, count: 4)])])
        XCTAssertEqual(EpisodeArcPolicy.storyGroup(tied)?.id, "x")
        let none: JSONValue = .object(["results": .array([episodeGroup("z", type: 2, count: 4)])])
        XCTAssertNil(EpisodeArcPolicy.storyGroup(none))
        XCTAssertNil(EpisodeArcPolicy.storyGroup(.object([:])))
    }

    func testArcsKeepTMDBOrderAndDropInvalidEntries() {
        let detail: JSONValue = .object(["groups": .array([
            storyArc("second", order: 2, episodes: [episodeGroupRef(1, 3)]),
            storyArc("first", order: 1, episodes: [episodeGroupRef(1, 1), .object(["season_number": .integer(1)]), episodeGroupRef(1, 2)]),
            storyArc("empty", order: 0, episodes: [.object([:])])
        ])])
        let arcs = EpisodeArcPolicy.arcs(detail)
        XCTAssertEqual(arcs.map(\.id), ["first", "second"])
        XCTAssertEqual(arcs[0].episodes, [EpisodeArc.Ref(season: 1, episode: 1), EpisodeArc.Ref(season: 1, episode: 2)])
        XCTAssertEqual(arcs[1].episodes, [EpisodeArc.Ref(season: 1, episode: 3)])
    }

    func testArcEpisodesFollowArcOrderAndSkipMissingOnes() {
        let arc = EpisodeArc(id: "a", name: "Arc", order: 0, episodes: [
            EpisodeArc.Ref(season: 2, episode: 1), EpisodeArc.Ref(season: 9, episode: 9), EpisodeArc.Ref(season: 1, episode: 4)
        ])
        let videos = [video(1, 4), video(2, 1), video(2, 2)]
        XCTAssertEqual(EpisodeArcPolicy.episodes(of: arc, in: videos).map(\.id), ["e2x1", "e1x4"])
    }

    func testEpisodeDisplaySettingsAreKeptPerProfile() {
        XCTAssertTrue(ProfileSettingsStore.keys.isSuperset(of: ["episodeLayout", "episodeCardScale", "episodeArcGroups"]))
    }
}
