import XCTest
@testable import Harbor

private actor OwnedLocalizedPosterTransport: CardArtworkTransport {
    let responses: [CardArtworkRequest: JSONValue]
    private(set) var requests: [CardArtworkRequest] = []
    init(_ responses: [CardArtworkRequest: JSONValue]) { self.responses = responses }
    func get(_ request: CardArtworkRequest, configuration: MetadataConfiguration) async throws -> JSONValue {
        requests.append(request); try await Task.sleep(for: .milliseconds(15))
        guard let response = responses[request] else { throw HarborError(code: "owned-unavailable-poster") }; return response
    }
}

final class LocalizedPosterTests: XCTestCase {
    private var configuration: MetadataConfiguration { .init(tmdbKey: "owned-synthetic-key", region: "US", language: "es-ES", translateTitles: true, imageLanguages: ["Spanish", "English", "Original"]) }
    private func resolver(_ transport: OwnedLocalizedPosterTransport) -> CardArtworkResolver {
        CardArtworkResolver(transport: transport, anime: AnimeArtwork(seed: Data(#"{"v":1,"art":{}}"#.utf8), fetch: { _ in throw HarborError(code: "owned-offline") }))
    }
    private var images: JSONValue { .object([
        "posters": .array([.object(["file_path": .string("/poster-es.jpg"), "iso_639_1": .string("es")]), .object(["file_path": .string("/poster-en.jpg"), "iso_639_1": .string("en")])]),
        "logos": .array([.object(["file_path": .string("/logo-es.png"), "iso_639_1": .string("es")])])]) }
    func testPosterLanguageFallbackAndStableVoteRankingMatchNineActualDesktopCases() throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "localized-poster-reference", withExtension: "json", subdirectory: "Fixtures"))
        let original = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(original["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(original["provider_network_requests"], .integer(0))
        let cases = original["cases"].array; XCTAssertEqual(cases.count, 9)
        for entry in cases {
            let policy = CardArtworkPolicy(languages: entry["languages"].array.compactMap(\.string), metadataLanguage: entry["metadata"].string ?? "", originalLanguage: entry["original"].string)
            XCTAssertEqual(policy.poster(entry["posters"].array), entry["expected"].string)
            XCTAssertEqual(policy.parameter, entry["requests"].array.first?["params"]["include_image_language"].string)
        }
    }
    func testConcurrentPortraitsAndTVLogosShareOneFindAndOneImageList() async {
        let media = Media(id: "tt1234567", type: "movie", name: "Owned title"), configuration = configuration
        let find = CardArtworkRequest.tmdbFind(media.id), imagesRequest = CardArtworkRequest.tmdbImages(kind: "movie", id: 100, languages: "es,en,null")
        let transport = OwnedLocalizedPosterTransport([.curated: .object([:]), find: .object(["movie_results": .array([.object(["id": .integer(100)])])]), imagesRequest: images])
        let resolver = resolver(transport)
        async let logo = resolver.resolve(media, configuration: configuration)
        let posters = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<8 { group.addTask { await resolver.poster(media, configuration: configuration) } }
            var results: [String?] = []; for await value in group { results.append(value) }; return results
        }
        let artwork = await logo
        XCTAssertEqual(artwork.logo, "https://image.tmdb.org/t/p/w500/logo-es.png")
        XCTAssertEqual(posters.count, 8); XCTAssertTrue(posters.allSatisfy { $0 == "https://image.tmdb.org/t/p/w500/poster-es.jpg" })
        _ = await resolver.poster(media, configuration: configuration)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3); XCTAssertEqual(requests.filter { $0 == find }.count, 1); XCTAssertEqual(requests.filter { $0 == imagesRequest }.count, 1)
    }
    func testPosterConfigurationAndSourceIdentityStayIsolatedAcrossLanguageAndAccountChanges() async {
        var media = Media(id: "tt1234567", type: "movie", name: "Resolved playback title"); media.artworkSourceID = "tmdb:movie:100"
        let spanish = CardArtworkRequest.tmdbImages(kind: "movie", id: 100, languages: "es,en,null")
        let french = CardArtworkRequest.tmdbImages(kind: "movie", id: 100, languages: "fr,en,null")
        let transport = OwnedLocalizedPosterTransport([spanish: images, french: images]), resolver = self.resolver(transport)
        var configuration = configuration
        let first = await resolver.poster(media, configuration: configuration)
        XCTAssertEqual(first, "https://image.tmdb.org/t/p/w500/poster-es.jpg")
        configuration.tmdbKey = "second-owned-synthetic-key"
        let second = await resolver.poster(media, configuration: configuration); XCTAssertEqual(second, first)
        configuration.imageLanguages = ["French", "English", "Original"]
        let third = await resolver.poster(media, configuration: configuration)
        XCTAssertEqual(third, "https://image.tmdb.org/t/p/w500/poster-en.jpg")
        let requests = await transport.requests; XCTAssertEqual(requests, [spanish, spanish, french])
    }
    func testUnconfiguredUnsupportedAndDefaultEnglishCardsSkipLookupsAndUnavailablePostersRemainRecoverable() async {
        let transport = OwnedLocalizedPosterTransport([:]), resolver = self.resolver(transport)
        var configuration = configuration
        for id in ["mal:7", "local:7", "tmdb:movie:0", "tt1234567/path"] {
            let value = await resolver.poster(Media(id: id, type: "movie", name: "Owned"), configuration: configuration); XCTAssertNil(value)
        }
        let media = Media(id: "tmdb:movie:100", type: "movie", name: "Owned")
        configuration.tmdbKey = ""; let unconfigured = await resolver.poster(media, configuration: configuration); XCTAssertNil(unconfigured)
        configuration = self.configuration; configuration.language = "en-US"; configuration.imageLanguages = ["English", "Original"]
        let english = await resolver.poster(media, configuration: configuration); XCTAssertNil(english)
        var requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
        configuration = self.configuration
        let missing = await resolver.poster(media, configuration: configuration), again = await resolver.poster(media, configuration: configuration)
        XCTAssertNil(missing); XCTAssertNil(again)
        requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
}
