import XCTest
@testable import Harbor

/// Desktop's Stremio library repair (`src/lib/stremio-library-repair.ts`) over canned library records.
final class LibraryRepairTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private let sparse = #"{"_id":"tt0903747","name":"Breaking Bad","type":"series","state":{"timeOffset":"12","watched":"tt0903747:1:2:x"},"_mtime":"2026-01-01T00:00:00.000Z"}"#

    func testSparseRecordIsRewrittenToTheSchema() throws {
        let plan = LibraryRepair.plan([try json(sparse)], now: now)
        XCTAssertEqual(plan.total, 1)
        XCTAssertEqual(plan.needsRepair, 1)
        XCTAssertEqual(plan.alreadyClean, 0)
        let fixed = try XCTUnwrap(plan.repairs.first)
        XCTAssertEqual(fixed["posterShape"].string, "poster")
        XCTAssertEqual(fixed["removed"], .bool(false))
        XCTAssertEqual(fixed["_ctime"], .null)
        XCTAssertEqual(fixed["state"]["timeOffset"], .integer(0))
        XCTAssertEqual(fixed["state"]["watched"].string, "tt0903747:1:2:x")
        XCTAssertNotEqual(fixed["behaviorHints"], .null)
    }

    func testRewrittenRecordIsLeftAloneOnTheNextRun() throws {
        let fixed = try XCTUnwrap(LibraryRepair.normalize(try json(sparse), now: now))
        let plan = LibraryRepair.plan([fixed], now: now)
        XCTAssertEqual(plan.needsRepair, 0)
        XCTAssertEqual(plan.alreadyClean, 1)
    }

    func testRecordWithoutIdOrObjectIsUnrepairable() throws {
        let plan = LibraryRepair.plan([try json(#"{"name":"No id"}"#), .string("text")], now: now)
        XCTAssertEqual(plan.total, 2)
        XCTAssertEqual(plan.unrepairable, 2)
        XCTAssertEqual(plan.needsRepair, 0)
        XCTAssertEqual(plan.alreadyClean, 0)
    }

    func testEmptyLibraryHasNothingToRepair() {
        let plan = LibraryRepair.plan([], now: now)
        XCTAssertEqual(plan.total, 0)
        XCTAssertEqual(plan.needsRepair, 0)
        XCTAssertEqual(plan.alreadyClean, 0)
    }

    func testCloudAnimeIsLeftAlone() throws {
        let plan = LibraryRepair.plan([try json(#"{"_id":"kitsu:1234","name":"Anime"}"#)], now: now)
        XCTAssertEqual(plan.needsRepair, 0)
        XCTAssertEqual(plan.alreadyClean, 1)
        XCTAssertEqual(plan.unrepairable, 0)
    }

    func testRemovedCloudAnimeIsRepaired() throws {
        let plan = LibraryRepair.plan([try json(#"{"_id":"mal:99","removed":true}"#)], now: now)
        XCTAssertEqual(plan.needsRepair, 1)
        XCTAssertEqual(plan.repairs.first?["removed"], .bool(true))
    }

    func testHarborOnlyFieldsSurviveTheRepair() throws {
        let raw = try json(#"{"_id":"tt0903747","imdb_id":"tt0903747","state":{"nativeManualEpisodes":{"tt0903747:1:1":true}}}"#)
        let fixed = try XCTUnwrap(LibraryRepair.plan([raw], now: now).repairs.first)
        XCTAssertEqual(fixed["imdb_id"].string, "tt0903747")
        XCTAssertEqual(fixed["state"]["nativeManualEpisodes"]["tt0903747:1:1"], .bool(true))
    }

    func testVideoIdFallsBackAndTheAliasIsDropped() throws {
        let raw = try json(#"{"_id":"tt1","state":{"videoId":"tt1:1:1"}}"#)
        let fixed = try XCTUnwrap(LibraryRepair.normalize(raw, now: now))
        XCTAssertEqual(fixed["state"]["video_id"].string, "tt1:1:1")
        XCTAssertEqual(fixed["state"]["videoId"], .null)
    }

    func testWatchedMarkerNeedsANumberInItsSecondToLastPart() throws {
        let bad = try XCTUnwrap(LibraryRepair.normalize(try json(#"{"_id":"tt1","state":{"watched":"tt1:x:y"}}"#), now: now))
        XCTAssertEqual(bad["state"]["watched"], .null)
        let good = try XCTUnwrap(LibraryRepair.normalize(try json(#"{"_id":"tt1","state":{"watched":"tt1:3:4:5"}}"#), now: now))
        XCTAssertEqual(good["state"]["watched"].string, "tt1:3:4:5")
    }

    func testMissingModifiedTimeGetsTheCurrentTime() throws {
        let fixed = try XCTUnwrap(LibraryRepair.normalize(try json(#"{"_id":"tt1"}"#), now: now))
        XCTAssertTrue(fixed["_mtime"].string?.hasPrefix("2027-01-15") ?? false)
    }

    func testWritesGoOutInBatchesOfTwentyFive() throws {
        let records = try (0..<60).map { try json("{\"_id\":\"tt\($0)\"}") }
        let repairs = LibraryRepair.plan(records, now: now).repairs
        XCTAssertEqual(repairs.count, 60)
        XCTAssertEqual(LibraryRepair.batches(repairs).map(\.count), [25, 25, 10])
    }
}
