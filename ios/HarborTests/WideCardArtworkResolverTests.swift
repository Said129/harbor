import XCTest
@testable import Harbor

private actor OwnedWideCardTransport: CardArtworkTransport {
    let responses: [CardArtworkRequest: JSONValue]
    private(set) var requests: [CardArtworkRequest] = []
    init(_ responses: [CardArtworkRequest: JSONValue]) { self.responses = responses }
    func get(_ request: CardArtworkRequest, configuration: MetadataConfiguration) async throws -> JSONValue {
        requests.append(request)
        guard let value = responses[request] else { throw HarborError(code: "owned-unplanned-wide-request") }; return value
    }
}

final class WideCardArtworkResolverTests: XCTestCase {
    private var configuration: MetadataConfiguration { .init(tmdbKey: "owned-synthetic-key", region: "US", language: "en-US", translateTitles: true) }
    private func emptyAnime() -> AnimeArtwork { AnimeArtwork(seed: Data(#"{"v":1,"art":{}}"#.utf8), fetch: { _ in throw HarborError(code: "owned-offline-wide-art") }) }
    func testWideCandidatesUseStableTMDBRankingThenPublicTVDBAndOwnBackdropWithoutLeakingTheTMDBKey() async throws {
        let imdb = "tt1234567", own = "https://owned.invalid/own.jpg"
        var media = Media(id: imdb, type: "movie", name: "Owned film"); media.background = own
        let transport = OwnedWideCardTransport([
            .tmdbFind(imdb): .object(["movie_results": .array([.object(["id": .integer(100)])])]),
            .tmdbImages(kind: "movie", id: 100, languages: "en,null"): .object(["backdrops": .array([
                .object(["file_path": .string("/low.jpg"), "vote_average": .integer(1)]),
                .object(["file_path": .string("/first.jpg"), "vote_average": .integer(8)]),
                .object(["file_path": .string("/tie.jpg"), "vote_average": .integer(8)])])]),
            .tvdbIMDb(imdb): .object(["backgrounds": .array([.string("https://owned.invalid/tvdb.jpg"), .string(own)])])])
        let resolver = CardArtworkResolver(transport: transport, anime: emptyAnime())
        var config = configuration; config.imageLanguages = ["English", "Original"]
        let urls = await resolver.wideCandidates(media, configuration: config)
        XCTAssertEqual(urls, ["https://image.tmdb.org/t/p/w1280/first.jpg", "https://image.tmdb.org/t/p/w1280/tie.jpg", "https://image.tmdb.org/t/p/w1280/low.jpg", "https://owned.invalid/tvdb.jpg", own])
        let requests = await transport.requests; XCTAssertEqual(Set(requests), Set(transportResponses(imdb)))
        let publicURL = try CardArtworkRequest.tvdbIMDb(imdb).url(configuration: config)
        XCTAssertTrue(publicURL.hasSuffix("/api/tvdb/artwork?imdb=" + imdb)); XCTAssertFalse(publicURL.contains(config.tmdbKey))
        XCTAssertFalse(CardArtworkRequest.tvdbIMDb(imdb).credentialed)
        XCTAssertThrowsError(try CardArtworkRequest.tvdbIMDb("tt1/path").url(configuration: config))
    }
    private func transportResponses(_ imdb: String) -> [CardArtworkRequest] {
        [.tmdbFind(imdb), .tmdbImages(kind: "movie", id: 100, languages: "en,null"), .tvdbIMDb(imdb)]
    }
    func testSimklUsesPublicDetailsAndVerifiedMappingsWhileDerivedAnimeAvoidsBorrowingTheParentSeriesArt() async throws {
        let transport = OwnedWideCardTransport([
            .simklAnime(7): .object(["ids": .object(["kitsu": .integer(8), "tvdb": .integer(9), "imdb": .string("tt1234567")])]),
            .tvdb(9): .object(["backgrounds": .array([.string("https://owned.invalid/simkl-wide.jpg")])]),
            .mapping("mal:11"): .object(["mappings": .object(["mal_id": .integer(11), "kitsu_id": .integer(12), "thetvdb_id": .integer(13)])]),
            .anime(kind: "series", id: "kitsu:12"): .object(["meta": .object(["background": .string("https://owned.invalid/ova-own.jpg")])])])
        let resolver = CardArtworkResolver(transport: transport, anime: emptyAnime())
        var config = configuration; config.tmdbKey = ""
        let simkl = await resolver.wideCandidates(Media(id: "simkl:7", type: "series", name: "Owned anime"), configuration: config)
        XCTAssertEqual(simkl, ["https://owned.invalid/simkl-wide.jpg"])
        var ova = Media(id: "mal:11", type: "series", name: "Owned extra"); ova.animeFormat = "OVA"
        let derived = await resolver.wideCandidates(ova, configuration: config); XCTAssertEqual(derived, ["https://owned.invalid/ova-own.jpg"])
        let requests = await transport.requests
        XCTAssertFalse(requests.contains(.tvdb(13))); XCTAssertFalse(requests.contains(.mapping("kitsu:12")))
        XCTAssertFalse(try CardArtworkRequest.simklAnime(7).url(configuration: config).contains("owned-synthetic-key"))
    }
}
