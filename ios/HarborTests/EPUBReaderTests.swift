import XCTest
import UIKit
@testable import Harbor

final class EPUBReaderTests: XCTestCase {
    @MainActor func testRealArchiveUsesSpineOrderAndPreservesInlineTextWithoutExecutingBookContent() throws {
        XCTAssertNotNil(UIFont(name: "SwitzerVariable-Regular", size: 16), "The original interface font must be registered in the app host")
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader", withExtension: "epub", subdirectory: "Fixtures"))
        let reader = try EPUBReader(data: Data(contentsOf: file))
        XCTAssertEqual(reader.publication.title, "Harbor reader fixture")
        XCTAssertEqual(reader.publication.authors, ["Harbor tests"])
        XCTAssertEqual(reader.publication.chapters.map(\.title), ["First section", "Second section"])
        let first = try reader.blocks(reader.publication.chapters[0])
        XCTAssertEqual(first.map(\.text), ["First section", "One two three & four.", "Literal <text>"])
        let second = try reader.blocks(reader.publication.chapters[1])
        XCTAssertEqual(second.map(\.text), ["Second section", "Five six seven."])
        XCTAssertTrue(first.allSatisfy { $0.image == nil })
        let owner = "tests-ebook-\(UUID().uuidString)"
        defer { try? KeychainStore().remove("ebook-shelf-" + EBookShelf.hash(owner)) }
        let book = EBook(id: "local-reader-test", title: reader.publication.title)
        let shelf = EBookShelf(owner: owner)
        try shelf.save(EBookRecord(book: book))
        var marked = try XCTUnwrap(shelf.record(book)); marked.completed = true
        let bookmarkBlock = try XCTUnwrap(first.dropFirst().first)
        let bookmark = EBookBookmark(id: UUID(), chapter: 0, block: bookmarkBlock.id, preview: bookmarkBlock.text)
        marked.bookmarks.append(bookmark); try shelf.save(marked)
        let position = try XCTUnwrap(second.last).id
        try shelf.savePosition(book, chapter: 1, block: position)
        let restored = try XCTUnwrap(EBookShelf(owner: owner).record(book))
        XCTAssertEqual(restored.chapter, 1); XCTAssertEqual(restored.block, position)
        XCTAssertTrue(restored.completed, "A delayed position write must preserve a newer read-state change")
        XCTAssertEqual(restored.bookmarks.map(\.id), [bookmark.id], "A position write must retain the actual bookmark saved before it")
        XCTAssertNil(EBookShelf(owner: owner + ".other").record(book))
        XCTAssertThrowsError(try shelf.savePosition(book, chapter: -1, block: 0))
        XCTAssertEqual(EBookShelf(owner: owner).record(book)?.block, position)
    }
}
