import XCTest
@testable import Harbor

@MainActor private final class EditorProfileMemory: HouseholdProfilePersistence {
    var value: HouseholdProfileState?
    var writes = 0
    var failWrites = false
    func readHousehold(_ key: String) throws -> HouseholdProfileState? { value }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws {
        if failWrites { throw HarborError(code: "synthetic-editor-write") }
        self.value = value; writes += 1
    }
}
private actor HeldEditorCredential: ProfileCredentialDeriving {
    private var answer: CheckedContinuation<DeviceProfileCredential, Error>?
    private var started: CheckedContinuation<Void, Never>?
    func derive(_ password: String) async throws -> DeviceProfileCredential {
        try await withCheckedThrowingContinuation { continuation in answer = continuation; started?.resume(); started = nil }
    }
    func waitUntilStarted() async { if answer == nil { await withCheckedContinuation { started = $0 } } }
    func complete() {
        answer?.resume(returning: DeviceProfileCredential(version: 1, salt: Data(repeating: 1, count: 32), rounds: 600_000, digest: Data(repeating: 2, count: 32)))
        answer = nil
    }
}

@MainActor final class ProfileEditorTransactionTests: XCTestCase {
    private func store(_ memory: EditorProfileMemory, derivation: any ProfileCredentialDeriving = DeviceProfileCredentialDeriver()) -> HouseholdProfileStore {
        HouseholdProfileStore(scope: .local(owner: "synthetic-editor"), persistence: memory, derivation: derivation)
    }
    func testCreationCommitsSettingsBothLocksAndSelectionTogetherWithoutUnlockingTheChildExit() async throws {
        let memory = EditorProfileMemory(), profiles = store(memory)
        let primary = try profiles.create(name: "Primary")
        let writes = memory.writes
        var draft = HouseholdProfileDraft(name: "  Child  ", sharingWith: primary.id)
        draft.kid = .object(["age": .integer(7), "curfewMinutes": .integer(60)])
        draft.lockedTabs = .object(["sports": .bool(true)])
        draft.settingsLinked = false; draft.pin = .set("4826"); draft.parentPIN = .set("7315")
        let child = try await profiles.saveEditor(draft)
        XCTAssertEqual(memory.writes, writes + 1); XCTAssertEqual(profiles.state.selectedID, child.id)
        XCTAssertEqual(child.desktop.name, "Child"); XCTAssertEqual(child.shareStremioWith, primary.id)
        XCTAssertFalse(child.desktop.settingsLinked); XCTAssertEqual(child.desktop.curfewMinutes, 60)
        XCTAssertNotNil(child.credential); XCTAssertNotNil(child.parentCredential)
        XCTAssertEqual(profiles.active?.id, child.id, "The creator already supplied the new profile PIN")
        let escaped = try await profiles.select(primary.id)
        XCTAssertFalse(escaped, "Creating a child's parent PIN must not leave its exit unlocked")
        let withParent = try await profiles.select(primary.id, parentPassword: "7315")
        XCTAssertTrue(withParent)
        let wire = try XCTUnwrap(profiles.state.wireValue["profiles"].array.first { $0["syncId"].string == child.syncID })
        XCTAssertEqual(wire["passwordHash"], .null); XCTAssertEqual(wire["kid"]["parentPinHash"], .null)
    }
    func testFailedCreationWriteCannotLeaveAnUnprotectedProfileOrChangeSelection() async throws {
        let memory = EditorProfileMemory(), profiles = store(memory)
        _ = try profiles.create(name: "Primary")
        let previous = profiles.state, writes = memory.writes
        memory.failWrites = true
        var draft = HouseholdProfileDraft(name: "Protected"); draft.pin = .set("4826")
        do { _ = try await profiles.saveEditor(draft); XCTFail("A failed atomic save must fail") } catch {}
        XCTAssertEqual(profiles.state, previous); XCTAssertEqual(memory.value, previous)
        XCTAssertEqual(memory.writes, writes); XCTAssertFalse(profiles.verifying)
    }
    func testAProfileChangeWhileDerivingThePINCannotCommitTheOldEditor() async throws {
        let memory = EditorProfileMemory(), held = HeldEditorCredential(), profiles = store(memory, derivation: held)
        _ = try profiles.create(name: "Primary")
        let previous = profiles.state
        var draft = HouseholdProfileDraft(name: "Do not create after reload"); draft.pin = .set("4826")
        let submitted = draft
        let save = Task { try await profiles.saveEditor(submitted) }
        await held.waitUntilStarted(); XCTAssertTrue(profiles.verifying)
        profiles.reload(); await held.complete()
        do { _ = try await save.value; XCTFail("The old editor must be invalidated") }
        catch let error as HarborError { XCTAssertEqual(error.code, "profile-editor-changed") }
        XCTAssertEqual(profiles.state, previous); XCTAssertFalse(profiles.verifying)
    }
    func testSecondaryCanEditItsIdentityButCannotEditOthersOrAdvancedOptions() async throws {
        let memory = EditorProfileMemory(), profiles = store(memory)
        let primary = try profiles.create(name: "Primary"), secondary = try profiles.create(name: "Secondary")
        _ = try await profiles.select(secondary.id)
        var own = HouseholdProfileDraft(profile: secondary); own.name = "My name"; own.color = "#a78bfa"
        let renamed = try await profiles.saveEditor(own)
        XCTAssertEqual(renamed.desktop.name, "My name")
        var other = HouseholdProfileDraft(profile: primary); other.name = "Cannot rename someone else"
        do { _ = try await profiles.saveEditor(other); XCTFail("Only primary manages another profile") } catch {}
        var advanced = HouseholdProfileDraft(profile: renamed); advanced.settingsLinked = false
        do { _ = try await profiles.saveEditor(advanced); XCTFail("Advanced options require primary") } catch {}
        advanced = HouseholdProfileDraft(profile: renamed); advanced.pin = .set("4826")
        do { _ = try await profiles.saveEditor(advanced); XCTFail("An existing secondary's security requires primary") } catch {}
        XCTAssertEqual(profiles.profiles.first { $0.id == primary.id }?.desktop.name, "Primary")
        XCTAssertTrue(profiles.profiles.first { $0.id == secondary.id }!.desktop.settingsLinked)
    }
    func testAStaleEditorCannotOverwriteAnIncomingDesktopEdit() async throws {
        let memory = EditorProfileMemory(), profiles = store(memory)
        let primary = try profiles.create(name: "Before")
        var draft = HouseholdProfileDraft(profile: primary); draft.name = "Stale local form"
        let changed = try primary.desktop.editing(["name": .string("Changed on Desktop")], at: 25)
        try profiles.adopt(DesktopHouseholdRoster(.object(["profiles": .array([changed.portable])])), revision: 1)
        do { _ = try await profiles.saveEditor(draft); XCTFail("A changed snapshot must be reopened") }
        catch let error as HarborError { XCTAssertEqual(error.code, "profile-editor-changed") }
        XCTAssertEqual(profiles.active?.desktop.name, "Changed on Desktop")
    }
    func testNoOpKeepsUnknownFieldsAndTimestampAndInvalidFormsNeverWrite() async throws {
        let memory = EditorProfileMemory(), profiles = store(memory)
        let primary = try profiles.create(name: "Primary")
        var fields = primary.desktop.raw.objectValue; fields["future-field"] = .object(["keep": .integer(9)])
        try profiles.adopt(DesktopHouseholdRoster(.object(["profiles": .array([.object(fields)])])), revision: 4)
        let before = try XCTUnwrap(profiles.active), writes = memory.writes
        let unchanged = try await profiles.saveEditor(HouseholdProfileDraft(profile: before))
        XCTAssertEqual(unchanged, before); XCTAssertEqual(memory.writes, writes)
        var invalid = HouseholdProfileDraft(profile: before); invalid.name = "  "
        do { _ = try await profiles.saveEditor(invalid); XCTFail("Blank names must fail") } catch {}
        invalid = HouseholdProfileDraft(profile: before); invalid.pin = .set("１２３４")
        do { _ = try await profiles.saveEditor(invalid); XCTFail("A PIN requires four ASCII digits") } catch {}
        invalid = HouseholdProfileDraft(profile: before); invalid.kid = .object(["age": .integer(7)])
        do { _ = try await profiles.saveEditor(invalid); XCTFail("Primary cannot be a child") } catch {}
        XCTAssertEqual(memory.writes, writes); XCTAssertEqual(profiles.active?.desktop.raw["future-field"]["keep"], .integer(9))
    }
}
