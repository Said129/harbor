import XCTest
@testable import Harbor

@MainActor private final class EditingGateMemory: HouseholdProfilePersistence {
    var state: HouseholdProfileState?
    var writes = 0
    func readHousehold(_ key: String) throws -> HouseholdProfileState? { state }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws { state = value; writes += 1 }
}
private actor HeldEditingGate: ProfileCredentialChecking {
    private var answer: CheckedContinuation<Bool, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func verifies(_ password: String, credential: DeviceProfileCredential) async throws -> Bool {
        await withCheckedContinuation { answer = $0; started?.resume(); started = nil }
    }
    func waitUntilStarted() async { if answer == nil { await withCheckedContinuation { started = $0 } } }
    func finish() { answer?.resume(returning: true); answer = nil }
}

@MainActor final class ProfileEditingGateTests: XCTestCase {
    func testRealPINAllowsEditingWithoutChangingTheSelectedAccountAndWrongPINNeverUnlocks() async throws {
        let memory = EditingGateMemory(), profiles = HouseholdProfileStore(scope: .local(owner: "editing-gate"), persistence: memory)
        let primary = try profiles.create(name: "Primary"), secondary = try profiles.create(name: "Protected")
        try await profiles.setCredential(secondary.id, password: "4826")
        profiles.reload(); let state = profiles.state, writes = memory.writes
        XCTAssertTrue(profiles.requiresPIN(secondary.id))
        let wrong = try await profiles.verifyForEditing(secondary.id, password: "0000")
        XCTAssertFalse(wrong); XCTAssertTrue(profiles.requiresPIN(secondary.id))
        let right = try await profiles.verifyForEditing(secondary.id, password: "4826")
        XCTAssertTrue(right); XCTAssertFalse(profiles.requiresPIN(secondary.id))
        XCTAssertEqual(profiles.state, state); XCTAssertEqual(memory.writes, writes)
        XCTAssertEqual(profiles.active?.id, primary.id)
        var draft = HouseholdProfileDraft(profile: secondary); draft.name = "Protected edited"
        _ = try await profiles.saveEditor(draft)
        XCTAssertEqual(profiles.active?.id, primary.id)
        let selected = try await profiles.select(secondary.id)
        XCTAssertTrue(selected)
        let denied = try await profiles.verifyForEditing(primary.id, password: "4826")
        XCTAssertFalse(denied, "A secondary profile cannot unlock another editor")
    }
    func testReloadDuringPINVerificationCannotGrantAnEditingUnlock() async throws {
        let memory = EditingGateMemory(), checker = HeldEditingGate()
        let profiles = HouseholdProfileStore(scope: .local(owner: "editing-stale"), persistence: memory, credentials: checker)
        _ = try profiles.create(name: "Primary")
        let protected = try profiles.create(name: "Protected")
        try await profiles.setCredential(protected.id, password: "4826"); profiles.reload()
        let task = Task { try await profiles.verifyForEditing(protected.id, password: "4826") }
        await checker.waitUntilStarted(); profiles.reload(); await checker.finish()
        do { _ = try await task.value; XCTFail("A stale verification cannot unlock") }
        catch let error as HarborError { XCTAssertEqual(error.code, "profile-selection-changed") }
        XCTAssertTrue(profiles.requiresPIN(protected.id)); XCTAssertFalse(profiles.verifying)
    }
}
