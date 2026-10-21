import XCTest
@testable import Harbor

private struct ReadingSeedNetwork: HarborNativeNetworkCalling {
    var catalog = false
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        let page = "http://127.0.0.1:18734/page.png"
        let value: String
        if request.url == "https://example.org/owned-reading/manga.json" {
            value = #"{"name":"Owned reading repository","plugins":[{"id":"owned.ui.reading.manga","name":"Owned UI Manga","entry":"manga.js","lang":"en","version":"1"}]}"#
        } else if request.url == "https://example.org/owned-reading/books.json" {
            value = catalog ? #"{"type":"ebook","name":"Owned reading repository","plugins":[{"id":"owned.ui.reading.books","name":"Owned UI Books","entry":"books.js","lang":"en","version":"2"},{"id":"owned.ui.reading.alternate","name":"Owned Alternate Books","entry":"alternate.js","lang":"es","version":"2"}]}"# : #"{"type":"ebook","name":"Owned reading repository","plugins":[{"id":"owned.ui.reading.books","name":"Owned UI Books","entry":"books.js","lang":"en","version":"1"}]}"#
        } else if catalog && (request.url.hasSuffix("/books.js") || request.url.hasSuffix("/alternate.js")) {
            let alternate = request.url.hasSuffix("/alternate.js")
            let id = alternate ? "owned.ui.reading.alternate" : "owned.ui.reading.books"
            let name = alternate ? "Owned Alternate Books" : "Owned UI Books"
            let title = alternate ? "The Owned Book" : "Owned Book"
            value = "function owned(){return {id:'owned',title:'" + title + "',author:'Owned author',altTitle:'الكتاب',cover:'" + page + "',originalLanguage:'ja',status:'ongoing',genres:['Fantasy'],chapters:2,score:85,description:'Owned full book description.'};}var plugin={id:'" + id + "',name:'" + name + "',tags:function(){return [{id:'status:ongoing',name:'Ongoing'}];},popular:function(o){return o?[]:[owned()];},search:function(q,o){return q==='Owned'&&!o?[owned()]:[];},detail:owned,chapters:function(){return [{id:'one',title:'First chapter'},{id:'two',title:'Second chapter'}];},content:function(id){return id==='two'?'Owned second chapter paragraph.':'Owned first chapter paragraph.';}};"
        } else if catalog && request.url.hasSuffix("/manga.js") {
            value = "var plugin={id:'owned.ui.reading.manga',name:'Owned UI Manga',tags:function(){return [{id:'owned-tag',name:'Owned tag',group:'Status'}];},popular:function(){return [{id:'owned',title:'Owned Manga',cover:'" + page + "'}];},search:function(q,o,tag){return tag==='owned-tag'?[{id:'tagged',title:'Owned tagged Manga',cover:'" + page + "'}]:q==='Owned'?[{id:'owned',title:'Owned Manga',cover:'" + page + "'}]:[];},detail:function(){return {id:'owned',title:'Owned Manga',cover:'" + page + "',author:'Owned author'};},chapters:function(){return [{id:'one',title:'Owned chapter 1',chapter:'1',pages:2}];},pageUrls:function(){return ['" + page + "?one','" + page + "?two'];}};"
        } else if request.url.hasSuffix("/manga.js") {
            value = "var plugin={id:'owned.ui.reading.manga',name:'Owned UI Manga',popular:function(){return [{id:'owned',title:'Owned Manga',cover:'" + page + "'}];},search:function(q){return q==='Owned'?[{id:'owned',title:'Owned Manga',cover:'" + page + "'}]:[];},detail:function(){return {id:'owned',title:'Owned Manga',cover:'" + page + "',author:'Owned author',description:'Owned offline reading fixture'};},chapters:function(){return [{id:'one',title:'Owned chapter 1',chapter:'1',pages:2}];},pageUrls:function(){return ['" + page + "?one','" + page + "?two'];}};"
        } else if request.url.hasSuffix("/books.js") {
            value = "var plugin={id:'owned.ui.reading.books',name:'Owned UI Books',popular:function(){return [{id:'owned',title:'Owned Book',author:'Owned author',cover:'" + page + "'}];},search:function(q){return q==='Owned'?[{id:'owned',title:'Owned Book',author:'Owned author',cover:'" + page + "'}]:[];},chapters:function(){return [{id:'one',title:'First chapter'},{id:'two',title:'Second chapter'}];},content:function(id){return id==='two'?'Owned second chapter paragraph.':'Owned first chapter paragraph.\\n\\nOwned next paragraph.';}};"
        } else { throw HarborPluginRepositoryError("owned-reading-route") }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(value.utf8).base64EncodedString(), url: request.url)
    }
}

final class HarborReadingPluginInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedBulkRepositoryWithoutInstallingItsEntries() async throws {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else { XCTFail("Refuse to seed an account"); return }
        let context = AppProfileContext.shared; try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil,
              context.profiles.active?.desktop.isKid == false, context.configuration?.account == nil else { XCTFail("Refuse configured profiles"); return }
        if context.configuration?.guestAddons == nil { try context.save(HouseholdSourceAccount(account: nil, guestAddons: [])) }
        let store = try HarborReadingPluginStore(), document = try await store.load()
        guard document.plugins.isEmpty, document.repositories.isEmpty else { XCTFail("Refuse configured reading sources"); return }
        try await appendBulk(store, document: document)
        let defaults = UserDefaults.standard
        defaults.set("es", forKey: "uiLanguage"); defaults.set(true, forKey: "nativeGuide.initialized.v1"); defaults.set(true, forKey: "nativeGuide.completed.v1")
        defaults.set(false, forKey: "interface.autoRotateBanners")
    }
    @MainActor func testPrepareOwnedReadingSourcesInTheOrdinaryLocalInstallation() async throws {
        try await prepare(catalog: false)
    }
    @MainActor func testPrepareOwnedCombinedBookCatalogInTheOrdinaryLocalInstallation() async throws {
        try await prepare(catalog: true)
    }
    @MainActor func testPrepareAllPendingReadingInterfacesInOneFreshInstallation() async throws {
        try await prepare(catalog: true)
        let store = try HarborReadingPluginStore(), document = try await store.load()
        guard document.plugins.count == 3, document.plugins.allSatisfy({ $0.entry.id.hasPrefix("owned.ui.reading.") }),
              document.repositories.allSatisfy({ $0.url.hasPrefix("https://example.org/owned-reading/") }) else { XCTFail("Refuse configured reading sources"); return }
        try await appendBulk(store, document: document)
    }
    @MainActor private func appendBulk(_ store: HarborReadingPluginStore, document: HarborReadingPluginDocument) async throws {
        let entries = ["bad", "a", "b"].map { name in
            HarborReadingPluginEntry(raw: .object(["id": .string("owned.ui.reading.bulk." + name), "name": .string("Owned bulk " + name), "entry": .string(name + ".js"), "version": .string("1")]))
        }
        var next = document
        next.repositories.append(.init(kind: .ebook, url: "http://127.0.0.1:18734/bulk/repo.json", name: "Owned bulk repository", entries: entries, checkedAt: Date()))
        _ = try await store.commit(next, expected: document.revision)
    }
    @MainActor private func prepare(catalog: Bool) async throws {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else { XCTFail("Refuse to seed an account"); return }
        let context = AppProfileContext.shared; try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil,
              context.profiles.active?.desktop.isKid == false, context.configuration?.account == nil else { XCTFail("Refuse configured profiles"); return }
        if context.configuration?.guestAddons == nil { try context.save(HouseholdSourceAccount(account: nil, guestAddons: [])) }
        let store = try HarborReadingPluginStore(), current = try await store.load()
        guard current.plugins.allSatisfy({ $0.entry.id.hasPrefix("owned.ui.reading.") }),
              current.repositories.allSatisfy({ $0.url.hasPrefix("https://example.org/owned-reading/") }) else { XCTFail("Refuse configured reading sources"); return }
        let scope = PluginExecutionScope(owner: "owned-reading-ui", activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: store, network: ReadingSeedNetwork(catalog: catalog))
        defer { manager.dispose() }; try await manager.load()
        if current.repositories.isEmpty {
            try await manager.addRepository("https://example.org/owned-reading/manga.json", kind: .manga)
            try await manager.addRepository("https://example.org/owned-reading/books.json", kind: .ebook)
        }
        for repository in manager.document.repositories { for entry in repository.entries { try await manager.install(entry, repository: repository) } }
        XCTAssertEqual(manager.document.plugins.count, catalog ? 3 : 2)
        let defaults = UserDefaults.standard
        defaults.set("es", forKey: "uiLanguage"); defaults.set(true, forKey: "nativeGuide.initialized.v1"); defaults.set(true, forKey: "nativeGuide.completed.v1")
        defaults.set(false, forKey: "interface.autoRotateBanners"); defaults.set("long", forKey: "manga.reader.mode")
        defaults.set("width", forKey: "manga.reader.fit"); defaults.set(1.0, forKey: "manga.reader.zoom")
    }
}
