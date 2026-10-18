import XCTest
@testable import Harbor

@MainActor final class ProfileLibraryBindingTests: XCTestCase {
    private func unique(_ suffix: String) -> String { "synthetic-library-profile-" + UUID().uuidString + "-" + suffix }
    private func record(_ media: Media) -> JSONValue { .object(LibraryRecord.new(media)) }

    func testIndependentGuestLibrariesStaySeparateAndRestoreTheirOriginalSavedItems() async throws {
        let sourceA = unique("source-a"), sourceB = unique("source-b"), personA = unique("person-a"), personB = unique("person-b")
        let first = Media(id: "tt99900001", type: "movie", name: "Synthetic first guest")
        let second = Media(id: "tt99900002", type: "movie", name: "Synthetic second guest")
        let cache = LibraryCache()
        try await cache.save([record(first)], owner: sourceA)
        let library = LibraryModel()
        await library.setSession(nil, personalOwner: personA, guestOwner: sourceA, synchronize: false)
        XCTAssertEqual(library.items.map(\.id), [first.id]); XCTAssertEqual(library.owner, sourceA)
        await library.setSession(nil, personalOwner: personB, guestOwner: sourceB, synchronize: false)
        XCTAssertTrue(library.items.isEmpty); XCTAssertEqual(library.owner, sourceB)
        await library.toggleBookmark(second)
        XCTAssertTrue(library.bookmarked(second)); XCTAssertFalse(library.bookmarked(first))
        await library.setSession(nil, personalOwner: personA, guestOwner: sourceA, synchronize: false)
        XCTAssertTrue(library.bookmarked(first)); XCTAssertFalse(library.bookmarked(second))
        let savedB = try await cache.readSnapshot(owner: sourceB)
        XCTAssertEqual(savedB.items.map(\.id), [second.id])
    }

    func testSharedStremioAccountKeepsPersonalFavoritesAndDiscoverySeparate() async throws {
        let account = unique("same-account"), personA = unique("person-a"), personB = unique("person-b")
        let session = AccountSession(authKey: "synthetic-offline-only", user: AccountUser(id: account, email: nil, fullname: nil))
        let movie = Media(id: "tt99900003", type: "movie", name: "Synthetic shared source")
        try await LibraryCache().save([record(movie)], owner: account)
        let library = LibraryModel()
        await library.setSession(session, personalOwner: personA, synchronize: false)
        library.favorites.toggle(movie)
        XCTAssertTrue(library.favorites.contains(movie)); XCTAssertEqual(library.discovery.owner, personA)
        await library.setSession(session, personalOwner: personB, synchronize: false)
        XCTAssertEqual(library.owner, account); XCTAssertTrue(library.bookmarked(movie))
        XCTAssertFalse(library.favorites.contains(movie)); XCTAssertEqual(library.discovery.owner, personB)
        await library.setSession(session, personalOwner: personA, synchronize: false)
        XCTAssertTrue(library.favorites.contains(movie)); XCTAssertEqual(library.discovery.owner, personA)
    }

    func testOnlyTheSameReadyPersonalAndSourceBindingCanReuseTheLoadedLibrary() async throws {
        let source = unique("source"), person = unique("person")
        let library = LibraryModel()
        XCTAssertFalse(library.matchesSession(nil, personalOwner: person, guestOwner: source))
        await library.setSession(nil, personalOwner: person, guestOwner: source, synchronize: false)
        XCTAssertTrue(library.matchesSession(nil, personalOwner: person, guestOwner: source))
        XCTAssertFalse(library.matchesSession(nil, personalOwner: unique("other-person"), guestOwner: source))
        XCTAssertFalse(library.matchesSession(nil, personalOwner: person, guestOwner: unique("other-source")))
        await library.setSession(nil, guestOwner: source, synchronize: false)
        XCTAssertEqual(library.personalOwner, source); XCTAssertEqual(library.favorites.owner, source)
        XCTAssertEqual(library.discovery.owner, source)
    }
}
