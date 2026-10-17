import XCTest
@testable import Harbor

@MainActor private final class StreamingSyncMemory: StreamingPreferencePersistence, StreamingSyncPersistence {
    var preferences: [String: [String: Bool]] = [:]
    var records: [String: StreamingSyncRecord] = [:]
    var failRead = false
    var failWrite = false
    var failQueueWrite = false
    func load(_ key: String) throws -> [String: Bool]? {
        if failRead { throw HarborError(code: "test-read") }; return preferences[key]
    }
    func save(_ value: [String: Bool], key: String) throws {
        if failWrite { throw HarborError(code: "test-write") }; preferences[key] = value
    }
    func readSync(_ key: String) throws -> StreamingSyncRecord? { records[key] }
    func writeSync(_ value: StreamingSyncRecord, key: String) throws {
        if failQueueWrite { throw HarborError(code: "test-queue") }; records[key] = value
    }
}

@MainActor final class StreamingSyncTests: XCTestCase {
    private let owner = "synthetic-streaming-owner"
    private let profile: JSONValue = .object(["syncId": .string("one"), "settingsLinked": .bool(false)])
    private var desktop: JSONValue { .object(["netflix": .bool(false), "prime": .bool(true), "future-provider": .object(["mode": .string("desktop-only")])]) }
    private func state(_ value: JSONValue?, rev: Int64, id: String = "one") -> JSONValue {
        .object(["rev": .integer(rev), "docs": .array(value.map { [.object(["key": .string(id + ":services"), "rev": .integer(rev), "value": $0])] } ?? [])])
    }
    private func accepted(_ rev: Int64) -> JSONValue { .object(["results": .array([.object(["ok": .bool(true), "rev": .integer(rev)])])]) }
    private func setup() -> (StreamingSyncMemory, StreamingPreferences, HarborStreamingSync) {
        let memory = StreamingSyncMemory(), preferences = StreamingPreferences(owner: owner, persistence: memory)
        return (memory, preferences, HarborStreamingSync(owner: owner, preferences: preferences, persistence: memory))
    }
    private func hydrate(_ sync: HarborStreamingSync) async throws {
        try await sync.synchronize(state: state(desktop, rev: 7), account: "account-a", profile: profile) { _ in XCTFail("A pull must not upload defaults"); return .null }
    }

    func testAccountAndUnlinkedProfilePreferencesSurviveRestartWithoutLeakingSelections() {
        let (memory, preferences, _) = setup()
        XCTAssertTrue(preferences.setEnabled(false, for: "netflix"))
        let a = NavigationScope.harbor(owner: owner, account: "a", profile: "one", linked: false)
        let b = NavigationScope.harbor(owner: owner, account: "b", profile: "one", linked: false)
        preferences.bind(a); XCTAssertFalse(preferences.isEnabled("netflix"))
        XCTAssertTrue(preferences.setEnabled(false, for: "prime"))
        preferences.bind(b); XCTAssertTrue(preferences.isEnabled("prime")); XCTAssertFalse(preferences.isEnabled("netflix"))
        preferences.bind(.harbor(owner: owner, account: "a", profile: "two", linked: false)); XCTAssertTrue(preferences.isEnabled("prime"))
        let reopened = StreamingPreferences(owner: owner, persistence: memory); reopened.bind(a)
        XCTAssertFalse(reopened.isEnabled("prime"))
        preferences.bind(.local(owner: owner)); XCTAssertTrue(preferences.isEnabled("prime")); XCTAssertFalse(preferences.isEnabled("netflix"))
        preferences.suspend(); XCTAssertFalse(preferences.ready); XCTAssertTrue(preferences.values.isEmpty)
        XCTAssertFalse(preferences.setEnabled(true, for: "netflix"))
        preferences.bind(.local(owner: owner)); XCTAssertTrue(preferences.ready); XCTAssertFalse(preferences.isEnabled("netflix"))
    }
    func testLinkedProfilesShareSettingsAndAnOldButtonCannotEditANewAccount() {
        let (_, preferences, _) = setup()
        let first = NavigationScope.harbor(owner: owner, account: "a", profile: "one", linked: true)
        let second = NavigationScope.harbor(owner: owner, account: "a", profile: "two", linked: true)
        preferences.bind(first); XCTAssertTrue(preferences.setEnabled(false, for: "prime", in: first))
        preferences.bind(second); XCTAssertFalse(preferences.isEnabled("prime"))
        XCTAssertFalse(preferences.setEnabled(true, for: "prime", in: first)); XCTAssertFalse(preferences.isEnabled("prime"))
        preferences.bind(.harbor(owner: owner, account: "b", profile: "two", linked: true)); XCTAssertTrue(preferences.isEnabled("prime"))
    }
    func testScopeReadAndWriteFailuresDoNotPublishAnotherScopeOrOverwriteSavedValues() {
        let (memory, preferences, _) = setup()
        XCTAssertTrue(preferences.setEnabled(false, for: "prime")); let before = memory.preferences
        memory.failRead = true
        preferences.bind(.harbor(owner: owner, account: "a", profile: "one", linked: false))
        XCTAssertFalse(preferences.ready); XCTAssertTrue(preferences.values.isEmpty)
        XCTAssertFalse(preferences.setEnabled(false, for: "netflix")); XCTAssertEqual(memory.preferences, before)
        memory.failRead = false; preferences.reload(); XCTAssertTrue(preferences.ready)
        memory.failWrite = true
        XCTAssertFalse(preferences.setEnabled(false, for: "netflix")); XCTAssertTrue(preferences.isEnabled("netflix")); XCTAssertEqual(memory.preferences, before)
    }
    func testDesktopPullUsesTheServiceDocumentWithoutEchoingAndPreservesLocalDefaults() async throws {
        let (_, preferences, sync) = setup()
        var scheduled = 0; sync.requestSync = { scheduled += 1 }
        try await hydrate(sync)
        XCTAssertFalse(preferences.isEnabled("netflix")); XCTAssertTrue(preferences.isEnabled("prime"))
        XCTAssertTrue(preferences.isEnabled("disney")); XCTAssertFalse(sync.hasPendingChanges); XCTAssertFalse(sync.hasParkedVersion)
        XCTAssertEqual(scheduled, 0)
        try await hydrate(sync); XCTAssertEqual(scheduled, 0)
    }
    func testEditingSendsTheExactWireKeyAndRetainsUnknownDesktopFields() async throws {
        let (_, preferences, sync) = setup(); try await hydrate(sync)
        XCTAssertTrue(preferences.setEnabled(true, for: "netflix")); XCTAssertTrue(sync.hasPendingChanges)
        var sent: JSONValue?
        try await sync.synchronize(state: state(desktop, rev: 7), account: "account-a", profile: profile) { packet in
            let write = try XCTUnwrap(packet["writes"].array.first)
            XCTAssertEqual(write["key"].string, "one:services"); XCTAssertEqual(write["baseRev"], .integer(7))
            XCTAssertEqual(write["value"]["netflix"], .bool(true)); XCTAssertEqual(write["value"]["future-provider"], self.desktop["future-provider"])
            sent = write["value"]; return self.accepted(8)
        }
        XCTAssertFalse(sync.hasPendingChanges)
        try await sync.synchronize(state: state(try XCTUnwrap(sent), rev: 8), account: "account-a", profile: profile) { _ in XCTFail("An acknowledgement must not echo"); return .null }
    }
    func testConflictAdoptsServerAndExplicitRestoreKeepsTheNewestUnknownDesktopFields() async throws {
        let (_, preferences, sync) = setup(); try await hydrate(sync)
        preferences.setEnabled(true, for: "netflix")
        var fields = desktop.objectValue; fields["future-provider"] = .object(["mode": .string("new-desktop-mode")])
        let newest = JSONValue.object(fields)
        try await sync.synchronize(state: state(desktop, rev: 7), account: "account-a", profile: profile) { _ in
            .object(["results": .array([.object(["ok": .bool(false), "current": .object(["key": .string("one:services"), "rev": .integer(9), "value": newest])])])])
        }
        XCTAssertFalse(preferences.isEnabled("netflix")); XCTAssertTrue(sync.hasParkedVersion); XCTAssertFalse(sync.hasPendingChanges)
        sync.restoreMyVersion(); XCTAssertTrue(preferences.isEnabled("netflix")); XCTAssertTrue(sync.hasPendingChanges)
        try await sync.synchronize(state: state(newest, rev: 9), account: "account-a", profile: profile) { packet in
            let write = try XCTUnwrap(packet["writes"].array.first)
            XCTAssertEqual(write["value"]["future-provider"], newest["future-provider"])
            XCTAssertEqual(write["value"]["netflix"], .bool(true)); return self.accepted(10)
        }
        XCTAssertFalse(sync.hasPendingChanges); XCTAssertFalse(sync.hasParkedVersion)
    }
    func testAnEditDuringAcknowledgementRemainsQueuedAtTheNewServerRevision() async throws {
        let (_, preferences, sync) = setup(); try await hydrate(sync)
        preferences.setEnabled(true, for: "netflix")
        var first: JSONValue?
        try await sync.synchronize(state: state(desktop, rev: 7), account: "account-a", profile: profile) { packet in
            first = packet["writes"].array.first?["value"]
            preferences.setEnabled(false, for: "prime")
            return self.accepted(8)
        }
        XCTAssertTrue(sync.hasPendingChanges); XCTAssertFalse(preferences.isEnabled("prime"))
        try await sync.synchronize(state: state(try XCTUnwrap(first), rev: 8), account: "account-a", profile: profile) { packet in
            let write = try XCTUnwrap(packet["writes"].array.first)
            XCTAssertEqual(write["baseRev"], .integer(8)); XCTAssertEqual(write["value"]["prime"], .bool(false)); return self.accepted(9)
        }
        XCTAssertFalse(sync.hasPendingChanges)
    }
    func testAnUncertainAcceptedWriteIsRecognizedAfterRestartWithoutRepeatingIt() async throws {
        let (memory, preferences, sync) = setup(); try await hydrate(sync)
        preferences.setEnabled(true, for: "netflix")
        var sent: JSONValue?
        do {
            try await sync.synchronize(state: state(desktop, rev: 7), account: "account-a", profile: profile) { packet in
                sent = packet["writes"].array.first?["value"]; throw HarborError(code: "test-lost-response")
            }; XCTFail("The transport should fail after capturing the write")
        } catch { XCTAssertTrue(sync.hasPendingChanges) }
        let reopened = StreamingPreferences(owner: owner, persistence: memory), resumed = HarborStreamingSync(owner: owner, preferences: reopened, persistence: memory)
        try await resumed.synchronize(state: state(try XCTUnwrap(sent), rev: 8), account: "account-a", profile: profile) { _ in XCTFail("GET already confirms this write"); return .null }
        XCTAssertTrue(reopened.isEnabled("netflix")); XCTAssertFalse(resumed.hasPendingChanges)
    }
    func testAResponseFromAnOldAccountCannotChangeTheNewAccountOrItsQueue() async throws {
        let (_, preferences, sync) = setup(); try await hydrate(sync)
        preferences.setEnabled(true, for: "netflix")
        do {
            try await sync.synchronize(state: state(desktop, rev: 7), account: "account-a", profile: profile) { _ in
                try await sync.synchronize(state: self.state(self.desktop, rev: 12), account: "account-b", profile: self.profile) { _ in XCTFail("The new account only pulls"); return .null }
                return self.accepted(8)
            }; XCTFail("The old scope must reject the acknowledgement")
        } catch { XCTAssertEqual((error as? HarborError)?.code, "account-changed") }
        XCTAssertEqual(preferences.scope, .harbor(owner: owner, account: "account-b", profile: "one", linked: false))
        XCTAssertFalse(preferences.isEnabled("netflix")); XCTAssertFalse(sync.hasPendingChanges)
    }
    func testFailedQueueReplacementRecoversTheNewestLocallySavedCheckboxes() async throws {
        let (memory, preferences, sync) = setup(); try await hydrate(sync)
        preferences.setEnabled(true, for: "netflix"); XCTAssertTrue(sync.hasPendingChanges)
        memory.failQueueWrite = true
        preferences.setEnabled(false, for: "prime"); XCTAssertNotNil(sync.error)
        do {
            try await sync.synchronize(state: state(desktop, rev: 7), account: "account-a", profile: profile) { _ in XCTFail("Queue persistence must succeed first"); return .null }
            XCTFail("The unavailable queue must stop synchronization")
        } catch { XCTAssertTrue(preferences.isEnabled("netflix")); XCTAssertFalse(preferences.isEnabled("prime")) }
        memory.failQueueWrite = false
        try await sync.synchronize(state: state(desktop, rev: 7), account: "account-a", profile: profile) { packet in
            let write = try XCTUnwrap(packet["writes"].array.first)
            XCTAssertEqual(write["value"]["netflix"], .bool(true)); XCTAssertEqual(write["value"]["prime"], .bool(false)); return self.accepted(8)
        }
        XCTAssertFalse(sync.hasPendingChanges)
    }
    func testMalformedAndRegressingDocumentsNeverOverwriteTheCurrentSelection() async throws {
        let (_, preferences, sync) = setup(); try await hydrate(sync)
        let before = preferences.selection
        let duplicate = JSONValue.object(["rev": .integer(8), "docs": .array(state(desktop, rev: 8)["docs"].array + state(desktop, rev: 8)["docs"].array)])
        for invalid in [state(.object(["netflix": .string("false")]), rev: 8), state(desktop, rev: 6), state(.object(["netflix": .bool(true)]), rev: 7), duplicate] {
            do { try await sync.synchronize(state: invalid, account: "account-a", profile: profile) { _ in XCTFail("Invalid state must not push"); return .null }; XCTFail("Invalid document accepted") }
            catch { XCTAssertEqual(preferences.selection, before) }
        }
    }
    func testConflictBackupAndInterruptedApplicationSurviveStorageFailureAndRestart() async throws {
        let (memory, preferences, sync) = setup(); try await hydrate(sync)
        preferences.setEnabled(true, for: "netflix")
        var fields = desktop.objectValue; fields["prime"] = .bool(false)
        let newest = JSONValue.object(fields)
        memory.failQueueWrite = true
        do {
            try await sync.synchronize(state: state(newest, rev: 9), account: "account-a", profile: profile) { _ in XCTFail("The incoming conflict only pulls"); return .null }
            XCTFail("The backup must be durable before applying server preferences")
        } catch { XCTAssertTrue(preferences.isEnabled("netflix")); XCTAssertTrue(sync.hasPendingChanges) }
        memory.failQueueWrite = false; memory.failWrite = true
        do {
            try await sync.synchronize(state: state(newest, rev: 9), account: "account-a", profile: profile) { _ in XCTFail("No default push"); return .null }
            XCTFail("The preference write must report its failure")
        } catch {
            XCTAssertTrue(preferences.isEnabled("netflix")); XCTAssertTrue(sync.hasParkedVersion)
            XCTAssertTrue(preferences.cloudWritePending); XCTAssertFalse(preferences.setEnabled(false, for: "prime"))
        }
        memory.failWrite = false
        let reopened = StreamingPreferences(owner: owner, persistence: memory), resumed = HarborStreamingSync(owner: owner, preferences: reopened, persistence: memory)
        try await resumed.synchronize(state: state(newest, rev: 9), account: "account-a", profile: profile) { _ in XCTFail("Recovery must finish applying the incoming value"); return .null }
        XCTAssertFalse(reopened.isEnabled("netflix")); XCTAssertFalse(reopened.isEnabled("prime"))
        XCTAssertFalse(reopened.cloudWritePending); XCTAssertTrue(resumed.hasParkedVersion); XCTAssertFalse(resumed.hasPendingChanges)
    }
    func testMissingServerDocumentDoesNotUploadDefaultsOrResurrectADeletedDocument() async throws {
        let (_, preferences, sync) = setup()
        try await sync.synchronize(state: state(nil, rev: 1), account: "account-a", profile: profile) { _ in XCTFail("No default upload"); return .null }
        preferences.setEnabled(false, for: "netflix")
        try await sync.synchronize(state: state(nil, rev: 1), account: "account-a", profile: profile) { packet in
            XCTAssertEqual(packet["writes"].array.first?["baseRev"], .integer(0)); return self.accepted(2)
        }
        preferences.setEnabled(false, for: "prime")
        try await sync.synchronize(state: state(nil, rev: 3), account: "account-a", profile: profile) { _ in XCTFail("The deleted document must not be silently recreated"); return .null }
        XCTAssertFalse(sync.hasPendingChanges); XCTAssertTrue(sync.hasParkedVersion); XCTAssertFalse(preferences.isEnabled("prime"))
    }
}
