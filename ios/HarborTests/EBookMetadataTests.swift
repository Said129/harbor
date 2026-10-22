import XCTest
@testable import Harbor

actor MetadataNetwork: HarborNativeNetworkCalling {
    let fixture: JSONValue
    private(set) var requests: [HarborNetworkRequest] = []
    private var holding = false
    private var held: CheckedContinuation<Void, Never>?
    init(_ fixture: JSONValue) { self.fixture = fixture }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        let url = try XCTUnwrap(URL(string: request.url)), host = url.host ?? ""
        if holding && host == "www.googleapis.com" { await withCheckedContinuation { held = $0 } }
        try Task.checkCancellation()
        let value: JSONValue
        if url.path.hasSuffix("/repo.json") {
            value = .object(["type": .string("ebook"), "plugins": .array([.object(["id": .string("owned-metadata-source"), "name": .string("Owned metadata source"), "entry": .string("source.js"), "lang": .string("en")])])])
        } else if url.path.hasSuffix("/source.js") {
            let source = #"var plugin={id:'owned-metadata-source',name:'Owned metadata source',search:function(q){return [{id:'one',title:'Owned Book',author:'Owned Writer',description:'Catalog',genres:[]}];},detail:function(id){return {id:id,title:'Owned Book',author:'Owned Writer',description:'Hydrated source description',genres:[]};},chapters:function(){return [{id:'chapter',title:'Chapter one'}];},content:function(){return 'Owned readable paragraph.';}};"#
            return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(source.utf8).base64EncodedString(), url: request.url)
        } else if host == "www.googleapis.com" {
            value = url.path.contains("/volumes/") ? fixture["google"] : .object(["items": .array([fixture["google"]])])
        } else if host == "graphql.anilist.co" {
            value = .object(["data": .object(["Page": .object(["media": .array([])]), "Media": .null])])
        } else if host == "openlibrary.org" {
            if url.path.hasPrefix("/works/") { value = .object(["title": .string("Owned library book"), "description": .string("Owned detailed description"), "covers": .array([.integer(12)])]) }
            else { value = .object(["docs": .array([fixture["open"]])]) }
        } else { value = .object(["results": .object(["bindings": .array([])]), "entities": .object([:]), "data": .array([])]) }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: try JSONEncoder().encode(value).base64EncodedString(), url: request.url)
    }
    func hold() { holding = true }
    func waitUntilHeld() async throws {
        for _ in 0..<900 { if held != nil { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw HarborPluginRuntimeError("owned-metadata-not-held")
    }
    func release() { holding = false; let continuation = held; held = nil; continuation?.resume() }
}

@MainActor private final class MetadataScope {
    var value = PluginExecutionScope(owner: "owned-metadata", activation: UUID())
}

private actor MetadataCatalogQueries {
    private(set) var titles: [String] = []
    func search(_ title: String) -> [EBook] { titles.append(title); return [] }
}

@MainActor final class EBookMetadataTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ebook-metadata-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
    }
    private func cache(_ name: String = UUID().uuidString, owner: String = "owned-metadata") throws -> EBookMetadataCache {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-" + name + ".json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        return try EBookMetadataCache(owner: owner, file: file)
    }
    private func client(_ context: MetadataScope, _ network: MetadataNetwork, cache: EBookMetadataCache? = nil) throws -> EBookMetadataClient {
        try EBookMetadataClient(scope: context.value, currentScope: { context.value }, network: network, cache: cache ?? self.cache(), googleKey: "owned-private-key", language: "en")
    }
    func testActualWorkerMatchesPinnedBookMetadataAndExactSixResolverAliases() async throws {
        let fixture = try fixture(), context = MetadataScope(), network = MetadataNetwork(fixture)
        let client = try client(context, network); defer { client.dispose() }
        XCTAssertEqual(fixture["cases"].array.count, 5)
        for row in fixture["cases"].array {
            var input = row["input"].objectValue
            let operation = try XCTUnwrap(input.removeValue(forKey: "operation")?.string)
            let actual = try await client.query(operation, arguments: input)
            XCTAssertEqual(actual, row["expected"], row["name"].string ?? "Original metadata")
        }
        var book = fixture["base"].objectValue
        book["sourceAliases"] = .array(["Alias", "Alias", "Two", "Three", "Four", "Five", "Six"].map(JSONValue.string))
        let titles = try await client.query("source-queries", arguments: ["book": .object(book)])
        XCTAssertEqual(titles.array.compactMap(\.string), ["Owned Book", "Alias", "Two", "Three", "Four", "Five"])
        XCTAssertEqual(client.active, 0)
    }
    func testNetworkEnrichmentPublishesReadableSourceAndPersistsFreshCacheWithoutAPIKey() async throws {
        let fixture = try fixture(), context = MetadataScope(), network = MetadataNetwork(fixture), cache = try cache()
        let client = try client(context, network, cache: cache); defer { client.dispose() }
        let book = EBook(id: "source:owned", title: "Owned Book", authors: ["Owned Writer"], source: "Owned source", pluginID: "ebook|owned", itemID: "one", metadata: fixture["base"])
        var partial: [[EBook]] = []
        let enriched = try await client.enrich([book]) { partial.append($0) }
        let result = try XCTUnwrap(enriched.first)
        XCTAssertEqual(result.id, book.id); XCTAssertEqual(result.pluginID, book.pluginID); XCTAssertEqual(result.itemID, book.itemID)
        XCTAssertEqual(result.metadata?["googleBooksId"].string, "owned-google"); XCTAssertTrue(result.readable)
        XCTAssertTrue(partial.contains { $0.first?.metadata?["googleBooksId"].string == "owned-google" })
        try await client.flush()
        let saved = try await cache.load(); XCTAssertFalse(saved.isEmpty)
        XCTAssertFalse(saved.description.contains("owned-private-key")); XCTAssertTrue(saved.keys.allSatisfy(EBookMetadataCache.allowed))
        let previous = await network.requests.count
        _ = try await client.enrich([book]) { _ in }
        let final = await network.requests.count; XCTAssertEqual(final, previous)
        let requests = await network.requests
        XCTAssertTrue(requests.contains { $0.url.contains("www.googleapis.com") && $0.url.contains("owned-private-key") })
        XCTAssertTrue(requests.allSatisfy { $0.publicNetworkOnly && !$0.allowLocalNetwork })
    }
    func testPublicDiscoverySearchCategoryPaginationAndDetailKeepMetadataOnlyUntilLinked() async throws {
        let fixture = try fixture(), context = MetadataScope(), network = MetadataNetwork(fixture)
        let client = try client(context, network); defer { client.dispose() }
        let popular = try await client.books("popular")
        let book = try XCTUnwrap(popular.first); XCTAssertEqual(book.id, "openlibrary:OWNED"); XCTAssertFalse(book.readable)
        let search = try await client.books("search", arguments: ["query": .string("Owned library")]); XCTAssertEqual(search.first?.id, book.id)
        let category = try await client.books("category", arguments: ["category": .string("Fantasy")]); XCTAssertEqual(category.first?.id, book.id)
        _ = try await client.query("browse", arguments: ["sort": .string("SCORE_DESC"), "page": .integer(2)])
        let detail = try await client.query("detail", arguments: ["id": .string(book.id)])
        XCTAssertEqual(detail["description"].string, "Owned detailed description")
        let detailed = EBookMetadataMapping.detail(detail, preserving: book)
        XCTAssertEqual(detailed.authors, book.authors); XCTAssertEqual(detailed.metadata?["editionCount"], book.metadata?["editionCount"])
        XCTAssertEqual(detailed.description, "Owned detailed description"); XCTAssertFalse(detailed.readable)
        let requests = await network.requests
        let graphql = try XCTUnwrap(requests.first { $0.url.contains("graphql.anilist") })
        XCTAssertFalse(graphql.headers.keys.contains { $0.lowercased() == "authorization" })
        let body = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(Data(base64Encoded: graphql.bodyBase64 ?? "")))
        XCTAssertEqual(body["variables"]["page"].integer, 1)
        XCTAssertTrue(requests.contains { request in guard let encoded = request.bodyBase64, let body = Data(base64Encoded: encoded), let value = try? JSONDecoder().decode(JSONValue.self, from: body) else { return false }; return value["variables"]["page"].integer == 2 })
    }
    func testCancelledMetadataCannotPublishLateProgressOrBlockAnotherQueryAndRetiredScope() async throws {
        let fixture = try fixture(), context = MetadataScope(), network = MetadataNetwork(fixture)
        let client = try client(context, network); defer { client.dispose(); Task { await network.release() } }
        await network.hold(); var partial = 0
        let task = Task { try await client.query("enrich", arguments: ["books": .array([fixture["base"]])]) { _ in partial += 1 } }
        try await network.waitUntilHeld(); task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled metadata must reject") } catch {}
        let before = partial
        let mapped = try await client.query("map", arguments: ["kind": .string("googlebooks"), "raw": fixture["google"]])
        XCTAssertEqual(mapped["id"].string, "googlebooks:owned-google")
        await network.release(); try await Task.sleep(for: .milliseconds(150)); XCTAssertEqual(partial, before)
        context.value = .init(owner: "another-owner", activation: UUID())
        do { _ = try await client.query("popular"); XCTFail("Retired profile must reject") } catch {}
        XCTAssertFalse(client.busy)
    }
    func testCacheRejectsAnotherOwnerAndDiscardsKeysOutsideOriginalPublicCacheNamespaces() async throws {
        let id = UUID().uuidString, first = try cache(id), other = try cache(id, owner: "another-owner")
        try await first.save(["harbor.ebook.metadata.v1": "owned public metadata", "harbor.ebook.google-books-key": "private", "unrelated": "private"])
        let own = try await first.load(), foreign = try await other.load()
        XCTAssertEqual(own, ["harbor.ebook.metadata.v1": "owned public metadata"]); XCTAssertTrue(foreign.isEmpty)
        try await first.clear(); let cleared = try await first.load(); XCTAssertTrue(cleared.isEmpty)
    }
    func testInstalledSourceResolutionUsesEveryOriginalAliasAndKeepsWorkingChapterRoutes() async throws {
        let fixture = try fixture(), context = MetadataScope(), network = MetadataNetwork(fixture)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-sources-" + UUID().uuidString + ".json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let manager = HarborReadingPluginManager(scope: context.value, currentScope: { context.value }, store: try HarborReadingPluginStore(file: file), network: network)
        defer { manager.dispose() }; try await manager.load()
        try await manager.addRepository("https://example.org/metadata/repo.json", kind: .ebook)
        let repository = try XCTUnwrap(manager.document.repositories.first)
        try await manager.install(XCTUnwrap(repository.entries.first), repository: repository)
        let client = try manager.ebookMetadata()
        var raw = try await client.query("map", arguments: ["kind": .string("googlebooks"), "raw": fixture["google"]]).objectValue
        raw["sourceAliases"] = .array([.string("Alias"), .string("Another title")])
        let book = try XCTUnwrap(EBookMetadataMapping.books(.array([.object(raw)])).first), catalog = MetadataCatalogQueries()
        var published: [[EBook]] = []
        let routes = try await manager.resolveEBook(book, candidates: [], catalog: { await catalog.search($0) }) { published.append($0) }
        let queries = await catalog.titles; XCTAssertEqual(queries, ["Owned Book", "Alias", "Another title"])
        let readable = try XCTUnwrap(routes.first); XCTAssertNotNil(readable.pluginID); XCTAssertNotNil(readable.itemID)
        XCTAssertEqual(readable.description, "Hydrated source description")
        XCTAssertTrue(published.contains { !$0.isEmpty })
        let publication = try await manager.ebookPublication(readable)
        let blocks = try await manager.ebookBlocks(readable, chapter: XCTUnwrap(publication.chapters.first))
        XCTAssertEqual(blocks.first?.text, "Owned readable paragraph.")
    }
}
