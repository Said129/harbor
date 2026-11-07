import XCTest
@testable import Harbor

/// Desktop's AniList lists (`lib/anilist/lists.ts`, `views/library/anilist-tab.tsx`) and recommendations
/// (`lib/anilist/recommendations.ts`, `franchise-dedupe.ts`, `use-anilist-anime-rails.ts`).
final class AniListListsTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func item(_ id: Int, _ name: String, format: String? = "TV", idMal: Int? = nil, year: Int? = nil, score: Int? = nil) -> AniListListMedia {
        AniListListMedia(id: id, idMal: idMal, romaji: name, english: nil, userPreferred: nil, format: format, episodes: nil,
                         poster: nil, background: nil, description: nil, seasonYear: year, averageScore: score)
    }

    private let collectionJSON = """
    {"MediaListCollection": {"lists": [
      {"status": "CURRENT", "isCustomList": false, "entries": [
        {"id": 1, "status": "CURRENT", "progress": 3, "media": {"id": 10, "idMal": 100, "title": {"romaji": "Alpha", "english": "Alpha", "native": null, "userPreferred": "Alpha"}, "coverImage": {"extraLarge": "x", "large": "l", "medium": null}, "bannerImage": null, "format": "TV", "episodes": 12, "averageScore": 80, "seasonYear": 2020}},
        {"id": 2, "status": "REPEATING", "progress": 1, "media": {"id": 11, "idMal": null, "title": {"romaji": "Beta", "english": null, "native": null, "userPreferred": null}, "coverImage": {}, "bannerImage": null, "format": "MOVIE", "episodes": 1, "averageScore": null, "seasonYear": null}}
      ]},
      {"status": "PLANNING", "isCustomList": true, "entries": [
        {"id": 3, "status": "PLANNING", "progress": 0, "media": {"id": 12, "idMal": null, "title": {"romaji": "Custom", "english": null, "native": null, "userPreferred": null}, "coverImage": {}, "bannerImage": null, "format": "TV", "episodes": null, "averageScore": null, "seasonYear": null}}
      ]},
      {"status": "COMPLETED", "isCustomList": false, "entries": [
        {"id": 4, "status": "COMPLETED", "progress": 24, "media": {"id": 10, "idMal": 100, "title": {"romaji": "Alpha", "english": "Alpha", "native": null, "userPreferred": "Alpha"}, "coverImage": {}, "bannerImage": null, "format": "TV", "episodes": 12, "averageScore": 80, "seasonYear": 2020}},
        {"id": 5, "status": "COMPLETED", "progress": 12, "media": {"id": 13, "idMal": null, "title": {"romaji": "Gamma", "english": "Gamma", "native": null, "userPreferred": null}, "coverImage": {}, "bannerImage": null, "format": "TV", "episodes": null, "averageScore": null, "seasonYear": null}}
      ]},
      {"status": "BOGUS", "isCustomList": false, "entries": [
        {"id": 6, "status": "BOGUS", "progress": 0, "media": {"id": 14, "idMal": null, "title": {"romaji": "Delta", "english": null, "native": null, "userPreferred": null}, "coverImage": {}, "bannerImage": null, "format": "TV", "episodes": null, "averageScore": null, "seasonYear": null}}
      ]}
    ]}}
    """

    private func collection() throws -> [AniListListEntry] {
        AniListLists.parseCollection(try json(collectionJSON))
    }

    func testCollectionSkipsCustomAndUnknownGroupsAndShowsEachTitleOnce() throws {
        let entries = try collection()
        XCTAssertEqual(entries.map(\.media.id), [10, 11, 13])
        XCTAssertEqual(entries.map(\.status), [.current, .repeating, .completed])
        XCTAssertEqual(entries.first?.progress, 3, "the first group keeps its progress")
    }

    func testSectionsFollowDesktopRailOrderAndRepeatingIsWatching() throws {
        let groups = AniListLists.groups(try collection(), kind: .all, query: "")
        XCTAssertEqual(groups.map(\.section), [.watching, .completed])
        XCTAssertEqual(groups.first?.entries.map(\.media.id), [10, 11])
        XCTAssertEqual(groups.last?.entries.map(\.media.id), [13])
        XCTAssertEqual(AniListListSection.allCases.map(\.title), ["Watching", "Plan to Watch", "Completed", "On Hold", "Dropped"])
    }

    func testTypeFilterSplitsMoviesFromShows() throws {
        let entries = try collection()
        XCTAssertEqual(AniListLists.groups(entries, kind: .movie, query: "").flatMap(\.entries).map(\.media.id), [11])
        XCTAssertEqual(AniListLists.groups(entries, kind: .series, query: "").flatMap(\.entries).map(\.media.id), [10, 13])
        XCTAssertEqual(AniListLists.count(entries, kind: .series, query: ""), 2)
    }

    func testSearchIsCaseInsensitiveAndTrimmedAndUsesTheDisplayTitle() throws {
        let entries = try collection()
        XCTAssertEqual(AniListLists.groups(entries, kind: .all, query: "  ALPHA ").flatMap(\.entries).map(\.media.id), [10])
        XCTAssertEqual(AniListLists.groups(entries, kind: .all, query: "gam").flatMap(\.entries).map(\.media.id), [13])
        XCTAssertTrue(AniListLists.groups(entries, kind: .all, query: "zzz").isEmpty)
    }

    func testProgressLabelShowsTheTotalOnlyWhenAniListKnowsIt() throws {
        let entries = try collection()
        XCTAssertEqual(AniListLists.progressLabel(entries[0]), "3 / 12")
        XCTAssertEqual(AniListLists.progressLabel(entries[2]), "12")
    }

    func testHarborTitleUsesMalIdentityAndAniListScore() throws {
        let entries = try collection()
        let alpha = try XCTUnwrap(AniListLists.harborMedia(entries[0].media))
        XCTAssertEqual(alpha.id, "mal:100")
        XCTAssertEqual(alpha.imdbRating, "8.0")
        XCTAssertEqual(alpha.releaseInfo, "2020")
        let gamma = try XCTUnwrap(AniListLists.harborMedia(entries[2].media))
        XCTAssertEqual(gamma.id, "anilist:13")
    }

    func testPlainTextTurnsLineBreaksIntoSpacesAndDropsTags() {
        XCTAssertEqual(AniListLists.plainText("<b>Hi</b><br><br>there"), "Hi there")
    }

    func testRecommendationSeedsAreCompletedThenWatchingCappedAt40() {
        let completed = (1...45).map { AniListListEntry(status: .completed, progress: 0, media: item($0, "Show \($0)")) }
        let seeds = AniListLists.recommendationSeeds(completed)
        XCTAssertEqual(seeds.count, 40)
        XCTAssertEqual(seeds.first, 1)
        XCTAssertEqual(seeds.last, 40)
    }

    func testRecommendationWeightsSumAcrossSeedsAndNegativeRatingsCountAsOne() throws {
        let data = try json("""
        {"Page": {"media": [
          {"id": 10, "recommendations": {"nodes": [
            {"rating": 9, "mediaRecommendation": {"id": 201, "idMal": null, "title": {"romaji": "Solo", "english": null, "userPreferred": null}, "coverImage": {}, "bannerImage": null, "format": "TV", "episodes": null, "averageScore": null, "seasonYear": null}},
            {"rating": 5, "mediaRecommendation": {"id": 200, "idMal": null, "title": {"romaji": "Shared", "english": null, "userPreferred": null}, "coverImage": {}, "bannerImage": null, "format": "TV", "episodes": null, "averageScore": null, "seasonYear": null}},
            {"rating": 9, "mediaRecommendation": {"id": 10, "idMal": null, "title": {"romaji": "On list", "english": null, "userPreferred": null}, "coverImage": {}, "bannerImage": null, "format": "TV", "episodes": null, "averageScore": null, "seasonYear": null}}
          ]}},
          {"id": 11, "recommendations": {"nodes": [
            {"rating": -3, "mediaRecommendation": {"id": 202, "idMal": null, "title": {"romaji": "Negative", "english": null, "userPreferred": null}, "coverImage": {}, "bannerImage": null, "format": "TV", "episodes": null, "averageScore": null, "seasonYear": null}},
            {"rating": 4, "mediaRecommendation": {"id": 200, "idMal": null, "title": {"romaji": "Shared", "english": null, "userPreferred": null}, "coverImage": {}, "bannerImage": null, "format": "TV", "episodes": null, "averageScore": null, "seasonYear": null}},
            {"rating": null, "mediaRecommendation": null}
          ]}}
        ]}}
        """)
        let ranked = AniListLists.rankedRecommendations(data, excluding: [10, 11])
        // Shared: 6 + 5 = 11, which beats Solo's 10 only because the two seeds' weights add up.
        // Negative: a rating below zero still counts as 1, so it comes last.
        XCTAssertEqual(ranked.map(\.id), [200, 201, 202])
    }

    func testFranchiseKeepsTVOverMovieAndTheEarlierSeason() {
        let list = [
            item(1, "Show", format: "TV", year: 2020),
            item(2, "Show Movie", format: "MOVIE", year: 2019),
            item(3, "Show Season 2", format: "TV", year: 2021)
        ]
        XCTAssertEqual(AniListFranchise.dedupe(list).map(\.id), [1])
    }

    func testMusicAndSpecialFormatsAreLeftOut() {
        XCTAssertTrue(AniListFranchise.dedupe([item(5, "Lonely", format: "MUSIC")]).isEmpty)
        XCTAssertTrue(AniListFranchise.dedupe([item(6, "Special Night", format: "SPECIAL")]).isEmpty)
    }

    func testCleanShowNameDropsSeasonSuffixes() {
        XCTAssertEqual(AniListFranchise.cleanShowName("X Season 2"), "X")
        XCTAssertEqual(AniListFranchise.cleanShowName("Attack on Titan Final Season"), "Attack on Titan")
        XCTAssertEqual(AniListFranchise.cleanShowName("Plain"), "Plain")
    }

    func testRecommendationRailNeedsFourTitles() {
        let three = [item(1, "Alpha"), item(2, "Beta"), item(3, "Gamma")]
        XCTAssertTrue(AniListLists.recommendationRail(three).isEmpty)
        let four = three + [item(4, "Delta")]
        XCTAssertEqual(AniListLists.recommendationRail(four).map(\.name), ["Alpha", "Beta", "Gamma", "Delta"])
    }

    func testRecommendationRailIsCappedAt40() {
        let many = (1...45).map { item($0, "Show \($0)") }
        XCTAssertEqual(AniListLists.recommendationRail(many).count, 40)
    }
}
