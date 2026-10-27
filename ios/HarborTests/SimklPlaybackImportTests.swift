import XCTest
@testable import Harbor

private actor OwnedPlaybackImportTransport {
    private(set) var requests: [URLRequest] = []
    private var replies: [SimklReply]
    private var held: CheckedContinuation<SimklReply, Never>?
    private var shouldHold = false
    init(_ replies: [SimklReply]) { self.replies = replies }
    func send(_ request: URLRequest) async -> SimklReply {
        requests.append(request)
        if shouldHold { shouldHold = false; return await withCheckedContinuation { held = $0 } }
        return replies.isEmpty ? .init(status: 400, data: Data("{}".utf8)) : replies.removeFirst()
    }
    func append(_ reply: SimklReply) { replies.append(reply) }
    func holdNext() { shouldHold = true }
    func release(_ reply: SimklReply) { held?.resume(returning: reply); held = nil }
}
@MainActor private final class OwnedPlaybackImportScope { var active = true; var enabled = true }
private actor OwnedPlaybackImportSleeps {
    private(set) var values: [Double] = []
    func add(_ value: Double) { values.append(value) }
}
@MainActor final class SimklPlaybackImportTests: XCTestCase {
    private func cases() throws -> [JSONValue] {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "simkl-playback-import-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(fixture["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(fixture["provider_network_requests"].integer, 0)
        XCTAssertEqual(fixture["cases"].array.count, 26); return fixture["cases"].array
    }
    private func dictionary(_ raw: JSONValue) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(raw)) as? NSDictionary)
    }
    private func reply(_ value: JSONValue) throws -> SimklReply { .init(status: 200, data: try JSONEncoder().encode(value)) }
    private func account(_ owner: String) throws -> SimklAccountStore {
        let account = SimklAccountStore(owner: owner, persistence: OwnedSimklLibraryAccount()); try account.load(); return account
    }
    func testTwentySixExecutedDesktopImportsKeepIdentityCoordinatesDeduplicationAndProgressFields() throws {
        for row in try cases() where row["expectedError"] != .bool(true) {
            let imported = SimklPlaybackImport.items(row["raw"])
            XCTAssertEqual(imported.count, row["expected"].array.count, row["name"].string ?? "")
            for (actual, expected) in zip(imported, row["expected"].array) {
                var fields = actual.raw.objectValue; fields.removeValue(forKey: "remotePct")
                XCTAssertEqual(try dictionary(.object(fields)), try dictionary(expected), row["name"].string ?? "")
                XCTAssertNotNil(SimklPlaybackImport.checkpoint(actual))
            }
        }
    }
    func testExecutedDesktopBackfillsKeepDismissedCardsAndNewerLocalProgressUntouched() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-playback-oracle-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for row in try cases() where row["expectedError"] != .bool(true) {
            let name = try XCTUnwrap(row["name"].string), store = ResumeStore(fileURL: root.appendingPathComponent(name + ".json"))
            try await store.load()
            let records = SimklPlaybackImport.items(row["raw"])
            for record in records {
                let (target, entry) = try XCTUnwrap(SimklPlaybackImport.checkpoint(record))
                var existing: ResumeEntry?
                if row["existing"] != .null {
                    existing = try row["existing"].decoded(ResumeEntry.self)
                    try await store.importRemote(target, entry: XCTUnwrap(existing), current: { true })
                }
                let written: Bool
                if row["dismissed"] == .bool(true) { written = false }
                else { written = try await store.importRemote(target, entry: entry, current: { true }) }
                let expected = row["writes"].array.first { value in
                    value["id"].string == record.id && value["season"].integer == target.season && value["episode"].integer == target.episode
                }
                XCTAssertEqual(written, expected != nil, name)
                let saved = try await store.entry(target)
                if let expected {
                    XCTAssertEqual(saved?.ms, expected["ms"].numericValue, name); XCTAssertEqual(saved?.pct, expected["pct"].numericValue, name)
                    XCTAssertEqual(saved?.t, expected["t"].numericValue.map(UInt64.init), name); XCTAssertEqual(saved?.source, "simkl")
                } else { XCTAssertEqual(saved, existing, name) }
            }
        }
    }
    func testRealPrivateResumeDocumentReopensTruePercentUsesRuntimeAndHonorsStartOver() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-playback-resume-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("resume.json"), store = ResumeStore(fileURL: file)
        let record = try XCTUnwrap(SimklPlaybackImport.items(try cases()[5]["raw"]).first)
        let (target, entry) = try XCTUnwrap(SimklPlaybackImport.checkpoint(record)); try await store.load()
        try await store.importRemote(target, entry: entry, current: { true })
        let reopened = ResumeStore(fileURL: file); try await reopened.load()
        let restored = try await reopened.entry(target); XCTAssertEqual(restored, entry)
        let start = try await reopened.position(target, durationMs: 1_440_000, prompt: true)
        XCTAssertEqual(start.ms, 720_000); XCTAssertTrue(start.prompt)
        try await reopened.restart(target, timestampMs: entry.t + 1)
        let rejected = try await reopened.importRemote(target, entry: entry, current: { true }); XCTAssertFalse(rejected)
        let reset = try await reopened.entry(target); XCTAssertEqual(reset?.ms, 0); XCTAssertNil(reset?.pct); XCTAssertNil(reset?.source)
        do { try await reopened.importRemote(target, entry: entry, current: { false }); XCTFail("A retired profile imported a late pause") } catch is CancellationError { }
    }
    func testFeedCoalescesAndUsesThirtySecondFocusAndFiveMinuteCacheThenRetainsOfflineCardsThroughThreeRetries() async throws {
        let raw = try cases()[0]["raw"], clock = OwnedSimklClock(), sleeps = OwnedPlaybackImportSleeps()
        let transport = OwnedPlaybackImportTransport([try reply(raw), try reply(raw), try reply(raw)])
        let client = SimklClient(transport: { await transport.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
        let feed = SimklPlaybackFeed(client: client, now: { clock.now() }, sleep: { value in await sleeps.add(value); clock.advance(value) })
        let account = try account("owned-feed-ttl")
        feed.bind(account: account, scope: "owned", active: { true }, enabled: { true })
        async let one: Void = feed.refresh(); async let two: Void = feed.refresh(); _ = await (one, two)
        var requests = await transport.requests; XCTAssertEqual(requests.count, 1); XCTAssertEqual(feed.records.count, 1)
        clock.advance(29); await feed.refresh(focused: true); requests = await transport.requests; XCTAssertEqual(requests.count, 1)
        clock.advance(1); await feed.refresh(focused: true); requests = await transport.requests; XCTAssertEqual(requests.count, 2)
        clock.advance(299); await feed.refresh(); requests = await transport.requests; XCTAssertEqual(requests.count, 2)
        clock.advance(1); await feed.refresh(); requests = await transport.requests; XCTAssertEqual(requests.count, 3)
        await feed.refresh(force: true); requests = await transport.requests; XCTAssertEqual(requests.count, 7)
        let delays = await sleeps.values; XCTAssertEqual(delays, [1, 4, 10]); XCTAssertEqual(feed.records.count, 1)
        XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/sync/playback" && $0.httpMethod == "GET" && $0.httpBody == nil })
        let url = try XCTUnwrap(URLComponents(url: XCTUnwrap(requests.first?.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.queryItems?.first { $0.name == "hide_watched" }?.value, "true"); XCTAssertEqual(url.queryItems?.first { $0.name == "limit" }?.value, "40")
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer " + account.session!.accessToken })
        await transport.append(try reply(raw)); await feed.refresh()
        requests = await transport.requests; XCTAssertEqual(requests.count, 8, "A failed refresh must not receive a successful cache TTL")
    }
    func testSourceAccountAndProfileChangesImmediatelyHideCardsAndRejectTheActualHeldReply() async throws {
        let raw = try cases()[0]["raw"], clock = OwnedSimklClock(), state = OwnedPlaybackImportScope()
        let transport = OwnedPlaybackImportTransport([try reply(raw)])
        let client = SimklClient(transport: { await transport.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
        let feed = SimklPlaybackFeed(client: client), account = try account("owned-feed-retirement")
        feed.bind(account: account, scope: "one", active: { state.active }, enabled: { state.enabled })
        await feed.refresh(); XCTAssertEqual(feed.records.count, 1)
        state.enabled = false; XCTAssertTrue(feed.records.isEmpty)
        feed.bind(account: account, scope: "one", active: { state.active }, enabled: { state.enabled })
        state.enabled = true; XCTAssertTrue(feed.records.isEmpty)
        await transport.holdNext(); let pending = Task { await feed.refresh(force: true) }
        for _ in 0..<100 { if await transport.requests.count == 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
        try account.set(.init(accessToken: "owned-replaced-token"))
        XCTAssertTrue(feed.records.isEmpty); await transport.release(try reply(raw)); await pending.value; XCTAssertTrue(feed.records.isEmpty)
        feed.bind(account: account, scope: "two", active: { state.active }, enabled: { state.enabled })
        await transport.append(try reply(raw)); await feed.refresh(); XCTAssertEqual(feed.records.count, 1)
        state.active = false; XCTAssertTrue(feed.records.isEmpty)
        state.active = true; try account.set(nil); XCTAssertTrue(feed.records.isEmpty)
    }
    func testProductionLibraryMergesImportedCardsWithoutSavingThemInStremioAndDismissalSurvivesRefresh() async throws {
        let raw = try cases()[0]["raw"], clock = OwnedSimklClock(), owner = "owned-library-import-" + UUID().uuidString
        let transport = OwnedPlaybackImportTransport([try reply(raw), try reply(raw)])
        let client = SimklClient(transport: { await transport.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
        let feed = SimklPlaybackFeed(client: client), library = LibraryModel(simklPlayback: feed), account = try account(owner)
        var sources = ContinueWatchingSources(); sources.simkl = true; library.setContinueSources(sources)
        await library.setSession(nil, personalOwner: owner, guestOwner: owner, synchronize: false)
        feed.bind(account: account, scope: owner, active: { true }, enabled: { true })
        await feed.refresh(); let record = try XCTUnwrap(library.continuing.first)
        XCTAssertTrue(library.items.isEmpty, "Imported cards must never become Stremio bookmarks")
        XCTAssertEqual(record.raw["external"].string, "simkl")
        let resume = await library.resume(for: .init(id: record.id), refresh: false); XCTAssertEqual(resume?.entry.pct, 0.5)
        library.hideContinuing(record, owner: owner); XCTAssertTrue(library.continuing.isEmpty); XCTAssertEqual(library.hiddenContinuing.count, 1)
        await feed.refresh(force: true, dismissed: { library.isDismissed($0) }); XCTAssertTrue(library.continuing.isEmpty)
        library.showContinuing(record); XCTAssertEqual(library.continuing.count, 1)
        await library.setSession(nil, personalOwner: owner + "-other", guestOwner: owner + "-other", synchronize: false)
        XCTAssertTrue(library.continuing.isEmpty)
        let otherResume = await library.resume(for: .init(id: record.id), refresh: false); XCTAssertNil(otherResume)
    }
    func testDesktopSourceDefaultsAndDisabledAuthenticationKeepThePlaybackEndpointPrivate() throws {
        let defaults = ContinueWatchingSources(rawValue: ContinueWatchingSources.defaultValue)
        XCTAssertTrue(defaults.library); XCTAssertTrue(defaults.local); XCTAssertFalse(defaults.simkl); XCTAssertFalse(defaults.trakt)
        var edited = defaults; edited.simkl = true; XCTAssertEqual(ContinueWatchingSources(rawValue: edited.rawValue), edited)
        XCTAssertTrue(ProfileSettingsStore.keys.contains("cwSources"))
        XCTAssertThrowsError(try SimklEndpoint.playback.request()); XCTAssertThrowsError(try SimklEndpoint.playback.request(token: "invalid token"))
    }
}
