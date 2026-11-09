import XCTest
@testable import Harbor

final class AnimeSearchTests: XCTestCase {
    func testSearchPortsMatchDesktopSelectorsAndBoundInput() throws {
        let query = "Cowboy Bebop & more"
        let jikan = try XCTUnwrap(URLComponents(url: try XCTUnwrap(AnimeSearchRequest.jikanURL(query: query)), resolvingAgainstBaseURL: false))
        let jikanItems = Dictionary(uniqueKeysWithValues: (jikan.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(jikan.host, "api.jikan.moe")
        XCTAssertEqual(jikan.path, "/v4/anime")
        XCTAssertEqual(jikanItems, ["q": query, "order_by": "popularity", "sort": "asc", "limit": "8", "sfw": "true"])

        let kitsu = try XCTUnwrap(URLComponents(url: try XCTUnwrap(AnimeSearchRequest.kitsuURL(query: query)), resolvingAgainstBaseURL: false))
        let kitsuItems = Dictionary(uniqueKeysWithValues: (kitsu.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(kitsu.host, "kitsu.io")
        XCTAssertEqual(kitsu.path, "/api/edge/anime")
        XCTAssertEqual(kitsuItems, ["filter[text]": query, "page[limit]": "8", "sort": "-userCount"])
        XCTAssertTrue(AnimeSearchRequest.aniListQuery.contains("media(search: $q, type: ANIME, sort: SEARCH_MATCH)"))
        XCTAssertTrue(AnimeSearchRequest.aniListQuery.contains("countryOfOrigin"))

        XCTAssertNil(AnimeSearchRequest.normalizedQuery("A"))
        XCTAssertNil(AnimeSearchRequest.normalizedQuery("Cowboy\nBebop"))
        XCTAssertNil(AnimeSearchRequest.normalizedQuery(String(repeating: "x", count: AnimeSearchRequest.maximumQueryBytes + 1)))
        XCTAssertEqual(AnimeSearchRequest.normalizedQuery("  Cowboy Bebop  "), "Cowboy Bebop")
    }

    func testSearchMergeKeepsTheWinningProviderMediaInDesktopOrder() {
        let anilist = Media(id: "anilist:1", type: "series", name: "Cowboy Bebop")
        let duplicateMal = Media(id: "mal:1", type: "series", name: "Cowboy Bebop (TV)")
        let kitsu = Media(id: "kitsu:2", type: "movie", name: "Kitsu Film")
        let merged = SearchRanking.mergeAnime([
            [AnimeSearchCandidate(malId: 1, name: anilist.name, media: anilist)],
            [AnimeSearchCandidate(malId: 1, name: duplicateMal.name, media: duplicateMal),
             AnimeSearchCandidate(malId: 0, name: kitsu.name, media: kitsu)],
        ])

        XCTAssertEqual(merged.map(\.name), ["Cowboy Bebop", "Kitsu Film"])
        XCTAssertEqual(merged.compactMap(\.media?.id), ["anilist:1", "kitsu:2"])
    }

    func testKitsuMovieAndFilmSearchHitsUseNativePlayableIdsAndKinds() throws {
        let movie = try XCTUnwrap(AnimeService.kitsuSearchCandidate(json("""
        {"type":"anime","id":"8801","attributes":{"subtype":"movie","titles":{"en":"Anime Film"},"canonicalTitle":"Anime Film","startDate":"2024-04-03","averageRating":"81.5","posterImage":{"medium":"https://images.example/poster.jpg"},"coverImage":{"large":"https://images.example/cover.jpg"},"synopsis":"A story"}}
        """)))
        XCTAssertEqual(movie.malId, 0)
        XCTAssertEqual(movie.media?.id, "kitsu:8801")
        XCTAssertEqual(movie.media?.type, "movie")
        XCTAssertEqual(movie.media?.poster, "https://images.example/poster.jpg")
        XCTAssertTrue(AnimeService.isAnime(try XCTUnwrap(movie.media?.id)))

        let film = try XCTUnwrap(AnimeService.kitsuSearchCandidate(json("""
        {"type":"anime","id":"8802","attributes":{"subtype":"film","titles":{"en":"Second Film"}}}
        """)))
        XCTAssertEqual(film.media?.type, "movie")
        XCTAssertEqual(film.media?.id, "kitsu:8802")

        let series = try XCTUnwrap(AnimeService.kitsuSearchCandidate(json("""
        {"type":"anime","id":"8803","attributes":{"subtype":"TV","titles":{"en":"Anime Series"}}}
        """)))
        let seriesMedia = try XCTUnwrap(series.media)
        XCTAssertEqual(seriesMedia.type, "series")
        XCTAssertTrue(seriesMedia.episodic)
        XCTAssertTrue(AnimeService.isAnime(seriesMedia.id))
    }

    func testJikanSearchMapsMovieKindAndRejectsNonHTTPSArtwork() throws {
        let hit = try XCTUnwrap(AnimeService.jikanSearchCandidate(json("""
        {"mal_id":123,"type":"Movie","title_english":"  The Film  ","title":"Film","year":2022,"images":{"jpg":{"image_url":"http://insecure.example/poster.jpg","large_image_url":"https://images.example/large.jpg"}},"trailer":{"images":{"maximum_image_url":"https://images.example/banner.jpg"}},"score":8.4,"synopsis":"A story"}
        """)))
        XCTAssertEqual(hit.malId, 123)
        XCTAssertEqual(hit.media?.id, "mal:123")
        XCTAssertEqual(hit.media?.name, "The Film")
        XCTAssertEqual(hit.media?.type, "movie")
        XCTAssertEqual(hit.media?.poster, "https://images.example/large.jpg")
        XCTAssertTrue(AnimeService.isAnime(try XCTUnwrap(hit.media?.id)))
    }

    func testNeutralAnimeRowOmitsTitlesAlreadyPresentInAddonSearch() throws {
        let present = Media(id: "addon:film", type: "series", name: "Cowboy Bebop", poster: "https://example/poster.jpg", releaseInfo: "1998")
        let duplicate = Media(id: "mal:1", type: "series", name: "Cowboy Bebop", poster: "https://example/poster.jpg", releaseInfo: "1998")
        let fresh = Media(id: "kitsu:2", type: "movie", name: "Kitsu Film", poster: "https://example/poster.jpg")

        let row = try XCTUnwrap(SearchAnimeSource.row(metas: [duplicate, fresh], excluding: [present]))
        XCTAssertEqual(row.id, "anime-search")
        XCTAssertEqual(row.plan.title, "Anime")
        XCTAssertEqual(row.plan.kind, "anime")
        XCTAssertEqual(row.metas.map(\.id), ["kitsu:2"])
        XCTAssertNil(SearchAnimeSource.row(metas: [], excluding: []))
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
}
