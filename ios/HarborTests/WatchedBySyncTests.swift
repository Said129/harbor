import XCTest
@testable import Harbor

@MainActor private final class WatchedByMemory: WatchedByPersistence {
    var values: [String: WatchedBySyncRecord] = [:]
    var failWrites = false
    func readWatchedBy(_ key: String) throws -> WatchedBySyncRecord? { values[key] }
    func writeWatchedBy(_ value: WatchedBySyncRecord, key: String) throws {
        if failWrites { throw HarborError(code: "owned-write-failed") }
        values[key] = value
    }
}
@MainActor final class WatchedBySyncTests: XCTestCase {
    private func state(_ value: JSONValue?, rev: Int64) -> JSONValue {
        .object(["rev": .integer(rev), "docs": .array(value.map { [.object(["key": .string(HarborWatchedBySync.documentKey), "rev": .integer(rev), "value": $0])] } ?? [])])
    }
    private func accepted(_ rev: Int64) -> JSONValue { .object(["results": .array([.object(["ok": .bool(true), "rev": .integer(rev)])])]) }
    private func entry(_ profile: String, _ time: Double) -> JSONValue { .object(["p": .string(profile), "t": .number(time)]) }

    func testAnUntouchedPullNormalizesLegacyValuesWithoutUploadingDefaults() async throws {
        let engine = HarborWatchedBySync(owner: "owned", account: "A", persistence: WatchedByMemory())
        try await engine.synchronize(state: state(.object(["film": .string("p_old")]), rev: 1), send: { _ in XCTFail("A legacy read is already equivalent"); return .null }, check: {})
        XCTAssertEqual(engine.value.entries["film"]?.profile, "p_old"); XCTAssertFalse(engine.hasPendingChanges)
    }
    func testOfflineWatchesMergeWithOtherDevicesAndOnlyTheAllowedMapIsUploaded() async throws {
        let memory = WatchedByMemory()
        let durable = HarborWatchedBySync(owner: "durable", account: "A", persistence: memory)
        try durable.record(mediaID: "local", profileID: "p_local", at: 100)
        let reopened = HarborWatchedBySync(owner: "durable", account: "A", persistence: memory)
        var posts = 0
        try await reopened.synchronize(state: state(.object(["remote": entry("p_remote", 200)]), rev: 5), send: { body in
            posts += 1
            let write = try XCTUnwrap(body["writes"].array.first)
            XCTAssertEqual(write["key"].string, "account:watchedby"); XCTAssertEqual(write["baseRev"].numericValue, 5)
            XCTAssertEqual(Set(write["value"].objectValue.keys), ["local", "remote"])
            for value in write["value"].objectValue.values { XCTAssertEqual(Set(value.objectValue.keys), ["p", "t"]) }
            return self.accepted(6)
        }, check: {})
        XCTAssertEqual(posts, 1); XCTAssertFalse(reopened.hasPendingChanges)
        XCTAssertFalse(HarborWatchedBySync(owner: "durable", account: "A", persistence: memory).hasPendingChanges)
    }
    func testAWatchRecordedDuringThePostRemainsPendingAfterTheSentSnapshotIsAcknowledged() async throws {
        let memory = WatchedByMemory()
        let active = HarborWatchedBySync(owner: "durable", account: "A", persistence: memory)
        try active.record(mediaID: "first", profileID: "p1", at: 100)
        var sent: JSONValue = .null
        try await active.synchronize(state: state(nil, rev: 0), send: { body in
            sent = body["writes"].array[0]["value"]
            try active.record(mediaID: "later", profileID: "p2", at: 200)
            return self.accepted(1)
        }, check: {})
        XCTAssertTrue(active.hasPendingChanges)
        let reopened = HarborWatchedBySync(owner: "durable", account: "A", persistence: memory)
        XCTAssertTrue(reopened.hasPendingChanges)
        try await reopened.synchronize(state: state(sent, rev: 1), send: { body in
            XCTAssertEqual(body["writes"].array[0]["baseRev"].numericValue, 1)
            XCTAssertNotEqual(body["writes"].array[0]["value"]["later"], .null)
            return self.accepted(2)
        }, check: {})
        XCTAssertFalse(reopened.hasPendingChanges)
    }
    func testARejectedWriteMergesNewerWatchersAndRequeuesDistinctLocalTitles() async throws {
        let engine = HarborWatchedBySync(owner: "owned", account: "A", persistence: WatchedByMemory())
        try engine.record(mediaID: "same", profileID: "local", at: 100)
        try engine.record(mediaID: "only-local", profileID: "local", at: 100)
        var requested = 0; engine.requestSync = { requested += 1 }
        let winner: JSONValue = .object(["same": entry("remote", 200), "only-remote": entry("remote", 200)])
        try await engine.synchronize(state: state(nil, rev: 0), send: { _ in
            .object(["results": .array([.object(["ok": .bool(false), "current": .object(["key": .string("account:watchedby"), "rev": .integer(2), "value": winner])])])])
        }, check: {})
        XCTAssertEqual(engine.value.entries["same"]?.profile, "remote")
        XCTAssertEqual(Set(engine.value.entries.keys), ["same", "only-local", "only-remote"])
        XCTAssertTrue(engine.hasPendingChanges); XCTAssertEqual(requested, 1)
    }
    func testSeparateAccountsAndUnsignedWatchesNeverShareTheSameBucket() throws {
        let memory = WatchedByMemory()
        let a = HarborWatchedBySync(owner: "owned", account: "A", persistence: memory)
        let b = HarborWatchedBySync(owner: "owned", account: "B", persistence: memory)
        let local = HarborWatchedBySync(owner: "owned", account: nil, persistence: memory)
        try a.record(mediaID: "A-only", profileID: "p1", at: 1)
        try b.record(mediaID: "B-only", profileID: "p2", at: 2)
        try local.record(mediaID: "unsigned", profileID: "p1", at: 3)
        XCTAssertEqual(Set(HarborWatchedBySync(owner: "owned", account: "A", persistence: memory).value.entries.keys), ["A-only"])
        XCTAssertEqual(Set(b.value.entries.keys), ["B-only"]); XCTAssertFalse(local.hasPendingChanges)
        XCTAssertEqual(memory.values.count, 3)
    }
    func testARetiredAccountLeaseCannotAcknowledgeTheResponse() async throws {
        let engine = HarborWatchedBySync(owner: "owned", account: "A", persistence: WatchedByMemory())
        try engine.record(mediaID: "film", profileID: "local", at: 10)
        var current = true
        do {
            try await engine.synchronize(state: state(nil, rev: 0), send: { _ in current = false; return self.accepted(1) }, check: {
                if !current { throw HarborError(code: "account-changed") }
            })
            XCTFail("The retired account must not commit")
        } catch let error as HarborError { XCTAssertEqual(error.code, "account-changed") }
        XCTAssertTrue(engine.hasPendingChanges); XCTAssertEqual(engine.value.entries["film"]?.profile, "local")
    }
    func testFailedPersistenceKeepsThePreviousWatchAndStaleServerRevisionsAreRejected() async throws {
        let memory = WatchedByMemory()
        let durable = HarborWatchedBySync(owner: "durable", account: "A", persistence: memory)
        try await durable.synchronize(state: state(.object(["film": entry("old", 100)]), rev: 3), send: { _ in XCTFail(); return .null }, check: {})
        memory.failWrites = true
        XCTAssertThrowsError(try durable.record(mediaID: "film", profileID: "new", at: 200))
        XCTAssertEqual(durable.value.entries["film"]?.profile, "old")
        do {
            try await durable.synchronize(state: state(.object([:]), rev: 2), send: { _ in XCTFail(); return .null }, check: {})
            XCTFail("A stale revision is invalid")
        } catch let error as HarborError { XCTAssertEqual(error.code, "watched-by-revision") }
    }
}
