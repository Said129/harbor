import XCTest
@testable import Harbor

final class ReaderBookmarkInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedBookAndTwoBookmarkRoutesInOneFreshGuest() async throws {
        try await EBookDetailInterfaceSeedTests.prepare()
        let owner = try XCTUnwrap(AppProfileContext.shared.binding?.personalOwner)
        let scope = PluginExecutionScope(owner: owner, activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore(), network: BookChapterNetwork())
        defer { manager.dispose() }; try await manager.load()
        let plugin = try XCTUnwrap(manager.installed(.ebook).first), books = try await manager.ebookBrowse(plugin, query: "", offset: 0)
        let book = try XCTUnwrap(books.first), publication = try await manager.ebookPublication(book), volumes = try await EBookDetailProgram().groups(publication.chapters)
        var record = EBookRecord(book: book)
        for index in [0, 2] {
            let blocks = try await manager.ebookBlocks(book, chapter: publication.chapters[index])
            let bookmark = try XCTUnwrap(EBookBookmarks.make(chapter: index, block: 0, paragraphs: EBookSearchParagraph.make(blocks), publication: publication, volumes: volumes))
            record.bookmarks = EBookBookmarks.adding(bookmark, to: record.bookmarks, in: publication)
        }
        try EBookShelf(owner: owner).save(record)
        UserDefaults.standard.set("harbor", forKey: "ebook.mode"); UserDefaults.standard.set(false, forKey: "ebook.focusMode")
    }
}
