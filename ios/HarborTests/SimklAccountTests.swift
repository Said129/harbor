import XCTest
@testable import Harbor

@MainActor private final class OwnedSimklAccountMemory: SimklAccountPersistence {
    var sessions: [String: SimklSession] = [:]
    var fail = false
    private(set) var writes = 0
    func readSimklSession(owner: String) throws -> SimklSession? { sessions[owner] }
    func writeSimklSession(_ session: SimklSession?, owner: String) throws {
        if fail { throw HarborError(code: "owned-simkl-write") }; sessions[owner] = session; writes += 1
    }
}
@MainActor private final class OwnedSimklActiveProfile { var valid = true }
private actor OwnedSimklHeldAuthorization {
    private(set) var started = false
    private var continuation: CheckedContinuation<SimklReply, Never>?
    func send(_ request: URLRequest) async throws -> SimklReply {
        if request.url?.path == "/oauth/pin" { return .init(status: 200, data: Data(#"{"user_code":"OWNED-123","expires_in":600,"interval":5}"#.utf8)) }
        guard request.url?.path == "/oauth/pin/OWNED-123" else { throw HarborError(code: "owned-unexpected-auth-request") }
        started = true; return await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume(returning: .init(status: 200, data: Data(#"{"result":"OK","access_token":"owned-cancelled-token"}"#.utf8))); continuation = nil
    }
}

@MainActor final class SimklAccountTests: XCTestCase {
    func testDeviceCodeUsesOnlyTheFixedProviderOriginAndProfileSessionWritesAreDurableBeforePublication() throws {
        let pin = try SimklPin(.object(["user_code": .string("OWNED-123"), "verification_url": .string("https://other.invalid/collect"), "expires_in": .integer(600), "interval": .integer(5)]))
        XCTAssertEqual(pin.verificationURL.absoluteString, "https://simkl.com/pin/OWNED-123")
        XCTAssertThrowsError(try SimklEndpoint.poll("x/other?token=owned").request())
        XCTAssertThrowsError(try SimklEndpoint.settings.request(token: "x\r\nInjected: value"))
        let memory = OwnedSimklAccountMemory(), first = SimklAccountStore(owner: "first", persistence: memory), second = SimklAccountStore(owner: "second", persistence: memory)
        try first.load(); try second.load(); XCTAssertNil(second.session)
        let session = SimklSession(accessToken: "owned-personal-token", username: "Owned")
        try first.set(session); memory.fail = true
        XCTAssertThrowsError(try first.set(nil)); XCTAssertEqual(first.session, session)
        memory.fail = false; try second.set(SimklSession(accessToken: "owned-second-token"))
        let reopened = SimklAccountStore(owner: "first", persistence: memory); try reopened.load(); XCTAssertEqual(reopened.session, session)
        try first.set(nil); XCTAssertNil(memory.sessions["first"]); XCTAssertNotNil(memory.sessions["second"])
        XCTAssertFalse(ProfileSettingsStore.keys.contains("harbor.simkl.session.v1"))
    }
    func testActualKeychainRecordsKeepTheTwoProfileTokensSeparateAndDoNotPutThemInDefaults() throws {
        let persistence = KeychainSimklAccount(), owner = "owned-simkl-" + UUID().uuidString, other = "owned-simkl-other-" + UUID().uuidString
        defer { try? persistence.writeSimklSession(nil, owner: owner); try? persistence.writeSimklSession(nil, owner: other) }
        let session = SimklSession(accessToken: "owned-keychain-" + UUID().uuidString)
        try persistence.writeSimklSession(session, owner: owner)
        XCTAssertEqual(try persistence.readSimklSession(owner: owner), session); XCTAssertNil(try persistence.readSimklSession(owner: other))
        XCTAssertFalse(String(describing: UserDefaults.standard.dictionaryRepresentation()).contains(session.accessToken))
        try persistence.writeSimklSession(nil, owner: owner); XCTAssertNil(try persistence.readSimklSession(owner: owner))
    }
    func testPINPollAndUsernameAuthorizationPersistTheGrantedSessionThenDisconnectOnlyThatProfile() async throws {
        let clock = OwnedSimklClock(), memory = OwnedSimklAccountMemory()
        let replies = OwnedSimklReplies([
            .init(status: 200, data: Data(#"{"user_code":"OWNED-123","expires_in":600,"interval":5}"#.utf8)),
            .init(status: 200, data: Data(#"{"result":"OK","access_token":"owned-granted-token"}"#.utf8)),
            .init(status: 200, data: Data(#"{"user":{"name":"Owned person"}}"#.utf8))], clock: clock)
        let client = SimklClient(transport: { try await replies.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() }, random: { 0 })
        let store = SimklAccountStore(owner: "owned-profile", persistence: memory)
        let model = SimklAccountModel(store: store, client: client, active: { true }, sleep: { clock.advance($0) }, now: { clock.now() })
        model.load(); await model.begin()
        XCTAssertEqual(store.session?.username, "Owned person"); XCTAssertEqual(memory.sessions[store.owner]?.accessToken, "owned-granted-token")
        XCTAssertFalse(model.busy); XCTAssertNil(model.pin); XCTAssertNil(model.error)
        let sent = await replies.requests; XCTAssertEqual(sent.map { $0.0.url!.path }, ["/oauth/pin", "/oauth/pin/OWNED-123", "/users/settings"])
        XCTAssertNil(sent[0].0.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(sent[1].0.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(sent[2].0.value(forHTTPHeaderField: "Authorization"), "Bearer owned-granted-token")
        model.disconnect(); XCTAssertNil(store.session); XCTAssertNil(memory.sessions[store.owner])
    }
    func testCancelOrProfileSwitchDropsALateGrantedTokenBeforeItCanReachTheKeychain() async throws {
        for changeProfile in [false, true] {
            let memory = OwnedSimklAccountMemory(), held = OwnedSimklHeldAuthorization(), clock = OwnedSimklClock()
            let client = SimklClient(transport: { try await held.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
            let active = OwnedSimklActiveProfile()
            let store = SimklAccountStore(owner: "owned-retired-profile", persistence: memory)
            let model = SimklAccountModel(store: store, client: client, active: { active.valid }, now: { clock.now() })
            model.load(); let task = Task { await model.begin() }
            for _ in 0..<100 { if await held.started { break }; try await Task.sleep(for: .milliseconds(10)) }
            let started = await held.started; XCTAssertTrue(started)
            if changeProfile { active.valid = false } else { model.cancel() }
            await held.release(); await task.value
            XCTAssertNil(store.session); XCTAssertEqual(memory.writes, 0); XCTAssertNil(memory.sessions[store.owner])
        }
    }
    func testPendingCodesExpireAtTheProviderDeadlineWithoutSavingOrContinuingToPoll() async throws {
        let memory = OwnedSimklAccountMemory(), clock = OwnedSimklClock()
        let replies = OwnedSimklReplies([
            .init(status: 200, data: Data(#"{"user_code":"OWNED","expires_in":2,"interval":1}"#.utf8)),
            .init(status: 200, data: Data(#"{"result":"PENDING"}"#.utf8)), .init(status: 200, data: Data(#"{"result":"PENDING"}"#.utf8))], clock: clock)
        let client = SimklClient(transport: { try await replies.send($0) }, sleep: { clock.advance($0) }, now: { clock.now() })
        let store = SimklAccountStore(owner: "owned-expiry", persistence: memory)
        let model = SimklAccountModel(store: store, client: client, active: { true }, sleep: { clock.advance($0) }, now: { clock.now() })
        model.load(); await model.begin()
        XCTAssertEqual(model.error, "Code expired. Try again."); XCTAssertFalse(model.busy); XCTAssertNil(store.session)
        let sent = await replies.requests; XCTAssertEqual(sent.count, 3); XCTAssertEqual(memory.writes, 0)
    }
}
