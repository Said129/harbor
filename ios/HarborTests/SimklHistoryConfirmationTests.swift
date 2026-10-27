import XCTest
@testable import Harbor

private actor OwnedHistoryResolutionHold {
    private(set) var started = false
    private var continuation: CheckedContinuation<TrackerResolutionResult, Never>?
    func resolve() async -> TrackerResolutionResult { started = true; return await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(returning: .found(.init(showIds: .init(.object(["trakt": .integer(42)])), season: 3, number: 2))); continuation = nil }
}
@MainActor private final class OwnedHistoryLease { var active = true }
@MainActor final class SimklHistoryConfirmationTests: XCTestCase {
    func testSevenHistoryReceiptsMatchTheActuallyExecutedDesktopConfirmationInsteadOfTreatingEmptyJSONAsSuccess() throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "tracker-episode-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(fixture["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(fixture["receipts"].array.count, 7)
        for row in fixture["receipts"].array {
            XCTAssertEqual(.bool(SimklHistoryReceipt.confirms(body: row["body"], response: row["response"])), row["expected"])
        }
    }
    func testRejectedTVHistoryUsesTheSharedResolverThenClearsOnlyAConfirmedWriteAndNeverResolvesAnimeOrAcceptedHistory() async throws {
        let resolved = TrackerResolutionResult.found(.init(showIds: .init(.object(["trakt": .integer(42), "imdb": .string("tt0765432")])), season: 3, number: 2))
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "tracker-episode-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        for mode in ["resolved", "still-rejected", "unresolved", "accepted", "anime"] {
            let catalog = OwnedTrackerCatalog(try XCTUnwrap(fixture["hydrationCases"].array.first))
            let resolver = TrackerEpisodeResolver(response: { try await catalog.send($0) }, cacheURL: nil)
            let account = SimklAccountStore(owner: "owned-history-" + mode, persistence: OwnedSimklLibraryAccount()); try account.load()
            let queue = SimklPendingWatches(owner: account.owner, persistence: OwnedSimklPendingMemory()), clock = OwnedSimklClock()
            let episode = Episode(id: "owned-video", season: 1, episode: 7)
            let identity = SimklWatchIdentity(mediaID: mode == "anime" ? "kitsu:123" : "tt0123456", episode: episode, imdb: mode == "anime" ? "tt0123456" : nil)
            let primary = mode == "accepted" ? "{\"added\":{\"episodes\":1}}" : "{}"
            let fallback = mode == "resolved" ? "{\"added\":{\"episodes\":1}}" : "{}"
            let replies = OwnedSimklReplies([.init(status: 200, data: Data("{}".utf8)), .init(status: 200, data: Data(primary.utf8)), .init(status: 200, data: Data(fallback.utf8))], clock: clock)
            let client = SimklClient(transport: { try await replies.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
            let reporter = SimklWatchReporter(account: account, queue: queue, client: client, active: { true }, resolve: { id, season, number in
                XCTAssertFalse(["accepted", "anime"].contains(mode)); XCTAssertEqual(id, "tt0123456"); XCTAssertEqual(season, 1); XCTAssertEqual(number, 7)
                if mode == "resolved" { return await resolver.resolve(metaID: id, season: season, number: number) }
                return mode == "unresolved" ? .notFound : resolved
            })
            await reporter.send(.init(action: .stop, progress: 100, recordWatched: true), identity: identity)
            let requests = await replies.requests
            let needsFallback = ["resolved", "still-rejected"].contains(mode)
            XCTAssertEqual(requests.count, needsFallback ? 3 : 2, mode)
            XCTAssertEqual(queue.document?.entries.isEmpty, ["accepted", "resolved"].contains(mode), mode)
            if needsFallback {
                let first = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(requests[1].0.httpBody))
                let second = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(requests[2].0.httpBody))
                XCTAssertEqual(first["shows"].array.first?["seasons"].array.first?["number"].integer, 1)
                XCTAssertEqual(second["shows"].array.first?["ids"]["trakt"].integer, mode == "resolved" ? 1 : 42)
                XCTAssertEqual(second["shows"].array.first?["seasons"].array.first?["number"].integer, 3)
                XCTAssertEqual(second["shows"].array.first?["seasons"].array.first?["episodes"].array.first?["number"].integer, 2)
            }
            let metadataRequests = await catalog.requests
            XCTAssertEqual(metadataRequests.count, mode == "resolved" ? 3 : 0, "The accepted fallback traverses the real Cinemeta/catalog resolver")
        }
    }
    func testAProfileRetiredDuringMetadataResolutionCannotWriteItsLateEpisodeToTheNextAccount() async throws {
        let account = SimklAccountStore(owner: "owned-retired-history", persistence: OwnedSimklLibraryAccount()); try account.load()
        let queue = SimklPendingWatches(owner: account.owner, persistence: OwnedSimklPendingMemory()), clock = OwnedSimklClock()
        let replies = OwnedSimklReplies(Array(repeating: .init(status: 200, data: Data("{}".utf8)), count: 3), clock: clock)
        let held = OwnedHistoryResolutionHold(), lease = OwnedHistoryLease()
        let client = SimklClient(transport: { try await replies.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
        let reporter = SimklWatchReporter(account: account, queue: queue, client: client, active: { lease.active }, resolve: { _, _, _ in await held.resolve() })
        let task = Task { await reporter.send(.init(action: .stop, progress: 100, recordWatched: true), identity: .init(mediaID: "tt0123456", episode: .init(id: "owned", season: 1, episode: 7))) }
        for _ in 0..<100 { if await held.started { break }; try await Task.sleep(for: .milliseconds(10)) }
        let started = await held.started; XCTAssertTrue(started)
        lease.active = false; await held.release(); await task.value
        let requests = await replies.requests; XCTAssertEqual(requests.count, 2); XCTAssertEqual(queue.document?.entries.count, 1)
    }
}
