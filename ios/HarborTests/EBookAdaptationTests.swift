import XCTest
@testable import Harbor

private actor AdaptationNetwork: HarborNativeNetworkCalling {
    let fixture: JSONValue
    private(set) var requests: [HarborNetworkRequest] = []
    init(_ fixture: JSONValue) { self.fixture = fixture }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        let url = try XCTUnwrap(URL(string: request.url))
        let value: JSONValue
        if url.path.hasSuffix("repo.json") {
            value = .object(["plugins": .array([.object(["id": .string("owned-adaptation-manga"), "name": .string("Owned adaptation source"), "entry": .string("manga.js"), "lang": .string("en")])])])
        } else if url.path.hasSuffix("manga.js") {
            let source = #"var plugin={id:'owned-adaptation-manga',name:'Owned adaptation source',search:function(q){return [{id:'one',title:'Owned Manga',author:'Owned Writer'}];},detail:function(){return {id:'one',title:'Owned Manga'};},chapters:function(){return [{id:'chapter',title:'Owned chapter'}];},pageUrls:function(){return ['https://example.org/owned-page.png'];}};"#
            return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(source.utf8).base64EncodedString(), url: request.url)
        } else if url.host == "graphql.anilist.co" { value = .object(["data": .object(["Page": .object(["media": fixture["anilistRows"]])])]) }
        else if url.host == "kitsu.io" { value = .object(["data": fixture["kitsuRows"]]) }
        else { value = .object(["data": fixture["jikanRows"]]) }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: try JSONEncoder().encode(value).base64EncodedString(), url: request.url)
    }
}

@MainActor private final class AdaptationScope {
    var value = PluginExecutionScope(owner: "owned-adaptation-search", activation: UUID())
}

@MainActor final class EBookAdaptationTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ebook-adaptation-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
    }
    func testActualWorkerPreservesAllSevenDesktopAdaptationRoutingAndChoiceCases() async throws {
        let fixture = try fixture(), network = AdaptationNetwork(fixture), scope = PluginExecutionScope(owner: "owned-adaptations", activation: UUID())
        let client = EBookAdaptationClient(scope: scope, currentScope: { scope }, network: network); defer { client.dispose() }
        XCTAssertEqual(fixture["cases"].array.count, 7)
        for row in fixture["cases"].array {
            var input = row["input"].objectValue
            let operation = try XCTUnwrap(input.removeValue(forKey: "operation")?.string)
            let actual = try await client.query(operation, arguments: input)
            XCTAssertEqual(actual, row["expected"], row["name"].string ?? "Adaptation routing")
            if row["expected"]["id"].string != nil {
                let parsed = try XCTUnwrap(EBookAdaptationClient.animeMedia(actual))
                XCTAssertEqual(parsed.id, row["expected"]["id"].string); XCTAssertEqual(parsed.type, "anime")
            }
        }
        let direct = try XCTUnwrap(fixture["cases"].array.first { $0["input"]["item"]["anilistId"].integer != nil })
        XCTAssertEqual(EBookAdaptationClient.directAnime(direct["input"]["item"])?.id, direct["expected"]["id"].string)
        XCTAssertNil(EBookAdaptationClient.animeMedia(.object(["id": .string("anilist:undefined"), "name": .string("Broken identity")])))
    }
    func testActualThreeProviderAnimeSearchDeduplicatesAndCannotCrossRetiredProfile() async throws {
        let fixture = try fixture(), network = AdaptationNetwork(fixture)
        let context = AdaptationScope()
        let client = EBookAdaptationClient(scope: context.value, currentScope: { context.value }, network: network); defer { client.dispose() }
        let hits = try await client.query("anime-search", arguments: ["query": .string("Owned"), "limit": .integer(8)])
        XCTAssertEqual(hits.array.compactMap { $0["name"].string }, ["Owned Anime", "Jikan Owned", "Kitsu Owned"])
        let requests = await network.requests; XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy { $0.publicNetworkOnly && !$0.allowLocalNetwork && !$0.headers.keys.contains { $0.lowercased() == "authorization" } })
        context.value = .init(owner: "another-owner", activation: UUID())
        do { _ = try await client.query("anime-search", arguments: ["query": .string("Owned")]); XCTFail("Retired lookup must reject") } catch {}
        let after = await network.requests; XCTAssertEqual(after.count, requests.count)
    }
    func testMangaAdaptationFindsInstalledSourceAndKeepsItsActualChapterAndPageRoutes() async throws {
        let fixture = try fixture(), network = AdaptationNetwork(fixture), scope = PluginExecutionScope(owner: "owned-manga-adaptation", activation: UUID())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("manga-adaptation-" + UUID().uuidString + ".json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore(file: file), network: network)
        let client = EBookAdaptationClient(scope: scope, currentScope: { scope }, network: network)
        defer { client.dispose(); manager.dispose() }; try await manager.load()
        try await manager.addRepository("https://example.org/adaptations/repo.json", kind: .manga)
        let repository = try XCTUnwrap(manager.document.repositories.first)
        try await manager.install(XCTUnwrap(repository.entries.first), repository: repository)
        let item: JSONValue = .object(["kind": .string("manga"), "title": .string("Owned Manga"), "altTitles": .array([.string("Alias")])])
        let rows = try await manager.resolveMangaAdaptation(item, book: EBook(id: "owned-novel", title: "Owned Novel"), client: client, server: nil, includeAdult: false)
        XCTAssertEqual(rows.count, 1)
        let book = try XCTUnwrap(rows.first); XCTAssertEqual(book.remoteID, "one"); XCTAssertNotNil(book.pluginID)
        let chapters = try await manager.mangaChapters(book)
        let pages = try await manager.mangaPages(book, chapter: XCTUnwrap(chapters.first))
        XCTAssertEqual(pages.first?.path, "https://example.org/owned-page.png")
    }
}
