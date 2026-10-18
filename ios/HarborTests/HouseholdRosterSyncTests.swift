import XCTest
@testable import Harbor

@MainActor private final class RosterSyncMemory: HouseholdProfilePersistence {
    var value: HouseholdProfileState?
    var failWrites = false
    func readHousehold(_ key: String) throws -> HouseholdProfileState? { value }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws {
        if failWrites { throw HarborError(code: "synthetic-write") }; self.value = value
    }
}

@MainActor final class HouseholdRosterSyncTests: XCTestCase {
    private let account = "synthetic-household"
    private func store(_ memory: RosterSyncMemory) -> HouseholdProfileStore { HouseholdProfileStore(scope: .harbor(account: account), persistence: memory) }
    private func state(_ revision: Int64 = 0, value: JSONValue? = nil) -> JSONValue {
        .object(["rev": .integer(revision), "docs": .array(value.map { [.object(["key": .string(HarborHouseholdSync.key), "rev": .integer(revision), "value": $0])] } ?? [])])
    }
    private func accepted(_ revision: Int64) -> JSONValue {
        .object(["results": .array([.object(["key": .string(HarborHouseholdSync.key), "ok": .bool(true), "rev": .integer(revision)])])])
    }
    func testPullAdoptsTheFullRosterWithoutEchoAndKeepsDeviceCredentials() async throws {
        let memory = RosterSyncMemory(), profiles = store(memory)
        let original = try profiles.create(name: "Original")
        try await profiles.setCredential(original.id, password: "4826")
        let remote = try original.desktop.editing(["name": .string("Remote name")], at: 7)
        let value: JSONValue = .object(["profiles": .array([remote.portable]), "future-roster-field": .bool(true)])
        let sync = HarborHouseholdSync(account: account, profiles: profiles)
        try await sync.synchronize(state: state(3, value: value)) { _ in XCTFail("A pull must not echo the server"); return .null }
        XCTAssertEqual(profiles.profiles.first?.id, original.id)
        XCTAssertEqual(profiles.profiles.first?.desktop.name, "Remote name")
        XCTAssertNotNil(profiles.profiles.first?.credential)
        XCTAssertEqual(profiles.state.wireValue["future-roster-field"], .bool(true))
        XCTAssertFalse(sync.hasPendingChanges)
    }
    func testOnlyAnAuthoritativeMissingDocumentCanSeedAndTheAttemptIsDurableBeforePOST() async throws {
        let memory = RosterSyncMemory(), profiles = store(memory)
        _ = try profiles.create(name: "Local")
        let sync = HarborHouseholdSync(account: account, profiles: profiles)
        var sends = 0
        do { try await sync.synchronize(state: .object(["docs": .array([])])) { _ in sends += 1; return self.accepted(1) }; XCTFail("Malformed full state must fail") } catch {}
        XCTAssertEqual(sends, 0); XCTAssertNil(profiles.state.synchronizationAccount)
        try await sync.synchronize(state: state()) { body in
            sends += 1
            XCTAssertNotNil(memory.value?.rosterAttempt)
            XCTAssertEqual(body["writes"].array.first?["key"], .string(HarborHouseholdSync.key))
            XCTAssertEqual(body["writes"].array.first?["baseRev"], .integer(0))
            XCTAssertEqual(body["writes"].array.first?["value"]["profiles"].array.first?["passwordHash"], .null)
            return self.accepted(1)
        }
        XCTAssertEqual(sends, 1); XCTAssertNil(profiles.state.rosterAttempt); XCTAssertEqual(profiles.state.serverRevision, 1)
    }
    func testAnUncertainAcceptedAttemptIsRecognizedAfterRestartWithoutAnotherPOST() async throws {
        let memory = RosterSyncMemory(), profiles = store(memory)
        _ = try profiles.create(name: "Local")
        let sync = HarborHouseholdSync(account: account, profiles: profiles)
        do { try await sync.synchronize(state: state()) { _ in throw URLError(.networkConnectionLost) }; XCTFail("Lost response must be reported") } catch {}
        let sent = try XCTUnwrap(memory.value?.rosterAttempt)
        memory.value = try JSONDecoder().decode(HouseholdProfileState.self, from: JSONEncoder().encode(try XCTUnwrap(memory.value)))
        let restart = store(memory), recovered = HarborHouseholdSync(account: account, profiles: restart)
        try await recovered.synchronize(state: state(1, value: try JSONValue.encoded(sent.value))) { _ in XCTFail("Do not repeat an accepted write"); return .null }
        XCTAssertEqual(restart.state.serverRevision, 1); XCTAssertNil(restart.state.rosterAttempt); XCTAssertFalse(recovered.hasPendingChanges)
    }
    func testIntegralJSONNumbersKeepTheirMeaningAcrossLocalEditsStorageAndServerReplies() async throws {
        let memory = RosterSyncMemory(), profiles = store(memory)
        let original = try profiles.create(name: "Original")
        let edited = try original.desktop.editing(["name": .string("Updated")], at: 7)
        XCTAssertEqual(edited.raw["updatedAt"], .integer(7))
        let document = try DesktopHouseholdRoster(.object(["profiles": .array([edited.portable]),
            "future-numeric-field": .object(["count": .number(12), "fraction": .number(1.25)])]))
        XCTAssertEqual(document.raw["future-numeric-field"]["count"], .integer(12))
        XCTAssertEqual(document.raw["future-numeric-field"]["fraction"], .number(1.25))
        try profiles.bindSynchronization(account: account); try profiles.adopt(document, revision: 3)
        memory.value = try JSONDecoder().decode(HouseholdProfileState.self, from: JSONEncoder().encode(try XCTUnwrap(memory.value)))
        let restart = store(memory)
        let sync = HarborHouseholdSync(account: account, profiles: restart)
        try await sync.synchronize(state: state(3, value: try JSONValue.encoded(document.raw))) { _ in XCTFail("Equivalent JSON must not echo"); return .null }
        XCTAssertFalse(sync.hasPendingChanges)
        XCTAssertEqual(restart.profiles.first?.desktop.name, "Updated")
    }
    func testAnEditDuringAcknowledgementRemainsDifferentAndUploadsAtTheAcceptedRevision() async throws {
        let memory = RosterSyncMemory(), profiles = store(memory)
        let original = try profiles.create(name: "Before")
        let sync = HarborHouseholdSync(account: account, profiles: profiles)
        var sent: JSONValue = .null
        try await sync.synchronize(state: state()) { body in
            sent = body["writes"].array[0]["value"]
            try profiles.edit(original.id, fields: ["name": .string("Edited during POST")])
            return self.accepted(1)
        }
        XCTAssertTrue(sync.hasPendingChanges); XCTAssertEqual(profiles.profiles.first?.desktop.name, "Edited during POST")
        try await sync.synchronize(state: state(1, value: sent)) { body in
            XCTAssertEqual(body["writes"].array[0]["baseRev"], .integer(1))
            XCTAssertEqual(body["writes"].array[0]["value"]["profiles"].array[0]["name"], .string("Edited during POST"))
            return self.accepted(2)
        }
        XCTAssertFalse(sync.hasPendingChanges)
    }
    func testConcurrentSeedingRetainsMissingLocalProfilesButKeepsOneServerPrimary() async throws {
        let memory = RosterSyncMemory(), profiles = store(memory)
        let local = try profiles.create(name: "Local primary")
        var remoteFields = local.desktop.raw.objectValue
        remoteFields["syncId"] = .string("s_remote"); remoteFields["name"] = .string("Server primary")
        let winner: JSONValue = .object(["profiles": .array([.object(remoteFields)])])
        let sync = HarborHouseholdSync(account: account, profiles: profiles)
        try await sync.synchronize(state: state()) { _ in
            .object(["results": .array([.object(["ok": .bool(false), "current": .object(["key": .string(HarborHouseholdSync.key), "rev": .integer(1), "value": winner])])])])
        }
        XCTAssertEqual(profiles.profiles.count, 2)
        XCTAssertEqual(profiles.profiles.filter { $0.desktop.isPrimary }.map(\.syncID), ["s_remote"])
        XCTAssertEqual(profiles.profiles.first { $0.id == local.id }?.desktop.name, "Local primary")
        XCTAssertTrue(sync.hasPendingChanges)
    }
    func testWrongAccountAndLateRepliesCannotAcknowledgeTheCurrentJournal() async throws {
        let memory = RosterSyncMemory(), profiles = store(memory)
        _ = try profiles.create(name: "Local")
        let wrong = HarborHouseholdSync(account: "another-household", profiles: profiles)
        do { try await wrong.synchronize(state: state()) { _ in XCTFail("Wrong account must not POST"); return .null }; XCTFail("Wrong account must fail") } catch {}
        XCTAssertNil(profiles.state.synchronizationAccount)
        let sync = HarborHouseholdSync(account: account, profiles: profiles)
        do { try await sync.synchronize(state: state()) { _ in sync.invalidate(); return self.accepted(1) }; XCTFail("Late reply must fail") } catch {}
        XCTAssertEqual(profiles.state.serverRevision, 0); XCTAssertNotNil(profiles.state.rosterAttempt)
    }
    func testRegressingOrSameRevisionChangedDocumentsKeepTheCurrentRoster() async throws {
        let memory = RosterSyncMemory(), profiles = store(memory)
        let local = try profiles.create(name: "Known")
        let value = profiles.state.wireValue
        let sync = HarborHouseholdSync(account: account, profiles: profiles)
        try await sync.synchronize(state: state(3, value: value)) { _ in XCTFail("No echo"); return .null }
        let before = profiles.state
        for bad in [state(2, value: value), state(3, value: .object(["profiles": .array([try local.desktop.editing(["name": .string("Forged")], at: 99).portable])]))] {
            do { try await sync.synchronize(state: bad) { _ in XCTFail("Bad document must not POST"); return .null }; XCTFail("Bad revision must fail") } catch {}
            XCTAssertEqual(profiles.state, before)
        }
    }
    func testFailedQueueWritesNeverSendAndFailedAcknowledgementsRemainRecoverable() async throws {
        let memory = RosterSyncMemory(), profiles = store(memory)
        _ = try profiles.create(name: "Local")
        try profiles.bindSynchronization(account: account); try profiles.noteMissingServerRoster(account: account)
        let sync = HarborHouseholdSync(account: account, profiles: profiles)
        memory.failWrites = true
        do { try await sync.synchronize(state: state()) { _ in XCTFail("Journal must persist first"); return .null }; XCTFail("Failed save must fail") } catch {}
        XCTAssertNil(profiles.state.rosterAttempt)
        memory.failWrites = false
        do { try await sync.synchronize(state: state()) { _ in memory.failWrites = true; return self.accepted(1) }; XCTFail("Failed acknowledgement save must fail") } catch {}
        let sent = try XCTUnwrap(memory.value?.rosterAttempt)
        memory.failWrites = false
        let restart = store(memory), recovered = HarborHouseholdSync(account: account, profiles: restart)
        try await recovered.synchronize(state: state(1, value: sent.value)) { _ in XCTFail("Do not repeat accepted write after a disk failure"); return .null }
        XCTAssertFalse(recovered.hasPendingChanges)
    }
}
