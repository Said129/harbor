import XCTest
@testable import Harbor

@MainActor private final class ControlledArtistMetadata: MusicArtistCalling {
    private(set) var offsets: [Int] = []
    private(set) var batches: [Int] = []
    var delayedGenre: Int?
    var held: CheckedContinuation<MusicArtistPage, any Error>?
    func roster(_ genre: Int, offset: Int) async throws -> MusicArtistPage {
        offsets.append(offset)
        if genre == delayedGenre { return try await withCheckedThrowingContinuation { held = $0 } }
        let names = offset == 0 ? ["first", "second"] : ["first", "third"]
        return .init(artists: names.map { .init(id: "genre:\(genre):" + $0, connectorId: "catalog", name: $0) }, next: offset == 0 ? 3 : nil)
    }
    func audience(_ artists: [MusicArtistReference]) async throws -> [MusicArtistAudience] {
        batches.append(artists.count); return artists.map { .init(artist: $0, fans: 1234) }
    }
    func recording(_ track: MusicTrack) async throws -> MusicRecordingProfile? { nil }
}
@MainActor final class MusicArtistModelTests: XCTestCase {
    func testPagingDeduplicatesProviderIdentityAndEnrichesInBoundedBatchesWithoutChangingCursor() async throws {
        let client = ControlledArtistMetadata(), model = MusicArtistRosterModel()
        await model.load(132, known: [], client: client)
        try await wait { model.rows.count == 2 && model.rows.allSatisfy { $0.fans == 1234 } }
        await model.loadNext(known: [], client: client)
        try await wait { model.rows.count == 3 && model.rows.allSatisfy { $0.fans == 1234 } }
        XCTAssertEqual(client.offsets, [0, 3]); XCTAssertEqual(model.rows.map(\.artist.name), ["first", "second", "third"])
        XCTAssertTrue(model.exhausted); XCTAssertFalse(model.loading); XCTAssertFalse(model.failure)
        XCTAssertTrue(client.batches.allSatisfy { (1...3).contains($0) })
        await model.loadNext(known: [], client: client); XCTAssertEqual(client.offsets, [0, 3]); model.cancel()
        await model.load(132, known: [], client: client)
        XCTAssertEqual(client.offsets, [0, 3]); XCTAssertEqual(model.rows.count, 3, "Returning from an artist must retain every loaded page")
        await model.load(132, known: [], client: client, revision: UUID())
        XCTAssertEqual(client.offsets, [0, 3, 0]); XCTAssertEqual(model.rows.count, 2, "Changed credentials must discard the previous worker's audience")
        model.cancel()
    }
    func testChangingGenreOrLeavingTheScreenDiscardsLateRosterAndAudience() async throws {
        let client = ControlledArtistMetadata(), model = MusicArtistRosterModel(); client.delayedGenre = 132
        let pending = Task { await model.load(132, known: [], client: client) }; try await wait { client.held != nil }
        await model.load(152, known: [], client: client)
        client.held?.resume(returning: .init(artists: [.init(id: "retired", connectorId: "catalog", name: "Retired")], next: nil)); client.held = nil
        await pending.value; XCTAssertEqual(model.rows.map(\.artist.id), ["genre:152:first", "genre:152:second"])
        let leaving = Task { await model.load(132, known: [], client: client) }; try await wait { client.held != nil }; model.cancel()
        client.held?.resume(returning: .init(artists: [.init(id: "left", connectorId: "catalog", name: "Left")], next: nil)); client.held = nil
        await leaving.value; XCTAssertTrue(model.rows.isEmpty)
    }
    private func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("The owned artist model did not settle"); throw HarborError(code: "owned-artist-model")
    }
}
