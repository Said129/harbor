import XCTest
@testable import Harbor

@MainActor private final class PageSyncMemory: PageSyncPersistence {
    var values: [String: PageSyncRecord] = [:]
    var writesBeforeFailure: Int?
    func read(_ key: String) throws -> PageSyncRecord? { values[key] }
    func write(_ value: PageSyncRecord, key: String) throws {
        if let remaining = writesBeforeFailure {
            guard remaining > 0 else { throw HarborError(code: "owned-page-store-failure") }
            writesBeforeFailure = remaining - 1
        }
        values[key] = value
    }
}

@MainActor final class PageLayoutSyncTests: XCTestCase {
    private let profile: JSONValue = .object(["syncId": .string("one"), "settingsLinked": .bool(false)])
    private var remote: JSONValue { .object(["order": .array([.string("cm-drama"), .string("cm-comedy")]), "future": .string("preserved")]) }
    private func state(_ value: JSONValue?, rev: Int64, id: String = "one", page: String = "home") -> JSONValue {
        .object(["rev": .integer(rev), "docs": .array(value.map { [.object(["key": .string(id + ":" + page), "rev": .integer(rev), "value": $0])] } ?? [])])
    }
    private func accepted(_ revision: Int64) -> JSONValue { .object(["results": .array([.object(["ok": .bool(true), "rev": .integer(revision)])])]) }
    private func isolated(page: String = "home", _ body: @MainActor (String, PageCustomization, HarborPageSync, PageSyncMemory) async throws -> Void) async throws {
        let owner = "owned-page-sync-" + UUID().uuidString, preferences = PageCustomization(owner: owner, page: page), memory = PageSyncMemory()
        let engine = HarborPageSync(preferences: preferences, persistence: memory)
        defer {
            engine.unbind()
            try? KeychainStore().remove("page-layout-" + EBookShelf.hash(owner + "|" + page))
            for account in ["A", "B"] { for profile in ["one", "two"] { for linked in [true, false] {
                let scope = NavigationScope.harbor(owner: owner, account: account, profile: profile, linked: linked)
                try? KeychainStore().remove("page-layout-scope-" + EBookShelf.hash(scope.key + "|" + page))
            } } }
        }
        try await body(owner, preferences, engine, memory)
    }
    private func hydrate(_ engine: HarborPageSync) async throws {
        try await engine.synchronize(state: state(remote, rev: 1), account: "A", profile: profile) { _ in XCTFail("A pull must not upload defaults"); return .null }
    }

    func testFirstPullHoldsDefaultsAndRealEditWritesOnlyItsProfileSectionWithServerRevision() async throws {
        try await isolated { _, preferences, engine, _ in
            try await engine.synchronize(state: self.state(nil, rev: 0), account: "A", profile: self.profile) { _ in XCTFail("No default push"); return .null }
            XCTAssertFalse(engine.hasPendingChanges); try await self.hydrate(engine)
            XCTAssertEqual(preferences.layout.order, ["discovery-cm-drama", "discovery-cm-comedy"])
            XCTAssertFalse(engine.hasPendingChanges); XCTAssertFalse(engine.hasParkedVersion)
            preferences.change { $0.renamed["discovery-cm-drama"] = "Owned phone name" }
            XCTAssertTrue(engine.hasPendingChanges)
            try await engine.synchronize(state: self.state(self.remote, rev: 1), account: "A", profile: self.profile) { request in
                let writes = request["writes"].array; XCTAssertEqual(writes.count, 1)
                XCTAssertEqual(writes[0]["key"], .string("one:home")); XCTAssertEqual(writes[0]["baseRev"], .integer(1))
                XCTAssertEqual(writes[0]["value"]["renamed"]["cm-drama"], .string("Owned phone name"))
                XCTAssertEqual(writes[0]["value"]["future"], .string("preserved")); return self.accepted(2)
            }
            XCTAssertFalse(engine.hasPendingChanges)
        }
    }

    func testQueueSurvivesReopeningAndNetworkFailureWithoutChangingTheLocalBaseline() async throws {
        try await isolated { owner, preferences, engine, memory in
            preferences.change { $0.renamed["discovery-cm-drama"] = "Local before account" }
            try await self.hydrate(engine)
            preferences.change { $0.cwTop = true }; engine.unbind()
            let reopened = PageCustomization(owner: owner, page: "home"), resumed = HarborPageSync(preferences: reopened, persistence: memory)
            defer { resumed.unbind() }
            do {
                try await resumed.synchronize(state: self.state(self.remote, rev: 1), account: "A", profile: self.profile) { _ in throw HarborError(code: "owned-offline") }
                XCTFail("The transport failed")
            } catch { XCTAssertTrue(resumed.hasPendingChanges); XCTAssertTrue(reopened.layout.cwTop) }
            try await resumed.synchronize(state: self.state(self.remote, rev: 1), account: "A", profile: self.profile) { request in
                XCTAssertEqual(request["writes"].array.first?["value"]["cwTop"], .bool(true)); return self.accepted(2)
            }
            XCTAssertFalse(resumed.hasPendingChanges)
            reopened.bind(.local(owner: owner)); XCTAssertEqual(reopened.layout.renamed["discovery-cm-drama"], "Local before account")
            XCTAssertFalse(reopened.layout.cwTop)
        }
    }

    func testAnEditSavedBeforeAQueueFailureIsRecoveredAfterTheProcessReopens() async throws {
        try await isolated { owner, preferences, engine, memory in
            try await self.hydrate(engine); memory.writesBeforeFailure = 0
            preferences.change { $0.cwTop = true }; XCTAssertTrue(preferences.layout.cwTop); XCTAssertNotNil(engine.error)
            engine.unbind(); memory.writesBeforeFailure = nil
            let reopened = PageCustomization(owner: owner, page: "home"), resumed = HarborPageSync(preferences: reopened, persistence: memory)
            defer { resumed.unbind() }
            try await resumed.synchronize(state: self.state(self.remote, rev: 1), account: "A", profile: self.profile) { request in
                XCTAssertEqual(request["writes"].array.first?["value"]["cwTop"], .bool(true)); return self.accepted(2)
            }
            XCTAssertTrue(reopened.layout.cwTop); XCTAssertFalse(resumed.hasPendingChanges)
        }
    }

    func testAConcurrentRemoteLayoutWinsWholeAndTheParkedLocalVersionCanBeRestoredExplicitly() async throws {
        try await isolated { _, preferences, engine, _ in
            try await self.hydrate(engine); preferences.change { $0.order = ["discovery-cm-comedy", "discovery-cm-drama"] }
            let winner: JSONValue = .object(["order": .array([.string("cm-action")]), "future": .string("new server field")])
            try await engine.synchronize(state: self.state(winner, rev: 2), account: "A", profile: self.profile) { _ in XCTFail("Pull conflict must adopt, not send an invented order"); return .null }
            XCTAssertEqual(preferences.layout.order, ["discovery-cm-action"]); XCTAssertTrue(engine.hasParkedVersion); XCTAssertFalse(engine.hasPendingChanges)
            engine.restoreMyVersion(); XCTAssertEqual(preferences.layout.order, ["discovery-cm-comedy", "discovery-cm-drama"])
            try await engine.synchronize(state: self.state(winner, rev: 2), account: "A", profile: self.profile) { request in
                let write = try XCTUnwrap(request["writes"].array.first)
                XCTAssertEqual(write["baseRev"], .integer(2)); XCTAssertEqual(write["value"]["future"], .string("preserved"), "An explicit Desktop restore re-pushes its entire saved section")
                return self.accepted(3)
            }
            XCTAssertFalse(engine.hasPendingChanges); XCTAssertFalse(engine.hasParkedVersion)
        }
    }

    func testAnEditDuringAnAcceptedPushStaysQueuedAgainstTheNewServerRevision() async throws {
        try await isolated { _, preferences, engine, memory in
            try await self.hydrate(engine); preferences.change { $0.renamed["discovery-cm-drama"] = "First edit" }
            var sent: JSONValue = .null
            try await engine.synchronize(state: self.state(self.remote, rev: 1), account: "A", profile: self.profile) { request in
                sent = try XCTUnwrap(request["writes"].array.first?["value"])
                preferences.change { $0.renamed["discovery-cm-drama"] = "Second edit" }; return self.accepted(2)
            }
            XCTAssertTrue(engine.hasPendingChanges); XCTAssertEqual(memory.values.values.first?.pending?.baseRev, 2)
            try await engine.synchronize(state: self.state(sent, rev: 2), account: "A", profile: self.profile) { request in
                XCTAssertEqual(request["writes"].array.first?["baseRev"], .integer(2))
                XCTAssertEqual(request["writes"].array.first?["value"]["renamed"]["cm-drama"], .string("Second edit")); return self.accepted(3)
            }
            XCTAssertFalse(engine.hasPendingChanges); XCTAssertEqual(preferences.layout.renamed["discovery-cm-drama"], "Second edit")
        }
    }

    func testRejectedPushParksTheLatestEditAndAdoptsTheServerWithoutDroppingItsNewFields() async throws {
        try await isolated { _, preferences, engine, _ in
            try await self.hydrate(engine); preferences.change { $0.cwTop = true }
            let winner: JSONValue = .object(["renamed": .object(["cm-drama": .string("Desktop winner")]), "future": .integer(42)])
            try await engine.synchronize(state: self.state(self.remote, rev: 1), account: "A", profile: self.profile) { _ in
                preferences.change { $0.renamed["discovery-cm-drama"] = "Latest phone edit" }
                return .object(["results": .array([.object(["ok": .bool(false), "current": .object(["key": .string("one:home"), "rev": .integer(2), "value": winner])])])])
            }
            XCTAssertEqual(preferences.layout.renamed["discovery-cm-drama"], "Desktop winner"); XCTAssertTrue(engine.hasParkedVersion)
            engine.restoreMyVersion(); XCTAssertEqual(preferences.layout.renamed["discovery-cm-drama"], "Latest phone edit"); XCTAssertTrue(preferences.layout.cwTop)
        }
    }

    func testAResponseFromAnOldActivationCannotPublishAfterSwitchingAccountsAndQueuesRemainSeparate() async throws {
        try await isolated { owner, preferences, engine, _ in
            try await self.hydrate(engine); preferences.change { $0.cwTop = true }
            do {
                try await engine.synchronize(state: self.state(self.remote, rev: 1), account: "A", profile: self.profile) { _ in
                    engine.unbind(); preferences.bind(.local(owner: owner))
                    try await engine.synchronize(state: self.state(nil, rev: 0), account: "B", profile: self.profile) { _ in XCTFail("No account B defaults upload"); return .null }
                    return self.accepted(2)
                }
                XCTFail("A response from retired activation must not apply")
            } catch {
                XCTAssertEqual(preferences.scope, .harbor(owner: owner, account: "B", profile: "one", linked: false))
                XCTAssertFalse(preferences.layout.cwTop); XCTAssertFalse(engine.hasPendingChanges)
            }
            engine.unbind()
            try await engine.synchronize(state: self.state(self.remote, rev: 1), account: "A", profile: self.profile) { request in
                XCTAssertEqual(request["writes"].array.first?["value"]["cwTop"], .bool(true)); return self.accepted(2)
            }
            XCTAssertTrue(preferences.layout.cwTop)
        }
    }

    func testAdoptionJournalRecoversAnInterruptedCommitWithoutEchoingServerData() async throws {
        try await isolated { owner, preferences, engine, memory in
            memory.writesBeforeFailure = 1
            do { try await self.hydrate(engine); XCTFail("The second journal write must fail") } catch { }
            XCTAssertNotNil(memory.values.values.first?.adoption)
            XCTAssertEqual(preferences.layout.order, ["discovery-cm-drama", "discovery-cm-comedy"])
            engine.unbind(); memory.writesBeforeFailure = nil
            let reopened = PageCustomization(owner: owner, page: "home"), resumed = HarborPageSync(preferences: reopened, persistence: memory)
            defer { resumed.unbind() }
            try await self.hydrate(resumed)
            XCTAssertNil(memory.values.values.first?.adoption); XCTAssertFalse(resumed.hasPendingChanges)
            XCTAssertEqual(reopened.layout.order, ["discovery-cm-drama", "discovery-cm-comedy"])
        }
    }

    func testMalformedAndRegressedServerDocumentsDoNotMutateOrPublishNativeChoices() async throws {
        try await isolated { _, preferences, engine, _ in
            let before = preferences.layout
            do {
                try await engine.synchronize(state: self.state(.object(["order": .string("bad")]), rev: 1), account: "A", profile: self.profile) { _ in XCTFail("No push for invalid input"); return .null }
                XCTFail("Malformed layout rejected")
            } catch { XCTAssertEqual(preferences.layout, before); XCTAssertFalse(engine.hasPendingChanges) }
            try await self.hydrate(engine); let adopted = preferences.layout
            for revision: Int64 in [0, 1] {
                do {
                    try await engine.synchronize(state: self.state(.object(["order": .array([.string("cm-action")])]), rev: revision), account: "A", profile: self.profile) { _ in XCTFail("No push"); return .null }
                    XCTFail("A lower revision or changed value with same revision is invalid")
                } catch { XCTAssertEqual(preferences.layout, adopted) }
            }
        }
    }

    func testProfileTargetRequiresAnExactSecondaryIDAndOnlyAllowsTheExplicitMigratedPrimaryFallback() throws {
        let primary: JSONValue = .object(["syncId": .string("desktop-primary"), "name": .string("Primary"), "isPrimary": .bool(true)])
        let secondary: JSONValue = .object(["syncId": .string("desktop-secondary"), "name": .string("Secondary")])
        let roster = HarborRoster(rev: 1, value: .object(["profiles": .array([primary, secondary])]))
        XCTAssertEqual(DesktopLayoutProfileTarget(id: "desktop-secondary", primary: false).resolve(in: roster), secondary)
        XCTAssertNil(DesktopLayoutProfileTarget(id: "device-secondary", primary: false).resolve(in: roster))
        XCTAssertEqual(DesktopLayoutProfileTarget(id: "device-primary", primary: true).resolve(in: roster), primary)
        XCTAssertNil(DesktopLayoutProfileTarget(id: "", primary: true).resolve(in: roster))
        XCTAssertEqual(DesktopLayoutProfileTarget(id: "desktop-secondary", primary: true).resolve(in: roster), secondary)
    }
}
