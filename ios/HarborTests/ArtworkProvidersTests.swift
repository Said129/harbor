import XCTest
@testable import Harbor

/// Desktop's RPDB poster URLs (`lib/providers/rpdb.ts`) and Fanart.tv ranking and requests (`lib/providers/fanart.ts`).
final class ArtworkProvidersTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testRPDBImdbPosterURLUsesDefaultHostAndFallback() {
        XCTAssertEqual(
            RatingPosterDB.posterURL(key: "KEY123", metaID: "tt0111161"),
            "https://api.ratingposterdb.com/KEY123/imdb/poster-default/tt0111161.jpg?fallback=true"
        )
    }

    func testRPDBTMDBPosterURLKeepsMediaType() {
        XCTAssertEqual(
            RatingPosterDB.posterURL(key: "KEY123", metaID: "tmdb:movie:603"),
            "https://api.ratingposterdb.com/KEY123/tmdb/poster-default/movie-603.jpg?fallback=true"
        )
        XCTAssertEqual(
            RatingPosterDB.posterURL(key: "KEY123", metaID: "tmdb:tv:1396"),
            "https://api.ratingposterdb.com/KEY123/tmdb/poster-default/series-1396.jpg?fallback=true"
        )
    }

    func testRPDBTVDBPosterURLIsSeries() {
        XCTAssertEqual(
            RatingPosterDB.posterURL(key: "KEY123", metaID: "tvdb:81189"),
            "https://api.ratingposterdb.com/KEY123/tvdb/poster-default/series-81189.jpg?fallback=true"
        )
    }

    func testRPDBAlternateIDFillsTheGapAndItsTypeApplies() {
        // The TVDB card gets its TMDB id from the alternate: TMDB is used, and the alternate's series type applies.
        XCTAssertEqual(
            RatingPosterDB.posterURL(key: "KEY123", metaID: "tvdb:81189", altID: "tmdb:tv:1396"),
            "https://api.ratingposterdb.com/KEY123/tmdb/poster-default/series-1396.jpg?fallback=true"
        )
    }

    func testRPDBImdbWinsOverAlternateTMDBID() {
        // Desktop checks the IMDb id first, so an alternate TMDB id does not change the URL.
        XCTAssertEqual(
            RatingPosterDB.posterURL(key: "KEY123", metaID: "tt0111161", altID: "tmdb:movie:278"),
            "https://api.ratingposterdb.com/KEY123/imdb/poster-default/tt0111161.jpg?fallback=true"
        )
    }

    func testRPDBReturnsNilWithoutUsableKeyOrID() {
        XCTAssertNil(RatingPosterDB.posterURL(key: "", metaID: "tt0111161"))
        XCTAssertNil(RatingPosterDB.posterURL(key: "a/b", metaID: "tt0111161"))
        XCTAssertNil(RatingPosterDB.posterURL(key: "KEY 123", metaID: "tt0111161"))
        XCTAssertNil(RatingPosterDB.posterURL(key: "KEY123", metaID: "kitsu:1"))
        XCTAssertNil(RatingPosterDB.posterURL(key: "KEY123", metaID: "tt12"))
        XCTAssertNil(RatingPosterDB.posterURL(key: "KEY123", metaID: "tmdb:movie:abc"))
    }

    func testFanartRequestsCarryTheKeyAsQuery() {
        XCTAssertEqual(FanartTV.movieURL(key: "test-key", tmdbID: 603), "https://webservice.fanart.tv/v3/movies/603?api_key=test-key")
        XCTAssertEqual(FanartTV.tvURL(key: "test-key", tvdbID: 81189), "https://webservice.fanart.tv/v3/tv/81189?api_key=test-key")
        XCTAssertNil(FanartTV.movieURL(key: "test-key", tmdbID: 0))
        XCTAssertNil(FanartTV.tvURL(key: "", tvdbID: 81189))
    }

    func testFanartLogoPrefersEnglishThenLikesThenHDList() throws {
        let movie = try json(#"""
        {
          "hdmovielogo": [
            {"url": "https://assets.fanart.tv/fr.png", "lang": "fr", "likes": "9"},
            {"url": "https://assets.fanart.tv/en-low.png", "lang": "en", "likes": "1"},
            {"url": "https://assets.fanart.tv/en-top.png", "lang": "en", "likes": "5"},
            {"url": "https://assets.fanart.tv/none.png", "lang": "00", "likes": "100"}
          ],
          "movielogo": [{"url": "https://assets.fanart.tv/plain.png", "lang": "en", "likes": "0"}]
        }
        """#)
        let art = FanartTV.movieArt(movie)
        XCTAssertEqual(art.logo, "https://assets.fanart.tv/en-top.png")
    }

    func testFanartLogoFallsBackWhenTheTopHDItemHasNoURL() throws {
        // Desktop's `pickEnglish(hd) ?? pickEnglish(plain)`: a top item without a url hands over to the plain list.
        let movie = try json(#"""
        {
          "hdmovielogo": [{"lang": "en", "likes": "3"}],
          "movielogo": [{"url": "https://assets.fanart.tv/plain.png", "lang": "en", "likes": "0"}]
        }
        """#)
        XCTAssertEqual(FanartTV.movieArt(movie).logo, "https://assets.fanart.tv/plain.png")
    }

    func testFanartTVLogoUsesClearlogoWhenHDIsEmpty() throws {
        let show = try json(#"""
        {"hdtvlogo": [], "clearlogo": [{"url": "https://assets.fanart.tv/clear.png", "lang": "en", "likes": "2"}]}
        """#)
        XCTAssertEqual(FanartTV.tvArt(show).logo, "https://assets.fanart.tv/clear.png")
    }

    func testFanartBackdropsAreRankedAndFirstIsTheBackdrop() throws {
        let movie = try json(#"""
        {
          "moviebackground": [
            {"url": "https://assets.fanart.tv/b1.jpg", "lang": "fr", "likes": "1"},
            {"url": "https://assets.fanart.tv/b2.jpg", "lang": "en", "likes": "0"},
            {"url": "https://assets.fanart.tv/b3.jpg", "lang": "00", "likes": "9"},
            {"lang": "en", "likes": "50"}
          ]
        }
        """#)
        let art = FanartTV.movieArt(movie)
        XCTAssertEqual(art.backdrops, ["https://assets.fanart.tv/b2.jpg", "https://assets.fanart.tv/b3.jpg", "https://assets.fanart.tv/b1.jpg"])
        XCTAssertEqual(art.backdrop, "https://assets.fanart.tv/b2.jpg")
    }

    func testFanartTiesKeepFanartsOwnOrder() throws {
        let items = try json(#"""
        [
          {"url": "https://assets.fanart.tv/first.png", "lang": "en", "likes": "2"},
          {"url": "https://assets.fanart.tv/second.png", "lang": "en", "likes": "2"}
        ]
        """#).array
        XCTAssertEqual(FanartTV.best(items), "https://assets.fanart.tv/first.png")
    }

    func testFanartPosterAndBannerUseTheirOwnLists() throws {
        let movie = try json(#"""
        {
          "movieposter": [{"url": "https://assets.fanart.tv/poster.jpg", "lang": "en", "likes": "2"}],
          "moviebanner": [{"url": "https://assets.fanart.tv/banner.jpg", "lang": "de", "likes": "0"}]
        }
        """#)
        let art = FanartTV.movieArt(movie)
        XCTAssertEqual(art.poster, "https://assets.fanart.tv/poster.jpg")
        XCTAssertEqual(art.banner, "https://assets.fanart.tv/banner.jpg")
        XCTAssertNil(art.logo)
        XCTAssertEqual(art.backdrops, [])
    }

    func testFanartClientReadsCannedMovieResponse() async throws {
        let body = try json(#"""
        {"hdmovielogo": [{"url": "https://assets.fanart.tv/en.png", "lang": "en", "likes": "4"}]}
        """#)
        let transport = CannedArtworkTransport(body: body)
        let art = await FanartClient(key: "test-key", transport: transport).movie(tmdbID: 603)
        XCTAssertEqual(art?.logo, "https://assets.fanart.tv/en.png")
        let urls = await transport.urls
        XCTAssertEqual(urls, ["https://webservice.fanart.tv/v3/movies/603?api_key=test-key"])
    }

    func testFanartClientReturnsNilOnFailureAndWithoutKey() async throws {
        let failing = CannedArtworkTransport(body: nil)
        let missing = await FanartClient(key: "test-key", transport: failing).tv(tvdbID: 81189)
        XCTAssertNil(missing)

        let unused = CannedArtworkTransport(body: .null)
        let empty = await FanartClient(key: "", transport: unused).tv(tvdbID: 81189)
        XCTAssertNil(empty)
        let calls = await unused.urls.count
        XCTAssertEqual(calls, 0)
    }
}

/// Answers every request with the same canned body, or fails when there is none, and records the URLs asked for.
private actor CannedArtworkTransport: ArtworkJSONTransport {
    private(set) var urls: [String] = []
    private let body: JSONValue?

    init(body: JSONValue?) { self.body = body }

    func json(_ url: String) async throws -> JSONValue {
        urls.append(url)
        guard let body else { throw HarborError(code: "http-404") }
        return body
    }
}
