import XCTest
@testable import Harbor

struct BookChapterNetwork: HarborNativeNetworkCalling {
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        let text: String
        if request.url.hasSuffix("repo.json") {
            text = #"{"type":"ebook","plugins":[{"id":"chapters","name":"Owned volumes","entry":"book.js","lang":"en"}]}"#
        } else if request.url.hasSuffix("book.js") {
            text = #"var plugin={id:'chapters',name:'Owned volumes',popular:function(){return [{id:'owned',title:'Owned book'}];},chapters:function(id){if(id==='empty')return [];return [{title:'Volume ۲',volume:'۲',chapters:[{id:'original:3',title:'Third',chapter:'3',position:0,publishAt:'2026-01-01',views:123},{id:'original:2',title:'Second',chapter:'2',position:1}]},{id:'original:1',title:'First',volume:'1',chapter:'1',position:2}];},content:function(id){return 'Actual '+id+' paragraph.';}};"#
        } else { throw HarborPluginRepositoryError("owned-chapter-route") }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(text.utf8).base64EncodedString(), url: request.url)
    }
}

final class EBookDetailInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedBookVolumesInOneFreshGuestWithoutAnAccount() async throws {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else { XCTFail("Refuse configured account"); return }
        let context = AppProfileContext.shared; try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil,
              context.configuration?.account == nil, let owner = context.binding?.personalOwner else { XCTFail("Refuse configured profiles"); return }
        if context.configuration?.guestAddons == nil { try context.save(HouseholdSourceAccount(account: nil, guestAddons: [])) }
        let store = try HarborReadingPluginStore(), document = try await store.load()
        guard document.plugins.isEmpty, document.repositories.isEmpty else { XCTFail("Refuse existing reading sources"); return }
        let scope = PluginExecutionScope(owner: owner, activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: store, network: BookChapterNetwork())
        defer { manager.dispose() }; try await manager.load()
        try await manager.addRepository("https://example.org/chapters/repo.json", kind: .ebook)
        let repository = try XCTUnwrap(manager.document.repositories.first)
        try await manager.install(XCTUnwrap(repository.entries.first), repository: repository)
        XCTAssertEqual(manager.document.plugins.count, 1)
        let defaults = UserDefaults.standard
        defaults.set("en", forKey: "uiLanguage"); defaults.set(true, forKey: "nativeGuide.initialized.v1"); defaults.set(true, forKey: "nativeGuide.completed.v1")
        defaults.set(false, forKey: "interface.autoRotateBanners")
    }
}

final class EBookDetailTests: XCTestCase {
    func testActualJavaScriptCoreMatchesEightOriginalChapterAndInformationCases() async throws {
        let program = EBookDetailProgram()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ebook-detail-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture["cases"].array.count, 8)
        for row in fixture["cases"].array {
            let actual = try await program.apply(row["input"])
            XCTAssertEqual(actual, row["expected"], row["name"].string ?? "Book detail")
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await program.apply(.object(["operation": .string("groups"), "chapters": .array([])]))
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled detail must not publish") } catch is CancellationError {}
    }

    @MainActor func testActualPluginVolumesKeepChapterRoutesWhenDisplayOrderChangesAndEmptySourcesStayEmpty() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("book-chapters-" + UUID().uuidString + ".json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let scope = PluginExecutionScope(owner: "owned-book-chapters", activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore(file: file), network: BookChapterNetwork())
        defer { manager.dispose() }; try await manager.load()
        try await manager.addRepository("https://example.org/chapters/repo.json", kind: .ebook)
        let repository = try XCTUnwrap(manager.document.repositories.first)
        try await manager.install(XCTUnwrap(repository.entries.first), repository: repository)
        let plugin = try XCTUnwrap(manager.installed(.ebook).first)
        let books = try await manager.ebookBrowse(plugin, query: "", offset: 0), book = try XCTUnwrap(books.first)
        let publication = try await manager.ebookPublication(book)
        XCTAssertEqual(publication.chapters.map(\.path), ["original:3", "original:2", "original:1"])
        XCTAssertEqual(publication.chapters.first?.volume, "۲")
        XCTAssertEqual(publication.chapters.first?.volumeTitle, "Volume ۲")
        XCTAssertEqual(publication.chapters.first?.publishAt, "2026-01-01")
        XCTAssertEqual(publication.chapters.first?.views, .integer(123))
        let program = EBookDetailProgram(), groups = try await program.groups(publication.chapters)
        XCTAssertEqual(groups.map(\.volume), ["1", "۲"])
        let ordered = try await program.ordered(publication.chapters, volume: "۲", query: "", newest: false)
        XCTAssertEqual(ordered.map(\.path), ["original:2", "original:3"])
        let selected = try XCTUnwrap(ordered.first)
        XCTAssertEqual(try publication.startingChapter(requestedID: selected.path, resume: 0), 1)
        let content = try await manager.ebookBlocks(book, chapter: selected)
        XCTAssertEqual(content.map(\.text), ["Actual original:2 paragraph."])
        var empty = book; empty.itemID = "empty"
        let noChapters = try await manager.ebookPublication(empty, allowEmpty: true)
        XCTAssertTrue(noChapters.chapters.isEmpty)
        do { _ = try await manager.ebookPublication(empty); XCTFail("Reader must not open an empty source") } catch let error as HarborPluginRuntimeError { XCTAssertEqual(error.code, "plugin-no-chapters") }
    }

    func testRequestedEPUBChapterUsesOriginalPathAndDoesNotOverwriteUnrelatedSavedProgress() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader", withExtension: "epub", subdirectory: "Fixtures"))
        let reader = try EPUBReader(data: Data(contentsOf: url)), publication = reader.publication
        let path = try XCTUnwrap(publication.chapters.last?.path)
        let selected = try publication.startingChapter(requestedID: path, resume: 0)
        XCTAssertEqual(selected, publication.chapters.count - 1)
        XCTAssertEqual(try reader.blocks(publication.chapters[selected]).map(\.text), ["Second section", "Five six seven."])
        XCTAssertEqual(try publication.startingChapter(requestedID: nil, resume: 500), publication.chapters.count - 1)
        XCTAssertThrowsError(try publication.startingChapter(requestedID: "removed:chapter", resume: 0))
        XCTAssertThrowsError(try EBookPublication(title: "Empty", authors: [], language: nil, chapters: []).startingChapter(requestedID: nil, resume: 0))
    }
}
