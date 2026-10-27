import XCTest
@testable import Harbor

@MainActor final class OwnedTraktPersistence: TraktAccountPersistence {
    var values: [String: TraktSession] = [:]
    var failRead = false, failWrite = false
    func read(owner: String) throws -> TraktSession? { if failRead { throw HarborError(code: "owned-read") }; return values[owner] }
    func write(_ session: TraktSession?, owner: String) throws { if failWrite { throw HarborError(code: "owned-write") }; values[owner] = session }
}
final class OwnedTraktClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 1_700_000_000)
    private var polls: [Double] = []
    func now() -> Date { lock.withLock { time } }
    func advance(_ seconds: Double) { lock.withLock { time.addTimeInterval(seconds) } }
    func poll(_ seconds: Double) { lock.withLock { time.addTimeInterval(seconds); polls.append(seconds) } }
    var pollDelays: [Double] { lock.withLock { polls } }
}
actor OwnedTraktTransport {
    private var replies: [TraktReply]
    private let fallback: @Sendable (URLRequest) throws -> TraktReply
    private(set) var requests: [URLRequest] = []
    private var holdPath: String?
    private var held: CheckedContinuation<Void, Never>?
    init(_ replies: [TraktReply] = [], fallback: @escaping @Sendable (URLRequest) throws -> TraktReply = { _ in .init(status: 503, data: Data()) }) { self.replies = replies; self.fallback = fallback }
    func send(_ request: URLRequest) async throws -> TraktReply {
        requests.append(request)
        let reply: TraktReply
        if replies.isEmpty { reply = try fallback(request) } else { reply = replies.removeFirst() }
        if request.url?.path == holdPath { holdPath = nil; await withCheckedContinuation { held = $0 } }
        return reply
    }
    func hold(_ path: String) { holdPath = path }
    var isHolding: Bool { held != nil }
    func release() { holdPath = nil; held?.resume(); held = nil }
}
@MainActor final class OwnedTraktScope { var active = true, enabled = true }

@MainActor final class TraktAccountTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "trakt-account-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(value["provider_network_requests"].integer, 0); return value
    }
    private func canonical(_ value: JSONValue) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
    private func reply(_ status: Int = 200, _ value: JSONValue = .null, retryAfter: String? = nil) throws -> TraktReply { .init(status: status, data: try JSONEncoder().encode(value), retryAfter: retryAfter) }
    private func session(_ suffix: String = "old") -> TraktSession { .init(accessToken: "owned-access-" + suffix, refreshToken: "owned-refresh-" + suffix, createdAt: 1_700_000_000, expiresIn: 7_776_000, username: "Owned Trakt") }
    private func grant(_ suffix: String = "new") -> JSONValue { .object(["access_token": .string("owned-access-" + suffix), "refresh_token": .string("owned-refresh-" + suffix), "created_at": .integer(1_700_000_100), "expires_in": .integer(7_776_000)]) }
    private func account(_ owner: String, memory: OwnedTraktPersistence? = nil) throws -> TraktAccountStore {
        let account = TraktAccountStore(owner: owner, persistence: memory ?? OwnedTraktPersistence()); try account.load(); try account.set(session()); return account
    }
    private func client(_ transport: OwnedTraktTransport, _ clock: OwnedTraktClock = .init()) -> TraktClient { .init(transport: { try await transport.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() }) }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-trakt-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    func testExecutedDesktopPlaybackCasesPreserveEveryProviderFieldCoordinateAndTruePercent() throws {
        let rows = try fixture()["cases"].array; XCTAssertEqual(rows.count, 28)
        for row in rows where row["expectedError"] != .bool(true) && row["noSession"] != .bool(true) {
            let records = TraktPlaybackImport.items(row["raw"])
            let actual = records.map { record -> JSONValue in var fields = record.raw.objectValue; fields.removeValue(forKey: "remotePct"); return .object(fields) }
            XCTAssertEqual(try canonical(.array(actual)), row["expected"], row["name"].string ?? "")
            for record in records {
                let point = try XCTUnwrap(TraktPlaybackImport.checkpoint(record))
                XCTAssertEqual(point.1.pct, record.progress); XCTAssertEqual(point.1.source, "trakt")
                XCTAssertEqual(point.0.season, record.playbackCoordinates.season); XCTAssertEqual(point.0.episode, record.playbackCoordinates.episode)
            }
        }
    }
    func testNativeEndpointRequestsPreserveDesktopProtocolAndNeverForwardBearerTokensToTheProxy() throws {
        let code = try TraktEndpoint.deviceCode.request(token: "owned-not-for-public-code")
        XCTAssertEqual(code.url?.absoluteString, "https://api.trakt.tv/oauth/device/code"); XCTAssertEqual(code.httpMethod, "POST"); XCTAssertNil(code.value(forHTTPHeaderField: "Authorization"))
        let body = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(code.httpBody)); XCTAssertEqual(body["client_id"].string, TraktConfiguration.clientID)
        for endpoint in [TraktEndpoint.poll("owned-device"), .refresh("owned-refresh")] {
            let request = try endpoint.request(token: "owned-access")
            XCTAssertEqual(request.url?.host, "harborcommunity.site"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertFalse(String(data: request.httpBody ?? Data(), encoding: .utf8)!.contains("owned-access"))
        }
        let playback = try TraktEndpoint.playback.request(token: "owned-access")
        XCTAssertEqual(playback.url?.absoluteString, "https://api.trakt.tv/sync/playback?limit=40"); XCTAssertEqual(playback.value(forHTTPHeaderField: "Authorization"), "Bearer owned-access")
        XCTAssertEqual(playback.value(forHTTPHeaderField: "trakt-api-key"), TraktConfiguration.clientID)
        XCTAssertThrowsError(try TraktEndpoint.playback.request()); XCTAssertThrowsError(try TraktEndpoint.refresh("bad\nsecret").request())
        let pin = try TraktPin(.object(["device_code": .string("owned-device"), "user_code": .string("OWNED-123"), "expires_in": .integer(30), "interval": .integer(2), "verification_url": .string("https://untrusted.invalid")]))
        XCTAssertEqual(pin.verificationURL.absoluteString, "https://trakt.tv/activate")
        XCTAssertEqual(TraktReply(status: 429, data: Data(), retryAfter: "999").retryDelay, 30)
        XCTAssertEqual(TraktReply(status: 429, data: Data(), retryAfter: "NaN").retryDelay, 1)
    }
    func testAccountPersistenceCommitsBeforePublishingAndNeverClearsAnotherProfile() throws {
        let memory = OwnedTraktPersistence(), a = try account("a", memory: memory), b = try account("b", memory: memory), identity = a.identity
        memory.failWrite = true; XCTAssertThrowsError(try a.set(nil)); XCTAssertEqual(a.session, session()); XCTAssertEqual(a.identity, identity)
        memory.failRead = true; XCTAssertThrowsError(try a.load()); XCTAssertEqual(a.session, session())
        memory.failRead = false; memory.failWrite = false; try a.set(nil)
        XCTAssertNil(a.session); XCTAssertNil(memory.values["a"]); XCTAssertEqual(b.session, session()); XCTAssertEqual(memory.values["b"], session())
        let owner = "owned-keychain-trakt-" + UUID().uuidString, durable = TraktAccountStore(owner: owner)
        try durable.load(); XCTAssertNil(durable.session); try durable.set(session())
        defer { try? durable.set(nil) }
        let reopened = TraktAccountStore(owner: owner); try reopened.load(); XCTAssertEqual(reopened.session, session())
        let other = TraktAccountStore(owner: owner + "-other"); try other.load(); XCTAssertNil(other.session)
    }
    func testExecutedDesktopAuthorizationPollsPreserveStatusesIntervalsAndOptionalUsername() async throws {
        let rows = try fixture()["authCases"].array; XCTAssertEqual(rows.count, 7)
        for row in rows where row["cancel"] != .bool(true) {
            let clock = OwnedTraktClock(), memory = OwnedTraktPersistence(), store = TraktAccountStore(owner: "owned-auth", persistence: memory)
            try store.load()
            let pin: JSONValue = .object(["device_code": .string("owned-device"), "user_code": .string("OWNED-123"), "expires_in": .integer(30), "interval": .integer(2)])
            var replies = [try reply(200, pin)]
            let originalGrant: JSONValue = .object(["access_token": .string("owned-access"), "refresh_token": .string("owned-refresh"), "created_at": .integer(1_700_000_000), "expires_in": .integer(7_776_000)])
            for status in row["polls"].array.compactMap(\.integer) { replies.append(try reply(status, status == 200 ? originalGrant : .null)) }
            if row["polls"].array.contains(.integer(200)) { replies.append(try reply(row["userStatus"].integer ?? 200, .object(["username": .string("Owned Trakt")]))) }
            let transport = OwnedTraktTransport(replies), model = TraktAccountModel(store: store, client: client(transport, clock), active: { true }, sleep: { clock.poll($0) }, now: { clock.now() })
            await model.begin()
            let requests = await transport.requests, original = row["expected"]["requests"].array
            XCTAssertEqual(requests.map { $0.url?.path }, original.map { URL(string: $0["url"].string!)?.path })
            XCTAssertEqual(requests.map(\.httpMethod), original.map { $0["method"].string })
            for (request, expected) in zip(requests, original) {
                let body = try request.httpBody.map { try JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
                XCTAssertEqual(try canonical(body), expected["body"])
                for (key, value) in expected["headers"].objectValue { XCTAssertEqual(request.value(forHTTPHeaderField: key), value.string) }
            }
            XCTAssertEqual(clock.pollDelays.map { Int($0 * 1_000) }, row["expected"]["delays"].array.compactMap(\.integer))
            XCTAssertEqual(store.session == nil, row["expected"]["session"] == .null, row["name"].string ?? "")
            XCTAssertEqual(store.session?.username, row["expected"]["session"]["username"].string)
            if let session = store.session {
                let expected = row["expected"]["session"]
                XCTAssertEqual(session.accessToken, expected["accessToken"].string)
                XCTAssertEqual(session.refreshToken, expected["refreshToken"].string)
                XCTAssertEqual(session.createdAt, expected["createdAt"].numericValue)
                XCTAssertEqual(session.expiresIn, expected["expiresIn"].numericValue)
                XCTAssertEqual(memory.values[store.owner], session)
            }
            XCTAssertFalse(model.busy); XCTAssertNil(model.pin)
            if store.session != nil { XCTAssertNil(model.error) } else { XCTAssertNotNil(model.error) }
        }
    }
    func testConcurrentUnauthorizedRequestsShareOneRefreshAnd429RetriesStayBounded() async throws {
        let memory = OwnedTraktPersistence(), store = try account("owned-refresh", memory: memory), grant = grant()
        let transport = OwnedTraktTransport(fallback: { request in
            if request.url?.path == "/api/trakt/token" { return .init(status: 200, data: try JSONEncoder().encode(grant)) }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer owned-access-old" { return .init(status: 401, data: Data()) }
            return .init(status: 200, data: Data("[]".utf8))
        })
        let client = client(transport)
        async let first = store.response(.playback, client: client, active: { true })
        async let second = store.response(.me, client: client, active: { true })
        _ = try await (first, second)
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/trakt/token" }.count, 1)
        XCTAssertEqual(store.session?.accessToken, "owned-access-new"); XCTAssertEqual(memory.values[store.owner], store.session)
        let clock = OwnedTraktClock(), retry = OwnedTraktTransport([try reply(429, retryAfter: "999"), try reply(200, .array([]))])
        let value = try await store.response(.playback, client: self.client(retry, clock), active: { true })
        XCTAssertEqual(value, .array([])); XCTAssertEqual(clock.now().timeIntervalSince1970, 1_700_000_030)
    }
    func testHeldRefreshPersistsOnlyItsStillOwnedAccountAndNeverRestoresADisconnectedSession() async throws {
        for mode in ["leave", "disconnect", "replace"] {
            let memory = OwnedTraktPersistence(), store = try account("owned-held-" + mode, memory: memory), scope = OwnedTraktScope()
            let transport = OwnedTraktTransport([try reply(401), try reply(200, grant())]); await transport.hold("/api/trakt/token")
            let client = client(transport), operation = Task { try await store.response(.playback, client: client, active: { scope.active }) }
            for _ in 0..<200 { if await transport.isHolding { break }; try await Task.sleep(for: .milliseconds(5)) }
            let held = await transport.isHolding; XCTAssertTrue(held)
            if mode == "leave" { scope.active = false }
            else { try store.set(mode == "disconnect" ? nil : session("other")) }
            await transport.release()
            do { _ = try await operation.value; XCTFail("A retired request must not publish") } catch is CancellationError { }
            XCTAssertEqual(store.session?.accessToken, mode == "leave" ? "owned-access-new" : mode == "replace" ? "owned-access-other" : nil)
            XCTAssertEqual(memory.values[store.owner], store.session); XCTAssertNil(memory.values[store.owner + "-other"])
        }
        let store = try account("owned-refresh-failure"), transport = OwnedTraktTransport([try reply(401), try reply(503)])
        do { _ = try await store.response(.playback, client: client(transport), active: { true }); XCTFail("Provider failure") } catch { }
        XCTAssertEqual(store.session, session(), "A transient renewal failure must not delete the durable account")
    }
    func testCancelledAuthorizationAndChangedProfileCannotPublishAnInFlightGrant() async throws {
        for changeProfile in [false, true] {
            let store = TraktAccountStore(owner: "owned-cancel", persistence: OwnedTraktPersistence()); try store.load()
            let pin: JSONValue = .object(["device_code": .string("owned-device"), "user_code": .string("OWNED-123"), "expires_in": .integer(30), "interval": .integer(2)])
            let transport = OwnedTraktTransport([try reply(200, pin), try reply(200, grant())]); await transport.hold("/api/trakt/device-token")
            let scope = OwnedTraktScope(), model = TraktAccountModel(store: store, client: client(transport), active: { scope.active })
            let operation = Task { await model.begin() }
            for _ in 0..<200 { if await transport.isHolding { break }; try await Task.sleep(for: .milliseconds(5)) }
            let held = await transport.isHolding; XCTAssertTrue(held)
            if changeProfile { scope.active = false } else { model.cancel() }
            await transport.release(); await operation.value
            XCTAssertNil(store.session); XCTAssertNil(model.error)
        }
    }
    func testPlaybackTTLFailuresTrueRuntimeAndProfileSourceGatesUseActualStores() async throws {
        let raw = try fixture()["cases"].array[3]["raw"], clock = OwnedTraktClock(), scope = OwnedTraktScope(), store = try account("owned-feed")
        let transport = OwnedTraktTransport([try reply(200, raw), try reply(503), try reply(503), try reply(503), try reply(503), try reply(200, raw)])
        let feed = TraktPlaybackFeed(client: client(transport, clock), now: { clock.now() }, sleep: { clock.poll($0) })
        feed.bind(account: store, scope: "one", active: { scope.active }, enabled: { scope.enabled })
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let shared = ResumeStore(fileURL: root.appendingPathComponent("shared.json")), personal = ResumeStore(fileURL: root.appendingPathComponent("personal.json"))
        try await shared.load(); try await personal.load(); await feed.refresh(resume: shared)
        XCTAssertEqual(feed.records.count, 1)
        let target = try XCTUnwrap(TraktPlaybackImport.checkpoint(feed.records[0])).0
        let point = try await shared.position(target, durationMs: 1_800_000), privatePoint = try await personal.entry(target)
        XCTAssertEqual(point.ms, 900_000); XCTAssertNil(privatePoint)
        await feed.refresh(); let firstCount = await transport.requests.count; XCTAssertEqual(firstCount, 1)
        clock.advance(31); await feed.refresh(focused: true); XCTAssertEqual(feed.records.count, 1); XCTAssertEqual(clock.pollDelays, [1, 4, 10])
        await feed.refresh(); let retryCount = await transport.requests.count; XCTAssertEqual(retryCount, 6)
        scope.enabled = false; XCTAssertTrue(feed.records.isEmpty); scope.enabled = true
        try store.set(nil); XCTAssertTrue(feed.records.isEmpty)
        feed.bind(account: store, scope: "two", active: { true }, enabled: { true }); await feed.refresh(force: true)
        let disconnectedCount = await transport.requests.count; XCTAssertEqual(disconnectedCount, 6)
    }
    func testProductionLibraryMergesTraktWithoutCreatingBookmarksAndKeepsPrivateHistorySeparate() async throws {
        let raw = try fixture()["cases"].array[3]["raw"], scope = OwnedTraktScope(), owner = "owned-trakt-library-" + UUID().uuidString, account = try account(owner)
        let transport = OwnedTraktTransport([try reply(200, raw)]), feed = TraktPlaybackFeed(client: client(transport))
        feed.bind(account: account, scope: owner, active: { scope.active }, enabled: { scope.enabled })
        let model = LibraryModel(traktPlayback: feed); await model.setSession(nil, personalOwner: owner, guestOwner: owner, synchronize: false)
        var sources = ContinueWatchingSources(); sources.trakt = true; model.setContinueSources(sources)
        await feed.refresh(); XCTAssertTrue(model.items.isEmpty); XCTAssertEqual(model.continuing.count, 1)
        let record = try XCTUnwrap(model.continuing.first), target = try XCTUnwrap(TraktPlaybackImport.checkpoint(record)).0
        let point = await model.resume(for: target, refresh: false); XCTAssertEqual(point?.entry.pct, 0.5); XCTAssertEqual(point?.entry.source, "trakt")
        model.hideContinuing(record, owner: owner); XCTAssertTrue(model.continuing.isEmpty); model.showContinuing(record)
        XCTAssertEqual(model.continuing.count, 1)
        model.setContinuePrivacy(true); XCTAssertTrue(model.continuing.isEmpty)
        let privatePoint = await model.resume(for: target, refresh: false); XCTAssertNil(privatePoint)
        model.setContinuePrivacy(false); XCTAssertEqual(model.continuing.count, 1)
        sources.trakt = false; model.setContinueSources(sources); XCTAssertTrue(model.continuing.isEmpty)
        await model.setSession(nil, personalOwner: owner + "-other", guestOwner: owner + "-other", synchronize: false)
        sources.trakt = true; model.setContinueSources(sources); XCTAssertTrue(model.continuing.isEmpty)
    }
}
