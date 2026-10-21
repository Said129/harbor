import XCTest
@testable import Harbor

private actor ReadingPluginNetwork: HarborNativeNetworkCalling {
    private let routes: [String: Data]
    private var held: [CheckedContinuation<Void, Never>] = []
    private var holding: String?
    private(set) var requests: [HarborNetworkRequest] = []
    init(_ routes: [String: Data]) { self.routes = routes }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        if holding == request.url { await withCheckedContinuation { held.append($0) } }
        guard let data = routes[request.url] else { throw HarborPluginRepositoryError("owned-route") }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: data.base64EncodedString(), url: request.url)
    }
    func hold(_ url: String) { holding = url }
    func waitUntilHeld() async throws {
        for _ in 0..<250 { if !held.isEmpty { return }; try await Task.sleep(for: .milliseconds(20)) }
        throw HarborPluginRepositoryError("owned-reading-timeout")
    }
    func release() { holding = nil; let pending = held; held = []; pending.forEach { $0.resume() } }
}
@MainActor private final class ReadingScope {
    var value = PluginExecutionScope(owner: "owned-reading", activation: UUID())
}

@MainActor final class HarborReadingPluginTests: XCTestCase {
    private func prepared(_ routes: [String: Data]) async throws -> (HarborReadingPluginManager, ReadingPluginNetwork, ReadingScope, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("owned-reading-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("reading.json"), context = ReadingScope(), network = ReadingPluginNetwork(routes)
        let manager = HarborReadingPluginManager(scope: context.value, currentScope: { context.value }, store: try HarborReadingPluginStore(file: file), network: network)
        try await manager.load(); return (manager, network, context, file)
    }
    private func data(_ string: String) -> Data { Data(string.utf8) }

    func testActualWorkerMatchesAllTwentyTwoPinnedReadingReferenceCases() async throws {
        let context = ReadingScope(), program = HarborReadingPluginProgram(scope: context.value, currentScope: { context.value })
        defer { program.dispose() }
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reading-plugin-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(fixture["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(fixture["cases"].array.count, 22)
        for row in fixture["cases"].array {
            let input = row["input"]; var extra = input.objectValue; extra["raw"] = nil; extra["operation"] = nil
            let actual = try await program.apply(XCTUnwrap(input["operation"].string), raw: input["raw"], extra: extra)
            XCTAssertEqual(actual, row["expected"], row["name"].string ?? "Owned reading case")
        }
    }

    func testNativeReadingSourcesInstallBrowseReadAndRetainDistinctKindsWithSanitizedPageHeaders() async throws {
        let mangaURL = "https://example.org/manga/repo.json", bookURL = "https://example.org/books/repo.json"
        let manga = #"var plugin={id:'same.id',name:'Owned manga',popular:function(o){return [{id:'m',title:'Manga '+o,cover:'https://files.example.org/cover.png'}];},search:function(q,o){return [{id:'m',title:q+' '+o}];},detail:function(id){return {id:id,title:'Owned detail',author:'Owned author'};},chapters:function(){return [{id:'ch',chapter:'2.5',title:'Owned chapter',pages:1}];},pageUrls:function(){return [{url:'https://files.example.org/page.png',headers:{referer:'https://example.org/','user-agent':'Owned',cookie:'private'}}];},tags:function(){return [{id:'owned',name:'Owned tag'}];}};"#
        let book = #"var plugin={id:'same.id',name:'Owned book',popular:function(o){return [{id:'b',title:'Book '+o,author:'Writer'}];},search:function(q,o){return [{id:'b',title:q+' '+o}];},chapters:function(){return [{title:'Volume 1',chapters:[{id:'one',title:'First',chapter:1},{id:'two',title:'Second',chapter:2}]}];},content:function(id){return id==='two'?{images:['https://files.example.org/page.png']}:'First line\ncontinued\n\nSecond paragraph';}};"#
        let fallback = #"var plugin={id:'pictures',name:'Pictures',popular:function(){return [{id:'p',title:'Picture book'}];},chapters:function(){return [{id:'pictures',title:'Pictures'}];},pageUrls:function(){return ['https://files.example.org/page.png'];}};"#
        let (manager, network, _, file) = try await prepared([
            mangaURL: data(#"{"name":"Owned manga repo","plugins":[{"id":"same.id","name":"Owned manga","entry":"m.js"}]}"#),
            bookURL: data(#"{"type":"ebook","name":"Owned book repo","plugins":[{"id":"same.id","name":"Owned book","entry":"b.js"},{"id":"pictures","name":"Pictures","entry":"p.js"}]}"#),
            "https://example.org/manga/m.js": data(manga), "https://example.org/books/b.js": data(book), "https://example.org/books/p.js": data(fallback),
            "https://files.example.org/page.png": Data([1, 2, 3])])
        defer { manager.dispose() }
        try await manager.addRepository(mangaURL, kind: .manga); try await manager.addRepository(bookURL, kind: .ebook)
        for repository in manager.document.repositories { for entry in repository.entries { try await manager.install(entry, repository: repository) } }
        XCTAssertEqual(manager.document.plugins.count, 3)
        let mangaPlugin = try XCTUnwrap(manager.installed(.manga).first), bookPlugin = try XCTUnwrap(manager.installed(.ebook).first(where: { $0.entry.id == "same.id" }))
        let hits = try await manager.mangaBrowse(mangaPlugin, query: "Owned", offset: 48)
        let found = try XCTUnwrap(hits.first); XCTAssertEqual(found.title, "Owned 48")
        XCTAssertEqual(found.id, "same.id::m")
        let detail = try await manager.mangaDetail(found); XCTAssertEqual(detail.author, "Owned author")
        let chapters = try await manager.mangaChapters(found); XCTAssertEqual(chapters.first?.number, 2.5)
        XCTAssertEqual(chapters.first?.id, "same.id::ch")
        let pages = try await manager.mangaPages(found, chapter: XCTUnwrap(chapters.first))
        let imageURL = try XCTUnwrap(pages.first?.path)
        async let firstImage = manager.image(imageURL, pluginID: mangaPlugin.id)
        async let otherImage = manager.image(imageURL, pluginID: mangaPlugin.id)
        let images = try await (firstImage, otherImage); XCTAssertEqual(images.0, Data([1, 2, 3])); XCTAssertEqual(images.1, images.0)
        let cached = try await manager.image(imageURL, pluginID: mangaPlugin.id); XCTAssertEqual(cached, images.0)
        let requests = await network.requests
        XCTAssertEqual(requests.filter { $0.url == imageURL }.count, 1)
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.headers["referer"], "https://example.org/"); XCTAssertNil(request.headers["cookie"])
        let tags = try await manager.tags(mangaPlugin); XCTAssertEqual(tags.array.first?["id"].string, "owned")
        let books = try await manager.ebookBrowse(bookPlugin, query: "Book", offset: 24), selected = try XCTUnwrap(books.first)
        XCTAssertEqual(selected.id, "source:plugin%3Asame.id:b"); XCTAssertEqual(selected.title, "Book 24")
        let publication = try await manager.ebookPublication(selected); XCTAssertEqual(publication.chapters.count, 2)
        let text = try await manager.ebookBlocks(selected, chapter: publication.chapters[0]); XCTAssertEqual(text.map(\.text), ["First line continued", "Second paragraph"])
        let pictures = try await manager.ebookBlocks(selected, chapter: publication.chapters[1]); XCTAssertEqual(pictures.first?.imageURL, "https://files.example.org/page.png")
        let picturePlugin = try XCTUnwrap(manager.installed(.ebook).first(where: { $0.entry.id == "pictures" }))
        let pictureBooks = try await manager.ebookBrowse(picturePlugin, query: "", offset: 0)
        let pictureBook = try XCTUnwrap(pictureBooks.first), picturePublication = try await manager.ebookPublication(pictureBook)
        let fallbackBlocks = try await manager.ebookBlocks(pictureBook, chapter: XCTUnwrap(picturePublication.chapters.first))
        XCTAssertEqual(fallbackBlocks.first?.imageURL, "https://files.example.org/page.png")
        try await manager.setEnabled(mangaPlugin, false); XCTAssertTrue(manager.installed(.manga).isEmpty)
        let reloaded = try await HarborReadingPluginStore(file: file).load()
        XCTAssertEqual(reloaded.plugins.first(where: { $0.kind == .manga })?.enabled, false)
        XCTAssertEqual(reloaded.plugins.first(where: { $0.kind == .ebook && $0.entry.id == "same.id" })?.enabled, true)
    }

    func testMangayomiJSIndexUsesOriginalPreludeForPageSearchDetailsAndConcurrentSourceReuse() async throws {
        let url = "https://example.org/my/repo.json"
        let source = #"class DefaultExtension {getPopular(page){return {list:[{url:'https://example.org/m/'+page,name:'Page '+page}]};}search(q,page){return {list:[{url:'https://example.org/m/search',name:q+' '+page}]};}getDetail(id){return {name:'Owned detail',author:'Writer',chapters:[{url:'https://example.org/ch/1',name:'Chapter 1'}]};}getPageList(){return ['https://files.example.org/page.png'];}}"#
        let (manager, _, _, _) = try await prepared([url: data(#"[{"id":12,"name":"Owned MY","baseUrl":"https://example.org","sourceCodeUrl":"a.js","sourceCodeLanguage":1,"langs":["es","en"]},{"name":"Dart","baseUrl":"https://example.org","sourceCodeUrl":"bad.dart","sourceCodeLanguage":0}]"#), "https://example.org/my/a.js": data(source)])
        defer { manager.dispose() }
        try await manager.addRepository(url, kind: .manga)
        let repository = try XCTUnwrap(manager.document.repositories.first); XCTAssertEqual(repository.entries.count, 1)
        try await manager.install(XCTUnwrap(repository.entries.first), repository: repository)
        let plugin = try XCTUnwrap(manager.installed(.manga).first)
        let results = try await withThrowingTaskGroup(of: [MangaBook].self, returning: [[MangaBook]].self) { group in
            for _ in 0..<6 { group.addTask { try await manager.mangaBrowse(plugin, query: "", offset: 48) } }
            var values: [[MangaBook]] = []; for try await result in group { values.append(result) }; return values
        }
        XCTAssertEqual(results.count, 6); XCTAssertTrue(results.allSatisfy { $0.first?.title == "Page 2" })
        let search = try await manager.mangaBrowse(plugin, query: "Query", offset: 96); XCTAssertEqual(search.first?.title, "Query 3")
        let book = try XCTUnwrap(results.first?.first), detail = try await manager.mangaDetail(book)
        XCTAssertEqual(detail.title, "Owned detail")
        let chapters = try await manager.mangaChapters(book); XCTAssertEqual(chapters.count, 1)
        let pages = try await manager.mangaPages(book, chapter: XCTUnwrap(chapters.first)); XCTAssertEqual(pages.first?.path, "https://files.example.org/page.png")
    }

    func testRetiredProfileCancelsAnInFlightReadingInstallAndKeepsThePreviousCatalog() async throws {
        let url = "https://example.org/retired/repo.json", sourceURL = "https://example.org/retired/a.js"
        let (manager, network, context, file) = try await prepared([url: data(#"{"plugins":[{"id":"owned","name":"Owned","entry":"a.js"}]}"#), sourceURL: data("var plugin={id:'owned',name:'Owned',popular:function(){return [];}};")])
        defer { manager.dispose(); Task { await network.release() } }
        try await manager.addRepository(url, kind: .manga)
        let repository = try XCTUnwrap(manager.document.repositories.first), before = try Data(contentsOf: file)
        await network.hold(sourceURL)
        let task = Task { try await manager.install(XCTUnwrap(repository.entries.first), repository: repository) }
        try await network.waitUntilHeld(); context.value = .init(owner: "other-profile", activation: UUID()); manager.dispose(); await network.release()
        do { try await task.value; XCTFail("Retired installation committed") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(manager.ready); XCTAssertTrue(manager.document.plugins.isEmpty); XCTAssertEqual(try Data(contentsOf: file), before)
    }
}
