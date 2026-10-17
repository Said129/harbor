import XCTest
@testable import Harbor

@MainActor private final class NavigationSyncMemory: NavigationLayoutPersistence, NavigationSyncPersistence {
    var layouts: [String: NativeNavigationLayout] = [:]
    var records: [String: NavigationSyncRecord] = [:]
    var failSyncWrite = false
    func read(_ key: String) throws -> NativeNavigationLayout? { layouts[key] }
    func write(_ value: NativeNavigationLayout, key: String) throws { layouts[key] = value }
    func readSync(_ key: String) throws -> NavigationSyncRecord? { records[key] }
    func writeSync(_ value: NavigationSyncRecord, key: String) throws {
        if failSyncWrite { throw HarborError(code: "test-storage-unavailable") }
        records[key] = value
    }
}

@MainActor final class NavigationSyncTests: XCTestCase {
    private let owner = "isolated-owner"
    private let profile = JSONValue.object(["syncId": .string("primary-id"), "settingsLinked": .bool(true)])
    private let defaultsOrder = ["home", "anime", "search", "music"]
    private let known: Set<String> = ["home", "anime", "music"]
    private var desktop: JSONValue { .object(["order": .array(["home", "games", "anime", "music"].map(JSONValue.string)), "hidden": .array([]), "renamed": .object(["games": .string("My PC"), "anime": .string("Desktop anime")]), "future": .bool(true)]) }
    private func state(_ value: JSONValue?, rev: Int64) -> JSONValue {
        .object(["rev": .integer(rev), "docs": .array(value.map { [.object(["key": .string("primary-id:nav"), "rev": .integer(rev), "value": $0])] } ?? [])])
    }
    private func accepted(_ rev: Int64) -> JSONValue { .object(["results": .array([.object(["ok": .bool(true), "rev": .integer(rev)])])]) }
    private func engine(_ prefs: ScopedNavigationPreferences, memory: NavigationSyncMemory) -> HarborNavigationSync {
        HarborNavigationSync(owner: owner, preferences: prefs, defaultOrder: defaultsOrder, knownIDs: known, persistence: memory)
    }
    private func isolated(_ body: @MainActor (UserDefaults, ScopedNavigationPreferences, HarborNavigationSync, NavigationSyncMemory) async throws -> Void) async throws {
        let suite = "HarborNavigationSyncTests-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = NavigationSyncMemory(), prefs = ScopedNavigationPreferences(storage: defaults, persistence: memory)
        prefs.bind(.local(owner: owner))
        try await body(defaults, prefs, engine(prefs, memory: memory), memory)
    }
    private func hydrate(_ sync: HarborNavigationSync) async throws {
        try await sync.synchronize(state: state(desktop, rev: 7), account: "account-one", profile: profile) { _ in XCTFail("A pull must not push defaults"); return .null }
    }
    func testDesktopPullAppliesNavigationWithoutAnEchoOrDefaultUpload() async throws {
        try await isolated { _, prefs, sync, _ in
            var requests = 0; sync.requestSync = { requests += 1 }
            try await self.hydrate(sync)
            XCTAssertEqual(prefs.value.renamed["anime"], "Desktop anime")
            XCTAssertEqual(prefs.value.order, ["home", "anime", "search", "music"])
            XCTAssertFalse(prefs.value.order.contains("games"))
            XCTAssertFalse(sync.hasPendingChanges); XCTAssertFalse(sync.hasParkedVersion); XCTAssertEqual(requests, 0)
            try await self.hydrate(sync); XCTAssertEqual(requests, 0)
        }
    }
    func testUserEditSendsTheDesktopDocumentAndKeepsUnknownConfiguration() async throws {
        try await isolated { _, prefs, sync, _ in
            try await self.hydrate(sync)
            prefs.change { $0.renamed["anime"] = "iPhone anime" }
            XCTAssertTrue(sync.hasPendingChanges)
            var sent: JSONValue?
            try await sync.synchronize(state: self.state(self.desktop, rev: 7), account: "account-one", profile: self.profile) { packet in
                XCTAssertEqual(packet["writes"].array.first?["baseRev"], .integer(7))
                sent = packet["writes"].array.first?["value"]
                XCTAssertEqual(sent?["renamed"]["games"].string, "My PC")
                XCTAssertEqual(sent?["renamed"]["anime"].string, "iPhone anime")
                XCTAssertEqual(sent?["future"], .bool(true))
                return self.accepted(8)
            }
            XCTAssertFalse(sync.hasPendingChanges)
            XCTAssertEqual(prefs.value.renamed["anime"], "iPhone anime")
            try await sync.synchronize(state: self.state(try XCTUnwrap(sent), rev: 8), account: "account-one", profile: self.profile) { _ in XCTFail("An acknowledged value must not echo"); return .null }
        }
    }
    func testConflictAdoptsServerAndRestoresOnlyMobileChoicesOnExplicitRequest() async throws {
        try await isolated { _, prefs, sync, _ in
            try await self.hydrate(sync)
            prefs.change { $0.order = ["music", "home", "search", "anime"] }
            var remote = self.desktop.objectValue
            remote["order"] = .array(["anime", "games", "home", "music"].map(JSONValue.string))
            remote["renamed"] = .object(["games": .string("New PC name"), "anime": .string("Online device")])
            let newest = JSONValue.object(remote)
            try await sync.synchronize(state: self.state(self.desktop, rev: 7), account: "account-one", profile: self.profile) { _ in
                .object(["results": .array([.object(["ok": .bool(false), "current": .object(["key": .string("primary-id:nav"), "rev": .integer(9), "value": newest])])])])
            }
            XCTAssertTrue(sync.hasParkedVersion); XCTAssertFalse(sync.hasPendingChanges)
            XCTAssertEqual(prefs.value.renamed["anime"], "Online device")
            XCTAssertEqual(prefs.value.order.filter { self.known.contains($0) }, ["anime", "home", "music"])
            sync.restoreMyVersion(); XCTAssertTrue(sync.hasPendingChanges)
            try await sync.synchronize(state: self.state(newest, rev: 9), account: "account-one", profile: self.profile) { packet in
                let write = try XCTUnwrap(packet["writes"].array.first)
                XCTAssertEqual(write["baseRev"], .integer(9))
                XCTAssertEqual(write["value"]["renamed"]["games"].string, "New PC name", "Restoring mobile choices must retain current PC-only fields")
                XCTAssertEqual(write["value"]["order"].array.compactMap(\.string).filter { self.known.contains($0) }, ["music", "home", "anime"])
                return self.accepted(10)
            }
            XCTAssertFalse(sync.hasPendingChanges); XCTAssertFalse(sync.hasParkedVersion)
        }
    }
    func testAnEditDuringTheRequestKeepsItsVersionAndUsesTheAcceptedRevisionNext() async throws {
        try await isolated { _, prefs, sync, _ in
            try await self.hydrate(sync)
            prefs.change { $0.renamed["anime"] = "First edit" }
            var first: JSONValue?
            try await sync.synchronize(state: self.state(self.desktop, rev: 7), account: "account-one", profile: self.profile) { packet in
                first = packet["writes"].array.first?["value"]
                prefs.change { $0.renamed["anime"] = "Second edit" }
                return self.accepted(8)
            }
            XCTAssertTrue(sync.hasPendingChanges); XCTAssertEqual(prefs.value.renamed["anime"], "Second edit")
            try await sync.synchronize(state: self.state(try XCTUnwrap(first), rev: 8), account: "account-one", profile: self.profile) { packet in
                let write = try XCTUnwrap(packet["writes"].array.first)
                XCTAssertEqual(write["baseRev"], .integer(8)); XCTAssertEqual(write["value"]["renamed"]["anime"].string, "Second edit")
                return self.accepted(9)
            }
            XCTAssertFalse(sync.hasPendingChanges)
        }
    }
    func testLateAcknowledgementCannotAffectAnotherOwnerAndIsRecoveredAfterReturning() async throws {
        try await isolated { _, prefs, sync, memory in
            try await self.hydrate(sync); prefs.change { $0.renamed["anime"] = "Owner edit" }
            var sent: JSONValue?
            do {
                try await sync.synchronize(state: self.state(self.desktop, rev: 7), account: "account-one", profile: self.profile) { packet in
                    sent = packet["writes"].array.first?["value"]
                    prefs.bind(.local(owner: "another-owner"))
                    return self.accepted(8)
                }
                XCTFail("A late response must be rejected after switching owners")
            } catch let failure as HarborError { XCTAssertEqual(failure.code, "account-changed") }
            XCTAssertTrue(prefs.value.renamed.isEmpty)
            XCTAssertTrue(memory.records.values.contains { $0.pending != nil })
            prefs.bind(.local(owner: self.owner))
            try await sync.synchronize(state: self.state(try XCTUnwrap(sent), rev: 8), account: "account-one", profile: self.profile) { _ in XCTFail("The GET already proves acceptance"); return .null }
            XCTAssertFalse(sync.hasPendingChanges); XCTAssertEqual(prefs.value.renamed["anime"], "Owner edit")
        }
    }
    func testFailedQueueWriteRetainsTheNativeEditAndRecoversBeforePullCanReplaceIt() async throws {
        try await isolated { _, prefs, sync, memory in
            try await self.hydrate(sync)
            memory.failSyncWrite = true
            prefs.change { $0.renamed["anime"] = "Saved offline edit" }
            XCTAssertNotNil(sync.error); XCTAssertEqual(prefs.value.renamed["anime"], "Saved offline edit")
            do {
                try await sync.synchronize(state: self.state(self.desktop, rev: 7), account: "account-one", profile: self.profile) { _ in XCTFail("An unpersisted queue must not push"); return .null }
                XCTFail("The failing queue must stay recoverable")
            } catch {}
            XCTAssertEqual(prefs.value.renamed["anime"], "Saved offline edit")
            memory.failSyncWrite = false
            try await sync.synchronize(state: self.state(self.desktop, rev: 7), account: "account-one", profile: self.profile) { packet in
                XCTAssertEqual(packet["writes"].array.first?["value"]["renamed"]["anime"].string, "Saved offline edit")
                return self.accepted(8)
            }
            XCTAssertFalse(sync.hasPendingChanges); XCTAssertNil(sync.error)
        }
    }
    func testPendingChangesSurviveAClientRestart() async throws {
        try await isolated { defaults, prefs, sync, memory in
            try await self.hydrate(sync); prefs.change { $0.hidden.insert("music") }
            let restored = ScopedNavigationPreferences(storage: defaults, persistence: memory)
            restored.bind(.local(owner: self.owner))
            let next = self.engine(restored, memory: memory)
            try await next.synchronize(state: self.state(self.desktop, rev: 7), account: "account-one", profile: self.profile) { packet in
                XCTAssertEqual(packet["writes"].array.first?["baseRev"], .integer(7))
                XCTAssertTrue(packet["writes"].array.first?["value"]["hidden"].array.contains(.string("music")) == true)
                return self.accepted(8)
            }
            XCTAssertTrue(restored.value.hidden.contains("music")); XCTAssertFalse(next.hasPendingChanges)
        }
    }
    func testMissingRemoteSectionHoldsDefaultsUntilARealUserEdit() async throws {
        try await isolated { _, prefs, sync, _ in
            try await sync.synchronize(state: self.state(nil, rev: 0), account: "account-one", profile: self.profile) { _ in XCTFail("An empty install has nothing to upload"); return .null }
            XCTAssertFalse(sync.hasPendingChanges)
            prefs.change { $0.renamed["anime"] = "First choice" }
            try await sync.synchronize(state: self.state(nil, rev: 0), account: "account-one", profile: self.profile) { packet in
                XCTAssertEqual(packet["writes"].array.first?["baseRev"], .integer(0))
                return self.accepted(1)
            }
            XCTAssertFalse(sync.hasPendingChanges)
        }
    }
    func testSwitchingHarborAccountsNeverUploadsThePreviousAccountsQueue() async throws {
        try await isolated { _, prefs, sync, memory in
            try await self.hydrate(sync); prefs.change { $0.renamed["anime"] = "Pending for account one" }
            var other = self.desktop.objectValue; other["renamed"] = .object(["anime": .string("Account two")])
            try await sync.synchronize(state: self.state(.object(other), rev: 2), account: "account-two", profile: self.profile) { _ in XCTFail("Never push account one's edit into account two"); return .null }
            XCTAssertEqual(prefs.value.renamed["anime"], "Account two"); XCTAssertFalse(sync.hasPendingChanges)
            XCTAssertTrue(memory.records.values.contains { $0.pending != nil }, "The original account's queued edit is retained")
            try await sync.synchronize(state: self.state(self.desktop, rev: 7), account: "account-one", profile: self.profile) { packet in
                XCTAssertEqual(packet["writes"].array.first?["value"]["renamed"]["anime"].string, "Pending for account one")
                return self.accepted(8)
            }
            XCTAssertFalse(sync.hasPendingChanges)
        }
    }
    func testInvalidIncomingLayoutNeverArmsAnUploadOrErasesLocalChoices() async throws {
        try await isolated { _, prefs, sync, _ in
            prefs.change { $0.renamed["anime"] = "Local choice" }; let original = prefs.value
            do {
                try await sync.synchronize(state: self.state(.object(["order": .bool(false)]), rev: 7), account: "account-one", profile: self.profile) { _ in XCTFail("A malformed remote section must not arm a push"); return .null }
                XCTFail("Malformed remote data must be rejected")
            } catch let failure as HarborError { XCTAssertEqual(failure.code, "navigation-sync-value") }
            XCTAssertEqual(prefs.value, original); XCTAssertFalse(sync.hasPendingChanges)
            XCTAssertEqual(prefs.scope, .local(owner: self.owner))
        }
    }
}
