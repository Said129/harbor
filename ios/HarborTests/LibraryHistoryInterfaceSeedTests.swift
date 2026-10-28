import XCTest
@testable import Harbor

final class LibraryHistoryInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareIndependentOwnedHistoryForTheRealLibraryInterface() async throws {
        let (binding, _) = try ContinuePrivacyInterfaceSeedTests.prepareOwnedSharedGuest()
        let records: [JSONValue] = [
            .object(["_id": .string("owned-history-series"), "type": .string("series"), "name": .string("Owned episode"), "_mtime": .string("2026-10-28T00:00:00Z"), "state": .object(["season": .integer(5), "episode": .integer(23), "video_id": .string("owned-history-series:5:23"), "timeOffset": .integer(40_000), "duration": .integer(100_000)])]),
            .object(["_id": .string("owned-history-film"), "type": .string("movie"), "name": .string("Owned finished movie"), "_mtime": .string("2026-10-27T00:00:00Z"), "state": .object(["timesWatched": .integer(1)])]),
            .object(["_id": .string("owned-history-other"), "type": .string("movie"), "name": .string("Owned earlier movie"), "_mtime": .string("2026-10-26T00:00:00Z"), "state": .object(["timeOffset": .integer(20_000), "duration": .integer(100_000)])]),
        ]
        try await LibraryCache().save(records, owner: binding.progressOwner)
        var presentation = LibraryPresentation(); presentation.display.grouped = false
        try KeychainStore().write(presentation, key: LibraryPresentation.key(owner: binding.progressOwner))
        let trakt = TraktAccountStore.forOwner(binding.personalOwner); try trakt.load(); XCTAssertNil(trakt.session)
    }
}
