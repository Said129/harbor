import XCTest
@testable import Harbor

@MainActor private final class BookLibraryMemory: EBookLibraryPersistence {
    var values: [String: EBookLibraryDocument] = [:]
    var failRead = false
    var failWrite = false
    var writes = 0
    func read(_ key: String) throws -> EBookLibraryDocument? {
        if failRead { throw HarborError(code: "owned-read") }
        return values[key]
    }
    func write(_ value: EBookLibraryDocument, key: String) throws {
        if failWrite { throw HarborError(code: "owned-write") }
        writes += 1; values[key] = value
    }
}

@MainActor final class EBookLibraryTests: XCTestCase {
    func testListsMigrateOnceRemainIndependentAndCannotCrossProfileOwners() throws {
        let memory = BookLibraryMemory(), book = EBook(id: "local:owned", title: "Owned")
        let first = EBookLibraryStore(owner: "one", legacy: [book], persistence: memory)
        XCTAssertTrue(first.ready); XCTAssertTrue(first.contains(book, in: .saved))
        XCTAssertFalse(first.contains(book, in: .favorites)); XCTAssertFalse(first.contains(book, in: .readLater))
        try first.toggle(book, in: .favorites); try first.toggle(book, in: .readLater); try first.toggle(book, in: .saved)
        XCTAssertFalse(first.contains(book, in: .saved)); XCTAssertTrue(first.contains(book, in: .favorites)); XCTAssertTrue(first.contains(book, in: .readLater))
        let restored = EBookLibraryStore(owner: "one", legacy: [book], persistence: memory)
        XCTAssertFalse(restored.contains(book, in: .saved), "Removing a bookmark must survive legacy migration")
        XCTAssertEqual(restored.books(.favorites).map(\.id), [book.id])
        let other = EBookLibraryStore(owner: "two", persistence: memory)
        XCTAssertTrue(other.books(.favorites).isEmpty)
        memory.values[EBookLibraryStore.key("two")] = memory.values[EBookLibraryStore.key("one")]
        let rejected = EBookLibraryStore(owner: "two", persistence: memory)
        XCTAssertFalse(rejected.ready); XCTAssertTrue(rejected.books(.favorites).isEmpty)
        try restored.removeEverywhere(book)
        XCTAssertTrue(EBookLibraryList.allCases.allSatisfy { restored.books($0).isEmpty })
    }

    func testFailedWritesAndUnavailableLegacyNeverPublishOrOverwriteAnotherState() throws {
        let memory = BookLibraryMemory(), book = EBook(id: "source:owned", title: "Owned")
        let unavailable = EBookLibraryStore(owner: "not-read", legacy: nil, persistence: memory)
        XCTAssertFalse(unavailable.ready); XCTAssertEqual(memory.writes, 0)
        let lists = EBookLibraryStore(owner: "one", persistence: memory), writes = memory.writes
        memory.failWrite = true
        XCTAssertThrowsError(try lists.toggle(book, in: .favorites))
        XCTAssertTrue(lists.books(.favorites).isEmpty); XCTAssertEqual(memory.writes, writes)
        memory.failWrite = false; try lists.toggle(book, in: .favorites)
        memory.failRead = true; lists.reload()
        XCTAssertFalse(lists.ready); XCTAssertEqual(lists.books(.favorites).map(\.id), [book.id])
        XCTAssertThrowsError(try lists.toggle(book, in: .favorites))
        memory.failRead = false; lists.reload(); XCTAssertTrue(lists.ready)
        XCTAssertEqual(lists.books(.favorites).map(\.id), [book.id])
    }

    func testRemovingBookmarkAndFavoritesDoesNotDeleteActualEPUBProgressOrBookmarks() async throws {
        let owner = "owned-book-lists-" + UUID().uuidString, service = EBookService()
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reader", withExtension: "epub", subdirectory: "Fixtures"))
        let book = try await service.importDocument(file, owner: owner), shelf = EBookShelf(owner: owner)
        addTeardownBlock { @MainActor in
            try? await service.remove(book, owner: owner)
            try? KeychainStore().remove("ebook-shelf-" + EBookShelf.hash(owner))
            try? KeychainStore().remove(EBookLibraryStore.key(owner))
        }
        var record = EBookRecord(book: book); record.chapter = 1; record.block = 1
        record.bookmarks = [.init(id: UUID(), chapter: 1, block: 1, preview: "Owned bookmark")]
        try shelf.save(record)
        XCTAssertTrue(shelf.library.contains(book, in: .saved))
        try shelf.library.toggle(book, in: .favorites); try shelf.library.toggle(book, in: .saved); try shelf.library.toggle(book, in: .favorites)
        let restored = EBookShelf(owner: owner), saved = try XCTUnwrap(restored.record(book))
        XCTAssertEqual(saved.chapter, 1); XCTAssertEqual(saved.block, 1); XCTAssertEqual(saved.bookmarks.count, 1)
        XCTAssertFalse(restored.library.contains(book, in: .saved)); XCTAssertFalse(restored.library.contains(book, in: .favorites))
        let blocks = try await service.blocks(book, owner: owner, chapter: 1)
        XCTAssertEqual(blocks.map(\.text), ["Second section", "Five six seven."])
    }
}
