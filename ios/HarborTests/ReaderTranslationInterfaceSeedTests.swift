import XCTest
@testable import Harbor

final class ReaderTranslationInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedCachedTranslationsWithoutAnAPIKeyInOneFreshGuest() async throws {
        try await EBookDetailInterfaceSeedTests.prepare()
        let owner = try XCTUnwrap(AppProfileContext.shared.binding?.personalOwner)
        XCTAssertNil(try KeychainStore().read(EBookTranslationSettings.key(owner), as: EBookTranslationSettings.self))
        let scope = PluginExecutionScope(owner: owner, activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore(), network: BookChapterNetwork())
        defer { manager.dispose() }; try await manager.load()
        let plugin = try XCTUnwrap(manager.installed(.ebook).first), books = try await manager.ebookBrowse(plugin, query: "", offset: 0)
        let book = try XCTUnwrap(books.first), publication = try await manager.ebookPublication(book)
        var settings = EBookTranslationSettings(); settings.targetLanguage = "es"
        try settings.save(owner: owner)
        let program = EBookTranslationProgram(), cache = try EBookTranslationCache(owner: owner)
        for chapter in publication.chapters {
            let blocks = try await manager.ebookBlocks(book, chapter: chapter)
            let source = blocks.map(\.text).joined(separator: "\n\n")
            let prepared = try await program.apply(.object(["operation": .string("prepare"), "source": .string(source), "title": .string(chapter.title), "settings": settings.raw]))
            try await cache.save(.init(title: "Traducción " + chapter.id, text: "Capítulo traducido " + chapter.id + "."), slot: XCTUnwrap(prepared["slot"].string))
        }
        try EBookShelf(owner: owner).addImported(book)
        UserDefaults.standard.set("harbor", forKey: "ebook.mode"); UserDefaults.standard.set(false, forKey: "ebook.focusMode")
    }
}
