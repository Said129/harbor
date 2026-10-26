import XCTest
@testable import Harbor

final class OwnedSimklClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}
actor OwnedSimklReplies {
    private var replies: [SimklReply]
    private(set) var requests: [(URLRequest, Date)] = []
    let clock: OwnedSimklClock
    init(_ replies: [SimklReply], clock: OwnedSimklClock) { self.replies = replies; self.clock = clock }
    func send(_ request: URLRequest) throws -> SimklReply {
        requests.append((request, clock.now()))
        guard !replies.isEmpty else { throw HarborError(code: "owned-unplanned-simkl-request") }; return replies.removeFirst()
    }
}
private actor OwnedSimklLease {
    var valid = true
    private(set) var started = false
    private var continuation: CheckedContinuation<SimklReply, Never>?
    func isValid() -> Bool { valid }
    func hold(_ request: URLRequest) async -> SimklReply {
        started = true; return await withCheckedContinuation { continuation = $0 }
    }
    func retire() { valid = false }
    func release() { continuation?.resume(returning: .init(status: 200, data: Data("{}".utf8))); continuation = nil }
}

final class SimklClientTests: XCTestCase {
    private struct Reference: Decodable {
        struct Case: Decodable {
            struct Expected: Decodable { let delayMs: Double; let cooldown: String? }
            let status, attempt: Int; let body: String; let retryAfter: String?; let now, random: Double; let expected: Expected
        }
        let actual_original_typescript_executed: Bool; let cases: [Case]
    }
    func testRetryDelaysAndAppVersusUserCooldownMatchTheExecutedDesktopPolicy() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "simkl-retry-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
        XCTAssertTrue(fixture.actual_original_typescript_executed); XCTAssertEqual(fixture.cases.count, 28)
        for item in fixture.cases {
            let policy = SimklRetryPolicy.resolve(status: item.status, body: Data(item.body.utf8), retryAfter: item.retryAfter, attempt: item.attempt, now: Date(timeIntervalSince1970: item.now / 1_000), random: item.random)
            XCTAssertEqual(policy.delay, item.expected.delayMs / 1_000, accuracy: item.expected.delayMs > 1e12 ? 0.01 : 0.000001)
            XCTAssertEqual(policy.cooldown?.rawValue, item.expected.cooldown)
        }
    }
    func testActualSerializedRequestsRetryBurstsAndKeepSeparateGETAndPOSTSlotsWithoutCredentialsOnPublicCalls() async throws {
        let clock = OwnedSimklClock(), ok = SimklReply(status: 200, data: Data("{}".utf8))
        let replies = OwnedSimklReplies([.init(status: 429, data: Data("{}".utf8)), .init(status: 503, data: Data("{}".utf8), retryAfter: "2"), ok, ok, ok, ok, ok], clock: clock)
        let client = SimklClient(transport: { try await replies.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() }, random: { 0 })
        _ = try await client.response(.pin)
        _ = try await client.response(.settings, token: "owned-simkl-synthetic-token")
        _ = try await client.response(.settings, token: "owned-simkl-synthetic-token")
        _ = try await client.response(.anime(7)); _ = try await client.response(.pin)
        let sent = await replies.requests; XCTAssertEqual(sent.count, 7)
        var last: [String: Date] = [:]
        for (request, at) in sent {
            let method = try XCTUnwrap(request.httpMethod)
            if let previous = last[method] { XCTAssertGreaterThanOrEqual(at.timeIntervalSince(previous), method == "GET" ? 0.109 : 1.049) }
            last[method] = at
            XCTAssertFalse(request.url!.absoluteString.contains("owned-simkl-synthetic-token"))
            if method == "GET" { XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")) }
            else { XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer owned-simkl-synthetic-token") }
        }
        XCTAssertGreaterThanOrEqual(sent[2].1.timeIntervalSince(sent[0].1), 3)
    }
    func testUserQuotaBlocksOnlyThatSessionWhileAnAppQuotaAndClient412StopEveryQueuedCaller() async throws {
        let clock = OwnedSimklClock(), ok = SimklReply(status: 200, data: Data("{}".utf8))
        let replies = OwnedSimklReplies([.init(status: 429, data: Data(#"{"error":"user_limit_exceeded"}"#.utf8)), ok, ok], clock: clock)
        let client = SimklClient(transport: { try await replies.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() }, random: { 0 })
        for _ in 0..<2 {
            do { _ = try await client.response(.settings, token: "owned-a"); XCTFail("User quota must remain closed") }
            catch let error as SimklAPIError { XCTAssertEqual(error.status, 429); XCTAssertNotNil(error.retryAt) }
        }
        _ = try await client.response(.pin); _ = try await client.response(.settings, token: "owned-b")
        let sent = await replies.requests; XCTAssertEqual(sent.count, 3)
        for status in [412, 429] {
            let blocked = OwnedSimklReplies([.init(status: status, data: Data(#"{"error":"app_limit_exceeded"}"#.utf8))], clock: clock)
            let shared = SimklClient(transport: { try await blocked.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
            for _ in 0..<2 {
                do { _ = try await shared.response(.pin); XCTFail("App cooldown must stop further network requests") }
                catch let error as SimklAPIError { XCTAssertEqual(error.status, status); XCTAssertNotNil(error.retryAt) }
            }
            let calls = await blocked.requests; XCTAssertEqual(calls.count, 1)
        }
    }
    func testAChangedProfileCannotSendAQueuedRequestOrPublishItsAlreadyInFlightReply() async throws {
        let lease = OwnedSimklLease(), clock = OwnedSimklClock()
        let client = SimklClient(transport: { await lease.hold($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
        do { _ = try await client.response(.settings, token: "owned-token", current: { false }); XCTFail("Retired profile sent a request") }
        catch is CancellationError { }
        let notStarted = await lease.started; XCTAssertFalse(notStarted)
        let task = Task { try await client.response(.settings, token: "owned-token", current: { await lease.isValid() }) }
        for _ in 0..<100 { if await lease.started { break }; try await Task.sleep(for: .milliseconds(10)) }
        let started = await lease.started; XCTAssertTrue(started)
        await lease.retire(); await lease.release()
        do { _ = try await task.value; XCTFail("Late reply was published after the profile changed") } catch is CancellationError { }
    }
}
