import XCTest
@testable import Harbor

final class EBookBookmarkTests: XCTestCase {
    func testLegacyBookmarksUpgradeOnceAndStableSourceIDsNeverJumpToAReorderedOrRemovedChapter() throws {
        let first = UUID(), second = UUID()
        let legacy = "[{\"id\":\"\(first)\",\"chapter\":0,\"block\":9,\"preview\":\"First\"},{\"id\":\"\(second)\",\"chapter\":1,\"block\":27,\"preview\":\"Second\"}]"
        let items = try JSONDecoder().decode([EBookBookmark].self, from: Data(legacy.utf8))
        let publication = EBookPublication(title: "Owned", authors: [], language: nil,
            chapters: [.init(path: "source:first", title: "First", number: "1"), .init(path: "source:second", title: "Second", number: "2")])
        let upgraded = EBookBookmarks.upgrading(items, in: publication, volumes: [])
        XCTAssertEqual(upgraded.map(\.id), [second, first]); XCTAssertEqual(upgraded.map(\.chapterID), ["source:second", "source:first"])
        let restored = try JSONDecoder().decode([EBookBookmark].self, from: JSONEncoder().encode(upgraded))
        XCTAssertEqual(EBookBookmarks.upgrading(restored, in: publication, volumes: []).map(\.id), [second, first], "Do not reverse already migrated bookmarks on each launch")
        let reordered = EBookPublication(title: "Owned", authors: [], language: nil, chapters: Array(publication.chapters.reversed()))
        XCTAssertEqual(restored.compactMap { EBookBookmarks.chapter($0, in: reordered) }, [0, 1])
        let removed = EBookPublication(title: "Owned", authors: [], language: nil, chapters: [publication.chapters[0]])
        XCTAssertNil(EBookBookmarks.chapter(restored[0], in: removed), "A missing source ID must not fall back to the numeric position of a different chapter")
        let invalid = EBookBookmark(id: UUID(), chapter: 99, block: 0, preview: "Removed")
        XCTAssertNil(EBookBookmarks.chapter(invalid, in: publication))
    }

    @MainActor func testActualProfilePersistenceKeepsNewestFirstDeduplicatesCapsAndPreservesBookmarksAcrossPositionWrites() throws {
        let owner = "bookmarks-" + UUID().uuidString
        defer { try? KeychainStore().remove("ebook-shelf-" + EBookShelf.hash(owner)) }
        let publication = EBookPublication(title: "Owned", authors: [], language: nil, chapters: [.init(path: "source:owned", title: "Chapter", number: "7")])
        let text = String(repeating: "😀", count: 80)
        let paragraphs = [EBookSearchParagraph(block: 9, text: "First"), .init(block: 27, text: text)]
        let latest = try XCTUnwrap(EBookBookmarks.make(chapter: 0, block: 27, paragraphs: paragraphs, publication: publication, volumes: []))
        XCTAssertEqual(latest.line, 1); XCTAssertEqual(latest.preview, String(repeating: "😀", count: 70)); XCTAssertEqual(latest.preview.utf16.count, 140)
        XCTAssertNil(EBookBookmarks.make(chapter: 0, block: 99, paragraphs: paragraphs, publication: publication, volumes: []))
        var entries = (0..<301).map { EBookBookmark(id: UUID(), chapter: 0, block: $0, preview: "Owned \($0)", chapterID: "source:owned") }
        let duplicated = entries[27].id, oldest = entries.last!.id
        entries = EBookBookmarks.adding(latest, to: entries, in: publication)
        XCTAssertEqual(entries.count, 300); XCTAssertEqual(entries.first?.id, latest.id)
        XCTAssertFalse(entries.contains { $0.id == duplicated || $0.id == oldest })
        XCTAssertEqual(entries.filter { $0.block == 27 }.count, 1)
        let book = EBook(id: "owned", title: "Owned"), shelf = EBookShelf(owner: owner)
        var record = EBookRecord(book: book); record.bookmarks = entries; record.completed = true; try shelf.save(record)
        try shelf.savePosition(book, chapter: 0, block: 9)
        let restoredShelf = EBookShelf(owner: owner), restored = try XCTUnwrap(restoredShelf.record(book))
        XCTAssertEqual(restored.bookmarks.map(\.id), entries.map(\.id)); XCTAssertTrue(restored.completed); XCTAssertEqual(restored.block, 9)
        XCTAssertEqual(restored.bookmarks.first?.chapterID, "source:owned"); XCTAssertEqual(restored.bookmarks.first?.line, 1)
        XCTAssertNil(EBookShelf(owner: owner + ".other").record(book))
        var deleted = restored; deleted.bookmarks.removeAll { $0.id == latest.id }; try restoredShelf.save(deleted)
        XCTAssertFalse(try XCTUnwrap(EBookShelf(owner: owner).record(book)).bookmarks.contains { $0.id == latest.id })
        XCTAssertEqual(EBookShelf(owner: owner).record(book)?.block, 9)
    }
}
