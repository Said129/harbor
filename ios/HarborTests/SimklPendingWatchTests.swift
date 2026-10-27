import XCTest
@testable import Harbor

@MainActor final class OwnedSimklPendingMemory: SimklPendingPersistence {
    var values: [String: SimklPendingDocument] = [:]
    var fail = false
    func read(owner: String) throws -> SimklPendingDocument? { values[owner] }
    func write(_ value: SimklPendingDocument?, owner: String) throws { if fail { throw HarborError(code: "owned-pending-disk") }; values[owner] = value }
}
@MainActor private final class OwnedSimklTrackingLease { var active = true }
private actor OwnedSimklTrackingHold {
    private(set) var requests: [URLRequest] = []
    private var continuation: CheckedContinuation<SimklReply, Never>?
    func send(_ request: URLRequest) async -> SimklReply {
        requests.append(request)
        if requests.count == 1 { return await withCheckedContinuation { continuation = $0 } }
        return .init(status: 200, data: Data((request.url?.path == "/sync/history" ? "{\"added\":{\"movies\":1}}" : "{}").utf8))
    }
    func release() { continuation?.resume(returning: .init(status: 200, data: Data("{}".utf8))); continuation = nil }
}
@MainActor final class SimklPendingWatchTests: XCTestCase {
    func testQueueIsBoundedDurableSanitizedAndAnOldReplyCannotClearANewerIntent() throws {
        let memory = OwnedSimklPendingMemory(), queue = SimklPendingWatches(owner: "owned-queue", persistence: memory)
        try queue.bind("owned-first-token")
        var episode = Episode(id: "owned", season: 1, episode: 7, thumbnail: "https://owned.invalid/private-image", overview: String(repeating: "x", count: 20_000))
        episode.tvdbEpisodeID = 77
        let identity = SimklWatchIdentity(mediaID: "kitsu:123", episode: episode)
        let old = try queue.record(identity); XCTAssertNil(old.identity.episode?.thumbnail); XCTAssertNil(old.identity.episode?.overview); XCTAssertEqual(old.identity.episode?.tvdbEpisodeID, 77)
        let latest = try queue.record(identity); XCTAssertEqual(queue.document?.entries.count, 1)
        try queue.remove(old, fingerprint: EBookShelf.hash("owned-first-token")); XCTAssertEqual(queue.document?.entries.first?.id, latest.id)
        memory.fail = true; XCTAssertThrowsError(try queue.record(.init(mediaID: "tt0123456"))); XCTAssertEqual(queue.document?.entries.first?.id, latest.id)
        memory.fail = false
        for index in 0..<60 { _ = try queue.record(.init(mediaID: "tt\(1_000_000 + index)")) }
        XCTAssertEqual(queue.document?.entries.count, 50)
        let reopened = SimklPendingWatches(owner: "owned-queue", persistence: memory); try reopened.bind("owned-first-token"); XCTAssertEqual(reopened.document?.entries.count, 50)
        try reopened.bind("owned-other-account-token"); XCTAssertTrue(reopened.document?.entries.isEmpty == true)
        XCTAssertTrue(queue.beginFlush("first")); XCTAssertFalse(queue.beginFlush("first")); XCTAssertTrue(queue.beginFlush("second")); queue.endFlush("first"); XCTAssertFalse(queue.beginFlush("second"))
    }
    func testActualKeychainQueueReopensForItsOwnerAndTokenWithoutWritingPersonalTokensToDefaults() throws {
        let owner = "owned-pending-keychain-" + UUID().uuidString, token = "owned-pending-token-" + UUID().uuidString
        let queue = SimklPendingWatches(owner: owner); defer { try? queue.bind(nil) }
        try queue.bind(token); _ = try queue.record(.init(mediaID: "tt0123456"))
        let reopened = SimklPendingWatches(owner: owner); try reopened.bind(token); XCTAssertEqual(reopened.document?.entries.count, 1)
        let stored = try XCTUnwrap(KeychainStore().read("native-simkl-pending-v1-" + EBookShelf.hash(owner), as: SimklPendingDocument.self))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(stored), as: UTF8.self).contains(token))
        XCTAssertFalse(String(describing: UserDefaults.standard.dictionaryRepresentation()).contains(token))
        let other = SimklPendingWatches(owner: owner + "-other"); try other.bind(token); XCTAssertTrue(other.document?.entries.isEmpty == true)
    }
    func testReporterKeepsTheIntentUntilBothTerminalStopAndHistorySucceed() async throws {
        let memory = OwnedSimklPendingMemory(), queue = SimklPendingWatches(owner: "owned", persistence: memory)
        let account = SimklAccountStore(owner: "owned", persistence: OwnedSimklLibraryAccount()); try account.load()
        let clock = OwnedSimklClock(), replies = OwnedSimklReplies([
            .init(status: 200, data: Data("{}".utf8)), .init(status: 403, data: Data("{}".utf8)),
            .init(status: 200, data: Data("{}".utf8)), .init(status: 200, data: Data("{\"added\":{\"movies\":1}}".utf8))], clock: clock)
        let client = SimklClient(transport: { try await replies.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
        let reporter = SimklWatchReporter(account: account, queue: queue, client: client, active: { true })
        await reporter.send(.init(action: .stop, progress: 100, recordWatched: true), identity: .init(mediaID: "tt0123456"))
        XCTAssertEqual(queue.document?.entries.count, 1)
        await reporter.recover(); XCTAssertTrue(queue.document?.entries.isEmpty == true)
        let requests = await replies.requests; XCTAssertEqual(requests.map { $0.0.url!.path }, ["/scrobble/stop", "/sync/history", "/scrobble/stop", "/sync/history"])
    }
    func testTerminalReportsKeepCrossSessionOrderAndRetiredProfilesCannotSendTheirQueuedHistory() async throws {
        let memory = OwnedSimklPendingMemory(), queue = SimklPendingWatches(owner: "owned", persistence: memory)
        let account = SimklAccountStore(owner: "owned", persistence: OwnedSimklLibraryAccount()); try account.load()
        let clock = OwnedSimklClock(), held = OwnedSimklTrackingHold(), active = OwnedSimklTrackingLease()
        let client = SimklClient(transport: { await held.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
        let reporter = SimklWatchReporter(account: account, queue: queue, client: client, active: { active.active })
        let delivery = SimklPlaybackDelivery(), first = SimklPlaybackTracker(identity: .init(mediaID: "tt0123456"), reporter: reporter, delivery: delivery)
        let next = SimklPlaybackTracker(identity: .init(mediaID: "tt0765432"), reporter: reporter, delivery: delivery)
        first.sample(status: .playing, position: 950, duration: 1000)
        first.finish(position: 950, duration: 1000); next.sample(status: .playing, position: 10, duration: 1000)
        for _ in 0..<100 { if await held.requests.count == 1 { break }; try await Task.sleep(for: .milliseconds(10)) }
        await held.release(); await next.settled()
        let requests = await held.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/scrobble/start", "/scrobble/stop", "/sync/history", "/scrobble/start"])
        XCTAssertTrue(queue.document?.entries.isEmpty == true, "A confirmed history reply clears the terminal intent before the next session")
        let lastBody = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(requests.last?.httpBody)); XCTAssertEqual(lastBody["movie"]["ids"]["imdb"].string, "tt0765432")
        try queue.bind(account.session?.accessToken); _ = try queue.record(.init(mediaID: "tt0123456"))
        active.active = false; await reporter.recover()
        let afterRetirement = await held.requests; XCTAssertEqual(afterRetirement.count, 4); XCTAssertEqual(queue.document?.entries.count, 1)
    }
}
