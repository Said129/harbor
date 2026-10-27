import XCTest
@testable import Harbor

private actor OwnedLibraryQueueService: LibraryServing {
    private var puts: [JSONValue], gets: [JSONValue]
    private var library: [JSONValue]
    private(set) var calls: [JSONValue] = []
    private var hold = false
    private var held: CheckedContinuation<Void, Never>?
    init(puts: [JSONValue] = [], gets: [JSONValue] = [], library: [JSONValue] = []) { self.puts = puts; self.gets = gets; self.library = library }
    func records(_ session: AccountSession) async throws -> [JSONValue] { library }
    func record(_ id: String, session: AccountSession) async throws -> JSONValue? {
        calls.append(.object(["method": .string("datastoreGet"), "body": .object(["authKey": .string(session.authKey), "collection": .string("libraryItem"), "ids": .array([.string(id)]), "all": .bool(false)])]))
        let response = gets.isEmpty ? JSONValue.object(["items": .array(library)]) : gets.removeFirst()
        if hold { hold = false; await withCheckedContinuation { held = $0 } }
        if response["error"] == .bool(true) { throw HarborError(code: "owned-transport-offline") }
        return response["items"].array.first { $0["_id"].string == id }
    }
    func save(_ record: JSONValue, session: AccountSession) async throws {
        calls.append(.object(["method": .string("datastorePut"), "body": .object(["authKey": .string(session.authKey), "collection": .string("libraryItem"), "changes": .array([record])])]))
        let response = puts.isEmpty ? JSONValue.null : puts.removeFirst()
        if response["error"] == .bool(true) { throw HarborError(code: "owned-transport-offline") }
        library.removeAll { $0["_id"] == record["_id"] }; library.append(record)
    }
    func holdNextRead() { hold = true }
    func isHolding() -> Bool { held != nil }
    func release() { hold = false; held?.resume(); held = nil }
    func appendFailure() { puts.append(.object(["error": .bool(true)])) }
    func replaceLibrary(_ records: [JSONValue]) { library = records }
}

@MainActor private final class OwnedDismissalRetryStore: ContinueDismissalPersistence {
    var failing = true
    func read() throws -> ContinueDismissalState? {
        if failing { throw HarborError(code: "owned-private-read") }
        var state = ContinueDismissalState(); state.migrations.insert("owned-retry"); return state
    }
    func write(_ value: ContinueDismissalState) throws { }
    func legacy(_ owner: String) throws -> [String: ContinueDismissal] { [:] }
}
private actor OwnedDismissalLease {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var released = false
    func wait() async -> Bool {
        if released { return true }
        return await withCheckedContinuation { continuation = $0 }
    }
    func isWaiting() -> Bool { continuation != nil }
    func release() { released = true; continuation?.resume(returning: true); continuation = nil }
}

@MainActor final class ContinueDismissalTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "continue-dismissal-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(value["provider_network_requests"].integer, 0)
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987"); return value
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("owned-dismissal-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    private func session(_ owner: String = "owned-queue") -> AccountSession {
        .init(authKey: "owned-fixture-credential", user: .init(id: owner, email: nil, fullname: "Owned"))
    }
    private func sorted(_ rows: [JSONValue]) -> [JSONValue] { rows.sorted { ($0["_id"].string ?? "") < ($1["_id"].string ?? "") } }

    func testElevenExecutedDesktopQueueHistoriesMatchActualRequestsAndProtectedReopenWithoutCredentials() async throws {
        let rows = try fixture()["queueCases"].array; XCTAssertEqual(rows.count, 11)
        for row in rows {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let service = OwnedLibraryQueueService(puts: row["puts"].array, gets: row["gets"].array)
            let queue = LibraryWriteQueue(service: service, directory: root), account = session()
            var outcomes: [JSONValue] = []
            for operation in row["operations"].array {
                if operation.array.first?.string == "put" { let sent = try await queue.put(operation.array[1], session: account); outcomes.append(.bool(sent)) }
                else { try await queue.flush(account); outcomes.append(.null) }
            }
            let pending = try await queue.pending(owner: account.user.id), calls = await service.calls
            let expected = row["expected"]["queue"].array.map { $0["item"] }
            XCTAssertEqual(outcomes, row["expected"]["results"].array, row["name"].string ?? "")
            XCTAssertEqual(sorted(pending), sorted(expected)); XCTAssertEqual(calls, row["expected"]["transport"].array)
            let reopened = LibraryWriteQueue(service: service, directory: root)
            let restored = try await reopened.pending(owner: account.user.id); XCTAssertEqual(sorted(restored), sorted(expected))
            for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains(account.authKey))
                let protection = try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey] as? FileProtectionType
                XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
            }
        }
    }
    func testTenExecutedDesktopDismissalsKeepPersonalAndOtherEpisodeResumesAndExactProviderFields() async throws {
        let fixture = try fixture(), rows = fixture["dismissals"].array; XCTAssertEqual(rows.count, 10)
        let now = try XCTUnwrap(fixture["now"].numericValue)
        for row in rows {
            let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
            let record = LibraryRecord(raw: row["item"])
            let action = ContinueDismissalAction(record, privateMode: row["privateMode"] == .bool(true) && row["solo"] != .bool(true), authenticated: row["auth"] == .bool(true), timestampMs: now)
            let shared = ResumeStore(fileURL: root.appendingPathComponent("shared.json")), personal = ResumeStore(fileURL: root.appendingPathComponent("personal.json"))
            try await shared.load(); try await personal.load()
            let checkpoint = ResumeSnapshot(positionMs: 400_000, durationMs: 1_000_000, timestampMs: UInt64(now - 1_000), exiting: true)
            let other = ResumeTarget(id: "owned-other", season: 0, episode: 8)
            for store in [shared, personal] { try await store.save(action.target, snapshot: checkpoint); try await store.save(other, snapshot: checkpoint) }
            if action.clearsResume { try await shared.clear(action.target, notNewerThan: now) }
            let held = try await shared.entry(action.target), privateHeld = try await personal.entry(action.target), otherHeld = try await shared.entry(other)
            XCTAssertEqual(held == nil, row["expected"]["sharedResume"].objectValue.isEmpty, row["name"].string ?? "")
            XCTAssertEqual(privateHeld?.ms, 400_000); XCTAssertEqual(otherHeld?.ms, 400_000)
            let service = OwnedLibraryQueueService(puts: row["puts"].array), queue = LibraryWriteQueue(service: service, directory: root.appendingPathComponent("queue"))
            if let cloud = action.cloudRecord { _ = try await queue.put(cloud, session: session()) }
            let calls = await service.calls, pending = try await queue.pending(owner: session().user.id)
            XCTAssertEqual(calls, row["expected"]["transport"].array)
            XCTAssertEqual(pending, row["expected"]["queue"].array.map { $0["item"] })
        }
    }
    func testHeldFlushCannotDropOrSendAnOlderSnapshotOverANewerQueuedChangeOrCrossAccounts() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let row = try fixture()["queueCases"].array[0], old = row["operations"].array[0].array[1]
        var fields = old.objectValue; fields["_mtime"] = .string(ContinueDismissalAction.iso(1_700_000_010_123)); let newer = JSONValue.object(fields)
        let service = OwnedLibraryQueueService(puts: [.object(["error": .bool(true)]), .object(["error": .bool(true)])])
        let queue = LibraryWriteQueue(service: service, directory: root), account = session()
        _ = try await queue.put(old, session: account); await service.holdNextRead()
        let flush = Task { try await queue.flush(account) }
        for _ in 0..<200 { if await service.isHolding() { break }; try await Task.sleep(for: .milliseconds(5)) }
        let held = await service.isHolding(); XCTAssertTrue(held)
        _ = try await queue.put(newer, session: account); await service.release(); _ = try await flush.value
        let pending = try await queue.pending(owner: account.user.id); XCTAssertEqual(pending, [newer])
        try await queue.flush(session("owned-other-account")); let calls = await service.calls
        XCTAssertEqual(calls.count, 3, "A stale flush and another account must not send the newer pending item")
        do { _ = try await queue.put(old, session: account, current: { false }); XCTFail("Retired lease") } catch is CancellationError { }
        let unchanged = try await queue.pending(owner: account.user.id); XCTAssertEqual(unchanged, [newer])
    }
    func testCorruptOrUnwritableQueuePreservesThePreviousFileAndDoesNotClaimDurability() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try fixture()["queueCases"].array[0]["operations"].array[0].array[1]
        let service = OwnedLibraryQueueService(puts: [.object(["error": .bool(true)])])
        let queue = LibraryWriteQueue(service: service, directory: root); _ = try await queue.put(record, session: session())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        let corrupt = Data("owned-corrupt".utf8); try corrupt.write(to: file)
        let reopened = LibraryWriteQueue(service: service, directory: root)
        do { _ = try await reopened.pending(owner: session().user.id); XCTFail("Corruption is not an empty queue") } catch { }
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
        let blocker = root.appendingPathComponent("blocked"); try Data("owned-blocker".utf8).write(to: blocker)
        await service.appendFailure()
        let blocked = LibraryWriteQueue(service: service, directory: blocker.appendingPathComponent("queue"))
        do { _ = try await blocked.put(record, session: session()); XCTFail("An unwritable queue cannot accept the intent") } catch { }
        XCTAssertEqual(try Data(contentsOf: blocker), Data("owned-blocker".utf8))
    }
    func testActualLibraryDismissalQueuesOfflineClearsOnlySharedResumeAndDoesNotResurrectFromTheLocalLedger() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try fixture(), raw = fixture["dismissals"].array[0]["item"], now = try XCTUnwrap(fixture["now"].numericValue)
        let owner = "owned-dismiss-model-" + UUID().uuidString, account = session(owner), person = owner + "-a"
        let service = OwnedLibraryQueueService(puts: [.object(["error": .bool(true)])], library: [raw])
        let queue = LibraryWriteQueue(service: service, directory: root.appendingPathComponent("queue"))
        let local = LocalContinueStore(root: root.appendingPathComponent("history")), model = LibraryModel(localContinue: local, service: service, writeQueue: queue)
        await model.setSession(account, personalOwner: person)
        await model.bindLocalContinuing(sharedOwner: owner, scope: "owned", active: { true })
        let target = ResumeTarget(id: raw["_id"].string!), media = try XCTUnwrap(LibraryRecord(raw: raw).media)
        let checkpoint = ResumeSnapshot(positionMs: 400_000, durationMs: 1_000_000, timestampMs: UInt64(now - 1_000), exiting: true)
        let shared = ResumeStore(fileURL: root.appendingPathComponent("shared.json")), personal = ResumeStore(fileURL: root.appendingPathComponent("personal.json"))
        for store in [shared, personal] { try await store.load(); try await store.save(target, snapshot: checkpoint) }
        model.bindPlaybackProgress(.init(personalOwner: person, sharedOwner: owner, personal: personal, shared: shared))
        await model.saveLocalProgress(media, target: target, snapshot: checkpoint, source: .library, owner: owner, personalOwner: person)
        let record = try XCTUnwrap(model.continuing.first)
        await model.hideContinuing(record, owner: owner, now: Date(timeIntervalSince1970: now / 1_000))?.value
        let sharedEntry = try await shared.entry(target), personalEntry = try await personal.entry(target)
        XCTAssertNil(sharedEntry); XCTAssertEqual(personalEntry?.ms, 400_000); XCTAssertTrue(model.continuing.isEmpty)
        let resume = await model.resume(for: target); XCTAssertNil(resume, "Neither the old remote record nor the shared local ledger may undo the dismissal")
        let pending = try await queue.pending(owner: owner); XCTAssertEqual(pending.count, 1); XCTAssertEqual(pending[0]["providerField"], .string("preserved"))
        let restored = LibraryModel(localContinue: local, service: service, writeQueue: LibraryWriteQueue(service: service, directory: root.appendingPathComponent("queue")))
        await restored.setSession(account, personalOwner: person, synchronize: false)
        await restored.bindLocalContinuing(sharedOwner: owner, scope: "owned", active: { true })
        XCTAssertTrue(restored.continuing.isEmpty)
        await restored.flushPendingWrites(); let sent = await service.calls.filter { $0["method"].string == "datastorePut" }
        XCTAssertEqual(sent.count, 2)
        let after = await restored.resume(for: target); XCTAssertTrue(after == nil || after?.entry.ms == 0)
    }
    func testDismissalCleanupCannotEraseANewerRealCheckpoint() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ResumeStore(fileURL: root.appendingPathComponent("resume.json")), target = ResumeTarget(id: "owned-new-playback", season: 0, episode: 7)
        try await store.load(); try await store.save(target, snapshot: .init(positionMs: 600_000, durationMs: 1_000_000, timestampMs: 1_700_000_010_123, exiting: true))
        let cleared = try await store.clear(target, notNewerThan: 1_700_000_000_123), entry = try await store.entry(target)
        XCTAssertFalse(cleared); XCTAssertEqual(entry?.ms, 600_000)
        let lease = OwnedDismissalLease()
        let pending = Task { try await store.importRemote(target, entry: .init(ms: 650_000, t: 1_700_000_020_123), current: { await lease.wait() }) }
        for _ in 0..<200 { if await lease.isWaiting() { break }; try await Task.sleep(for: .milliseconds(5)) }
        let waiting = await lease.isWaiting(); XCTAssertTrue(waiting)
        let removed = try await store.clear(target, notNewerThan: 1_700_000_030_123); XCTAssertTrue(removed)
        await lease.release(); let imported = try await pending.value; XCTAssertFalse(imported)
        let absent = try await store.entry(target); XCTAssertNil(absent)
        let late = try await store.save(target, snapshot: .init(positionMs: 700_000, durationMs: 1_000_000, timestampMs: 1_700_000_025_123, exiting: true))
        XCTAssertFalse(late)
        let merged = try await store.position(target, cloud: .init(ms: 650_000, t: 1_700_000_020_123)); XCTAssertEqual(merged.ms, 0)
        let fresh = try await store.save(target, snapshot: .init(positionMs: 710_000, durationMs: 1_000_000, timestampMs: 1_700_000_040_123, exiting: true))
        let freshEntry = try await store.entry(target); XCTAssertTrue(fresh); XCTAssertEqual(freshEntry?.ms, 710_000)
        var movie = Media(id: "owned-legacy-dismissal", type: "movie", name: "Owned legacy")
        movie.videos = [.init(id: movie.id + ":1:1", season: 1, episode: 1)]
        let oldMovie = ResumeTarget(id: movie.id, season: 1, episode: 1, videoId: movie.videos?.first?.id), currentMovie = ResumeTarget(id: movie.id)
        try await store.save(oldMovie, snapshot: .init(positionMs: 300_000, durationMs: 1_000_000, timestampMs: 1_700_000_020_123, exiting: true))
        _ = try await store.clear(currentMovie, notNewerThan: 1_700_000_030_123)
        let legacy = try await store.position(currentMovie, durationMs: 1_000_000, media: movie)
        XCTAssertEqual(legacy.ms, 0, "An old S1E1 alias cannot undo a cleared movie key that was already absent")
    }
    func testOfflineBookmarkChangesPreserveProviderFieldsAndNewerRemotePlaybackWinsTheRecovery() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let raw = try fixture()["dismissals"].array[0]["item"], owner = "owned-offline-bookmark-" + UUID().uuidString
        let failure = JSONValue.object(["error": .bool(true)])
        let service = OwnedLibraryQueueService(puts: [failure, failure], gets: [failure, failure], library: [raw])
        let queue = LibraryWriteQueue(service: service, directory: root), model = LibraryModel(service: service, writeQueue: queue)
        let account = session(owner), media = try XCTUnwrap(LibraryRecord(raw: raw).media)
        await model.setSession(account)
        await model.toggleBookmark(media); XCTAssertFalse(model.bookmarked(media))
        await model.toggleBookmark(media); XCTAssertTrue(model.bookmarked(media))
        let pending = try await queue.pending(owner: owner); XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0]["removed"], .bool(false)); XCTAssertEqual(pending[0]["providerField"], .string("preserved"))
        var fields = raw.objectValue, state = raw["state"].objectValue
        fields["_mtime"] = .string(ContinueDismissalAction.iso(Date().timeIntervalSince1970 * 1_000 + 30_000))
        state["timeOffset"] = .integer(700_000); fields["state"] = .object(state)
        await service.replaceLibrary([.object(fields)]); await model.flushPendingWrites()
        let remaining = try await queue.pending(owner: owner), calls = await service.calls
        XCTAssertTrue(remaining.isEmpty); XCTAssertEqual(calls.filter { $0["method"].string == "datastorePut" }.count, 2)
        XCTAssertEqual(model.items.first?.raw["state"]["timeOffset"].integer, 700_000)
        let resume = await model.resume(for: .init(id: media.id), refresh: false); XCTAssertEqual(resume?.entry.ms, 700_000)
    }
    func testPrivateReadFailureCanBeRetriedOrDisabledWithoutLeavingAnUnrelatedError() async throws {
        let memory = OwnedDismissalRetryStore(), store = ContinueDismissalStore(persistence: memory)
        let model = LibraryModel(privateDismissals: store)
        let owner = "owned-private-retry-" + UUID().uuidString
        await model.setSession(nil, personalOwner: owner, guestOwner: owner, synchronize: false)
        model.setContinuePrivacy(true, migratedScope: "owned-retry"); XCTAssertNotNil(model.presentationError)
        model.reloadPresentation(); XCTAssertNotNil(model.presentationError, "Reloading the shared document cannot hide a private read failure")
        model.setContinuePrivacy(false); XCTAssertNil(model.presentationError)
        model.setContinuePrivacy(true, migratedScope: "owned-retry"); XCTAssertNotNil(model.presentationError)
        memory.failing = false; model.reloadPresentation(); XCTAssertNil(model.presentationError); XCTAssertTrue(model.continuingPrivate)
    }
}
