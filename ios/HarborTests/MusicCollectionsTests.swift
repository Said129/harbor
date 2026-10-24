import XCTest
@testable import Harbor

@MainActor private final class MusicCollectionsMemory: MusicCollectionsPersistence {
    var documents: [String: MusicCollectionsDocument] = [:]
    var unreadable: Set<String> = []
    var failWrite = false
    var writes = 0
    func read(owner: String) throws -> MusicCollectionsDocument? {
        if unreadable.contains(owner) { throw HarborError(code: "synthetic-read") }
        return documents[owner]
    }
    func write(_ value: MusicCollectionsDocument, owner: String) throws {
        if failWrite { throw HarborError(code: "synthetic-write") }
        documents[owner] = value; writes += 1
    }
}

@MainActor final class MusicCollectionsTests: XCTestCase {
    func testNewestFirstCollectionsKeepDesktopRecentLimitAndProfileIsolationAcrossRestart() throws {
        let memory = MusicCollectionsMemory(), store = MusicCollections(persistence: memory)
        for index in 0..<60 { XCTAssertTrue(store.recordPlayed("track:\(index)", owner: "one")) }
        let expected = (10..<60).reversed().map { "track:\($0)" }
        XCTAssertEqual(store.snapshot(owner: "one")?.recent, expected)
        XCTAssertTrue(store.recordPlayed("track:20", owner: "one"))
        XCTAssertEqual(store.snapshot(owner: "one")?.recent, ["track:20"] + expected.filter { $0 != "track:20" })
        XCTAssertTrue(store.setLiked("track:20", liked: true, owner: "one"))
        XCTAssertTrue(store.setLiked("track:10", liked: true, owner: "one"))
        XCTAssertTrue(store.setLiked("track:20", liked: false, owner: "one"))
        XCTAssertEqual(store.snapshot(owner: "one")?.liked, ["track:10"])
        XCTAssertEqual(store.snapshot(owner: "one")?.recent.first, "track:20", "Unliking preserves listening history")
        XCTAssertTrue(store.recordPlayed("track:20", owner: "two"))
        XCTAssertTrue(store.setLiked("track:20", liked: true, owner: "two"))
        let restarted = MusicCollections(persistence: memory)
        restarted.prepare(owner: "one"); restarted.prepare(owner: "two")
        XCTAssertEqual(restarted.snapshot(owner: "one"), store.snapshot(owner: "one"))
        XCTAssertEqual(restarted.snapshot(owner: "two"), MusicCollectionsDocument(liked: ["track:20"], recent: ["track:20"]))
        XCTAssertFalse(restarted.isLiked("track:20", owner: "one"))
    }

    func testFailedReadsWritesAndCorruptHistoryNeverOverwritePreservedCollections() throws {
        let original = MusicCollectionsDocument(liked: ["saved"], recent: ["played"])
        let memory = MusicCollectionsMemory(); memory.documents["owner"] = original; memory.unreadable.insert("owner")
        let store = MusicCollections(persistence: memory)
        XCTAssertFalse(store.setLiked("new", liked: true, owner: "owner")); XCTAssertNil(store.snapshot(owner: "owner"))
        XCTAssertEqual(memory.writes, 0); XCTAssertEqual(memory.documents["owner"], original)
        memory.unreadable.remove("owner"); store.retry(owner: "owner")
        XCTAssertEqual(store.snapshot(owner: "owner"), original)
        memory.failWrite = true
        XCTAssertFalse(store.recordPlayed("new", owner: "owner"))
        XCTAssertEqual(store.snapshot(owner: "owner"), original); XCTAssertEqual(memory.documents["owner"], original)
        memory.failWrite = false
        XCTAssertFalse(store.setLiked("", liked: true, owner: "owner")); XCTAssertEqual(memory.writes, 0)
        memory.documents["corrupt"] = MusicCollectionsDocument(liked: ["same", "same"])
        store.prepare(owner: "corrupt"); XCTAssertFalse(store.isReady(owner: "corrupt"))
        XCTAssertFalse(store.recordPlayed("replacement", owner: "corrupt")); XCTAssertEqual(memory.writes, 0)
        XCTAssertEqual(memory.documents["corrupt"]?.liked, ["same", "same"])
        XCTAssertNotNil(store.errors["owner"]); XCTAssertNotNil(store.errors["corrupt"])
    }

    func testOnlyActuallyLoadedOwnedAudioCreatesTheCurrentProfilesRecentEntry() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-tone", withExtension: "wav", subdirectory: "Fixtures"))
        let owner = "music-collections-audio-" + UUID().uuidString
        let imported = try await MusicFileService.shared.importFile(file, owner: owner)
        let record = imported.record
        let player = MusicPlayback.shared, collections = MusicCollections.shared
        player.stop(); defer { player.stop() }; collections.prepare(owner: owner)
        XCTAssertEqual(collections.snapshot(owner: owner)?.recent, [], "Reading/importing metadata must not record playback")
        do {
            player.play(record, queue: [record], owner: owner)
            let deadline = Date(timeIntervalSinceNow: 12)
            while Date() < deadline, (!player.loaded || player.position <= 0.1 || collections.snapshot(owner: owner)?.recent.first != record.id), player.error == nil {
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertNil(player.error); XCTAssertTrue(player.loaded); XCTAssertGreaterThan(player.position, 0.1)
            XCTAssertEqual(collections.snapshot(owner: owner)?.recent, [record.id])
            let missingOwner = owner + "-missing"; player.play(record, queue: [record], owner: missingOwner)
            XCTAssertNotNil(player.error); collections.prepare(owner: missingOwner)
            XCTAssertEqual(collections.snapshot(owner: missingOwner)?.recent, [], "An unavailable file must not populate another profile")
            player.stop(); try await MusicFileService.shared.remove(record, owner: owner)
        } catch {
            player.stop(); try? await MusicFileService.shared.remove(record, owner: owner); throw error
        }
    }
}
