import XCTest
@testable import Harbor

private actor OwnedCardArtworkTransport: CardArtworkTransport {
    let responses: [CardArtworkRequest: JSONValue]
    private(set) var requests: [CardArtworkRequest] = []
    init(_ responses: [CardArtworkRequest: JSONValue]) { self.responses = responses }
    func get(_ request: CardArtworkRequest, configuration: MetadataConfiguration) async throws -> JSONValue {
        requests.append(request)
        try await Task.sleep(for: .milliseconds(15))
        guard let value = responses[request] else { throw HarborError(code: "owned-unplanned-artwork-request") }
        return value
    }
}

final class CardArtworkResolverTests: XCTestCase {
    private var configuration: MetadataConfiguration { .init(tmdbKey: "owned-synthetic-key", region: "US", language: "en-US", translateTitles: true) }
    private func emptyAnime() -> AnimeArtwork {
        AnimeArtwork(seed: Data(#"{"v":1,"art":{}}"#.utf8), fetch: { _ in throw HarborError(code: "owned-offline-art-index") })
    }
    func testConcurrentCardsCoalesceActualProviderRequestsAndPublicURLsNeverReceiveTheTMDBKey() async throws {
        let catalog = CardArtworkRequest.cinemeta(kind: "movie", id: "tt1234567")
        let transport = OwnedCardArtworkTransport([.curated: .object(["logos": .object([:])]), catalog: .object(["meta": .object(["logo": .string("https://owned.invalid/logo.png")])])])
        let resolver = CardArtworkResolver(transport: transport, anime: emptyAnime())
        let media = Media(id: "tt1234567", type: "movie", name: "Owned title")
        let configuration = configuration
        let results = await withTaskGroup(of: ResolvedCardArtwork.self) { group in
            for _ in 0..<8 { group.addTask { await resolver.resolve(media, configuration: configuration) } }
            var result: [ResolvedCardArtwork] = []; for await item in group { result.append(item) }; return result
        }
        XCTAssertEqual(results.count, 8); XCTAssertTrue(results.allSatisfy { $0.logo == "https://owned.invalid/logo.png" })
        let requests = await transport.requests; XCTAssertEqual(requests, [.curated, catalog])
        for request in requests {
            let url = try request.url(configuration: configuration)
            XCTAssertFalse(url.contains(configuration.tmdbKey)); XCTAssertFalse(request.credentialed)
        }
        let key = CardArtworkResolver.cacheKey(media, configuration)
        XCTAssertEqual(key.count, 64); XCTAssertFalse(key.contains(configuration.tmdbKey))
        let target = try XCTUnwrap(URLComponents(string: CardArtworkRequest.tmdbImages(kind: "movie", id: 100, languages: "es,en,null").url(configuration: configuration)))
        XCTAssertEqual(target.host, "api.themoviedb.org")
        XCTAssertEqual(target.queryItems?.first { $0.name == "api_key" }?.value, configuration.tmdbKey)
        XCTAssertThrowsError(try CardArtworkRequest.cinemeta(kind: "movie", id: "tt1/path").url(configuration: configuration))
    }
    func testLocalizedTMDBArtOverridesCuratedAndOwnLogosWhileAnExplicitPinAlwaysWins() async {
        var media = Media(id: "tt1234567", type: "movie", name: "Owned title"); media.logo = "https://owned.invalid/own.png"
        let transport = OwnedCardArtworkTransport([
            .curated: .object(["logos": .object([media.id: .string("https://owned.invalid/curated.png")])]),
            .tmdbFind(media.id): .object(["movie_results": .array([.object(["id": .integer(100)])])]),
            .tmdbImages(kind: "movie", id: 100, languages: "es,en,null"): .object(["logos": .array([
                .object(["file_path": .string("/english.png"), "iso_639_1": .string("en"), "vote_average": .integer(10)]),
                .object(["file_path": .string("/spanish.png"), "iso_639_1": .string("es")])])])])
        let resolver = CardArtworkResolver(transport: transport, anime: emptyAnime())
        var configuration = configuration; configuration.language = "es-ES"; configuration.imageLanguages = ["Spanish", "English", "Original"]
        let localized = await resolver.resolve(media, configuration: configuration)
        XCTAssertEqual(localized.logo, "https://image.tmdb.org/t/p/w500/spanish.png")
        let before = await transport.requests
        let pinned = await resolver.resolve(media, configuration: configuration, pinnedLogo: "https://owned.invalid/pinned.png")
        XCTAssertEqual(pinned.logo, "https://owned.invalid/pinned.png")
        let after = await transport.requests; XCTAssertEqual(after, before)
        configuration.language = "en-US"; configuration.imageLanguages = ["English", "Original"]
        let original = await resolver.resolve(media, configuration: configuration)
        XCTAssertEqual(original.logo, "https://owned.invalid/curated.png")
    }
    func testAnimeCardsReuseStaticArtAndResolveVerifiedAliasesWhileDerivedFormatsAvoidTVDBBorrowing() async throws {
        let staticArt = AnimeArtwork(seed: Data(#"{"v":1,"art":{"mal:1":{"bg":"https://owned.invalid/static-wide.jpg","logo":"https://owned.invalid/static-logo.png"}}}"#.utf8), fetch: { _ in throw HarborError(code: "owned-offline-art-index") })
        let mapping: JSONValue = .object(["mappings": .object(["mal_id": .integer(7), "kitsu_id": .integer(8), "thetvdb_id": .integer(9)])])
        let transport = OwnedCardArtworkTransport([
            .curated: .object(["logos": .object([:])]), .mapping("mal:7"): mapping,
            .anime(kind: "series", id: "kitsu:8"): .object(["meta": .object(["id": .string("kitsu:8"), "name": .string("Owned anime")])]),
            .tvdb(9): .object(["clearLogos": .array([.string("https://owned.invalid/tvdb-logo.png")]), "backgrounds": .array([.string("https://owned.invalid/tvdb-wide.jpg")])])])
        let resolver = CardArtworkResolver(transport: transport, anime: staticArt)
        var configuration = configuration; configuration.tmdbKey = ""
        let first = await resolver.resolve(Media(id: "mal:1", type: "series", name: "Owned static anime"), configuration: configuration)
        XCTAssertEqual(first.logo, "https://owned.invalid/static-logo.png"); XCTAssertEqual(first.backdrop, "https://owned.invalid/static-wide.jpg")
        var requests = await transport.requests; XCTAssertEqual(requests, [.curated])
        var media = Media(id: "mal:7", type: "series", name: "Owned anime")
        let mapped = await resolver.resolve(media, configuration: configuration)
        XCTAssertEqual(mapped.logo, "https://owned.invalid/tvdb-logo.png"); XCTAssertEqual(mapped.backdrop, "https://owned.invalid/tvdb-wide.jpg")
        media.animeFormat = "OVA"
        let derived = await resolver.resolve(media, configuration: configuration)
        XCTAssertNil(derived.logo); XCTAssertNil(derived.backdrop)
        requests = await transport.requests
        XCTAssertEqual(requests.filter { $0 == .tvdb(9) }.count, 1)
        XCTAssertFalse(requests.contains(.mapping("kitsu:8")))
    }
}
