import XCTest
@testable import Harbor

final class ReaderAnnotationInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedChapterAndCrossChapterReferenceInOneFreshGuest() async throws {
        try await EBookDetailInterfaceSeedTests.prepare()
        let owner = try XCTUnwrap(AppProfileContext.shared.binding?.personalOwner), scope = PluginExecutionScope(owner: owner, activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore(), network: BookChapterNetwork())
        defer { manager.dispose() }; try await manager.load()
        let plugin = try XCTUnwrap(manager.installed(.ebook).first), books = try await manager.ebookBrowse(plugin, query: "", offset: 0), book = try XCTUnwrap(books.first)
        var note = EBookAnnotation(chapterID: "original:1", chapterLabel: "Chapter 1", volumeLabel: "Volume 1", ranges: [.init(line: 0, start: 0, end: 6)], text: "Actual")
        note.id = "owned-reference"; note.reference = true; note.title = "Owned reference"
        let file = try EBookAnnotationFile(owner: owner, book: book.id)
        let existing = try await file.read(); XCTAssertTrue(existing.isEmpty); try await file.write([note])
        try EBookShelf(owner: owner).addImported(book)
        UserDefaults.standard.set("harbor", forKey: "ebook.mode"); UserDefaults.standard.set(false, forKey: "ebook.focusMode")
    }
}
