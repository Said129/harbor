import XCTest
@testable import Harbor

private struct EBookCatalogNetwork: HarborNativeNetworkCalling {
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        let text: String
        if request.url.hasSuffix("manga-repo.json") {
            text = #"{"plugins":[{"id":"manga-tags","name":"Owned tags","entry":"manga.js","lang":"en"}]}"#
        } else if request.url.hasSuffix("manga.js") {
            text = #"var plugin={id:'manga-tags',name:'Owned tags',tags:function(){return [{id:'ongoing',name:'Ongoing',group:'Status'},{id:'bad'}];},popular:function(){return [{id:'all',title:'Unfiltered'}];},search:function(q,o,tag){return [{id:'tagged',title:(q||'<empty>')+' '+o+' '+tag}];}};"#
        } else if request.url.hasSuffix("repo.json") {
            text = #"{"type":"ebook","plugins":[{"id":"catalog","name":"Owned catalog","entry":"catalog.js","lang":"ar"}]}"#
        } else if request.url.hasSuffix("catalog.js") {
            text = #"var probes=0;var plugin={id:'catalog',name:'Owned catalog',tags:async function(){probes++;await new Promise(r=>setTimeout(r,100));return [{id:'status:ongoing'},{id:'sort:rating'}];},popular:function(offset,tag){return [{id:'book',title:(tag||'none')+' '+offset+' probes:'+probes,originalLanguage:'ja',status:'ongoing',genres:['Fantasy']}];},search:function(q,offset,tag){return this.popular(offset,tag);},detail:function(id){return {id:id,title:'Detailed book',description:'Owned detail',originalLanguage:'ja'};}};"#
        } else { throw HarborPluginRepositoryError("owned-catalog-route") }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(text.utf8).base64EncodedString(), url: request.url)
    }
}

final class EBookCatalogTests: XCTestCase {
    func testActualJavaScriptCoreMatchesAllTwentyOnePinnedDesktopCatalogCases() async throws {
        let program = EBookCatalogProgram()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ebook-catalog-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(fixture["cases"].array.count, 21)
        for row in fixture["cases"].array {
            let actual = try await program.apply(row["input"])
            XCTAssertEqual(actual, row["expected"], row["name"].string ?? "Catalog")
        }
        let definitions = try await program.filterDefinitions()
        XCTAssertEqual(definitions.genres.count, 11)
        XCTAssertEqual(definitions.categories["Fiction"]?.count, 13)
        for pair in [("ongoing", "rating", "status:ongoing"), ("any", "popular", "sort:popular")] {
            let tag = try await program.apply(.object(["operation": .string("tag"), "status": .string(pair.0), "sort": .string(pair.1)]))
            XCTAssertEqual(tag.string, pair.2)
        }
    }

    func testGroupedNativeBooksKeepEveryPlayableRouteAndPersistOldShelves() async throws {
        var first = EBook(id: "source:first", title: "The Book", authors: ["Writer"], language: "en", pluginID: "ebook|first", itemID: "one", metadata: .object(["altTitle": .string("الكتاب"), "originalLanguage": .string("ja")]))
        let second = EBook(id: "source:second", title: "Book", authors: ["Writer"], language: "es", pluginID: "ebook|second", itemID: "two")
        let program = EBookCatalogProgram()
        let result = try await program.filter([first, second], filters: .init(), titleLanguage: "ar")
        XCTAssertEqual(result.books.count, 1)
        let grouped = try XCTUnwrap(result.books.first)
        XCTAssertEqual(result.titles[grouped.id], "الكتاب")
        XCTAssertEqual(grouped.title, "The Book")
        XCTAssertEqual(grouped.alternativeSources?.map(\.pluginID), ["ebook|first", "ebook|second"])
        XCTAssertEqual(grouped.alternativeSources?.map(\.itemID), ["one", "two"])
        XCTAssertEqual(grouped.alternativeSources?.map(\.language), ["en", "es"])
        let again = try await program.filter(result.books, filters: .init(), titleLanguage: "auto")
        XCTAssertEqual(again.books.first?.alternativeSources?.count, 2)
        first.alternativeSources = nil
        var old = try JSONValue.encoded(first).objectValue; old["alternativeSources"] = nil
        let decoded = try JSONValue.object(old).decoded(EBook.self)
        XCTAssertNil(decoded.alternativeSources); XCTAssertEqual(decoded.id, first.id)
        let input = first
        let cancelled = Task {
            withUnsafeCurrentTask { task in if let task { task.cancel() } }
            return try await program.filter([input], filters: .init(), titleLanguage: "auto")
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled catalog must not publish a result") } catch is CancellationError {} 
    }

    @MainActor func testRealReadingWorkerCoalescesSupportedTagsAndSeparatesOriginalFromContentLanguage() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-" + UUID().uuidString + ".json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let scope = PluginExecutionScope(owner: "owned-catalog", activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore(file: file), network: EBookCatalogNetwork())
        defer { manager.dispose() }; try await manager.load()
        try await manager.addRepository("https://example.org/catalog/repo.json", kind: .ebook)
        let repository = try XCTUnwrap(manager.document.repositories.first)
        try await manager.install(XCTUnwrap(repository.entries.first), repository: repository)
        let plugin = try XCTUnwrap(manager.installed(.ebook).first)
        async let first = manager.ebookBrowse(plugin, query: "", offset: 0, tag: "status:ongoing")
        async let second = manager.ebookBrowse(plugin, query: "", offset: 24, tag: "sort:rating")
        let results = try await (first, second)
        XCTAssertEqual(results.0.first?.title, "status:ongoing 0 probes:1")
        XCTAssertEqual(results.1.first?.title, "sort:rating 24 probes:1")
        let book = try XCTUnwrap(results.0.first)
        XCTAssertEqual(book.language, "ar"); XCTAssertEqual(book.metadata?["originalLanguage"].string, "ja")
        let unsupported = try await manager.ebookBrowse(plugin, query: "", offset: 48, tag: "sort:trending")
        XCTAssertEqual(unsupported.first?.title, "none 48 probes:1")
        let detail = try await manager.ebookDetail(book)
        XCTAssertEqual(detail.itemID, book.itemID); XCTAssertEqual(detail.language, "ar"); XCTAssertEqual(detail.description, "Owned detail")
        try await manager.setEnabled(plugin, false)
        let disabled = try XCTUnwrap(manager.document.plugins.first)
        try await manager.setEnabled(disabled, true)
        let enabled = try XCTUnwrap(manager.installed(.ebook).first)
        let fresh = try await manager.ebookBrowse(enabled, query: "", offset: 0, tag: "sort:rating")
        XCTAssertEqual(fresh.first?.title, "sort:rating 0 probes:1")
    }

    @MainActor func testMangaTagUsesOriginalSearchContractWithEmptyQueryAndSourceOffset() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("manga-tags-" + UUID().uuidString + ".json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let scope = PluginExecutionScope(owner: "owned-manga-tags", activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore(file: file), network: EBookCatalogNetwork())
        defer { manager.dispose() }; try await manager.load()
        try await manager.addRepository("https://example.org/catalog/manga-repo.json", kind: .manga)
        let repository = try XCTUnwrap(manager.document.repositories.first)
        try await manager.install(XCTUnwrap(repository.entries.first), repository: repository)
        let plugin = try XCTUnwrap(manager.installed(.manga).first)
        let tags = try await manager.tags(plugin)
        XCTAssertEqual(tags.array.count, 1); XCTAssertEqual(tags.array.first?["group"].string, "Status")
        let filtered = try await manager.mangaBrowse(plugin, query: "", offset: 48, tag: "ongoing")
        XCTAssertEqual(filtered.first?.title, "<empty> 48 ongoing"); XCTAssertEqual(filtered.first?.remoteID, "tagged")
        let unfiltered = try await manager.mangaBrowse(plugin, query: "", offset: 0)
        XCTAssertEqual(unfiltered.first?.title, "Unfiltered")
    }
}
