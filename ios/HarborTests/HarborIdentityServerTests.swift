import XCTest
@testable import Harbor

@MainActor final class HarborIdentityServerTests: XCTestCase {
    private func key(_ owner: String) -> String { "harbor-identity-" + EBookShelf.hash(owner) }
    private func login() -> JSONValue {
        .object(["token": .string("owned-token"), "refresh": .string("owned-refresh"),
            "user": .object(["id": .string("same-provider-id"), "username": .string("owned-user")])])
    }
    private func state(_ memory: ActivationMemory) -> JSONValue {
        let doc = memory.document()
        return .object(["rev": .integer(doc.rev), "docs": .array([.object(["key": .string(doc.key), "rev": .integer(doc.rev), "value": doc.value])])])
    }
    private func cleanup(_ owner: String, _ cloud: HarborProfileSync) {
        cloud.suspendForProfileChange()
        try? KeychainStore().remove(key(owner)); try? KeychainStore().remove("mobile-profile-" + EBookShelf.hash(owner))
    }
    func testServerOriginsAreCanonicalAndMalformedOrCredentialedOriginsCannotBeRestored() throws {
        XCTAssertEqual(try HarborIdentityServer("  HTTPS://HarborCommunity.Site:443/  "), .community)
        XCTAssertEqual(try HarborIdentityServer("https://owned.example:8443/").base, "https://owned.example:8443")
        for invalid in ["http://owned.example", "https://user:secret@owned.example", "https://owned.example/themes/api", "https://owned.example/?secret=x", "https://owned.example/#x", "https://owned.example:0", "", "https://"] {
            XCTAssertThrowsError(try HarborIdentityServer(invalid))
            XCTAssertThrowsError(try JSONDecoder().decode(HarborIdentityServer.self, from: JSONEncoder().encode(invalid)))
        }
        let encoded = try JSONEncoder().encode(HarborIdentityServer.community)
        XCTAssertEqual(try JSONDecoder().decode(HarborIdentityServer.self, from: encoded), .community)
        XCTAssertEqual(HarborIdentityServer.original.account("same"), "same")
        XCTAssertNotEqual(HarborIdentityServer.community.account("same"), HarborIdentityServer.original.account("same"))
        XCTAssertNotEqual(try HarborIdentityServer("https://owned.example").account("same"), HarborIdentityServer.community.account("same"))
    }
    func testAccountRequestsUseOnlyTheSelectedOriginAndKnownMethods() throws {
        let server = try HarborIdentityServer("https://owned.example:8443")
        let body = JSONValue.object(["password": .string("owned-password")])
        let request = try HTTPClient.harborRequest("/identity/api/login", server: server, method: "POST", body: body)
        XCTAssertEqual(request.url?.absoluteString, "https://owned.example:8443/themes/api/identity/api/login")
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody)), body)
        let sync = try HTTPClient.harborRequest("/sync/v1/state", server: server, token: "owned-token")
        XCTAssertEqual(sync.value(forHTTPHeaderField: "Authorization"), "Bearer owned-token")
        for path in ["/sync/v1/state?url=https://other.example", "//other.example", "/identity/api/../login", "/unknown"] {
            XCTAssertThrowsError(try HTTPClient.harborRequest(path, server: server, token: "owned-token"))
        }
        XCTAssertThrowsError(try HTTPClient.harborRequest("/sync/v1/push", server: server))
        XCTAssertThrowsError(try HTTPClient.harborRequest("/sync/v1/state", server: .original, token: "owned-original-token"))
    }
    func testAnOldSessionNeverContactsTheClosedServerOrTransfersItsPendingAppearanceToTheCommunity() async throws {
        let memory = ActivationMemory(), owner = memory.identity
        let pending = JSONValue.object(["account": .string("same-provider-id"), "syncId": .string("desktop-primary"),
            "version": .string(UUID().uuidString), "fields": .object(["name": .string("Original realm name")])])
        let legacy = JSONValue.object(["session": .object(["id": .string("same-provider-id"), "username": .string("owned-user"),
            "token": .string("owned-original-token"), "refresh": .string("owned-original-refresh")]), "pending": pending])
        try KeychainStore().write(legacy, key: key(owner))
        var requests: [String] = []
        let cloud = HarborProfileSync(owner: owner, profile: ProfilePreferences.forOwner(owner), serverTransport: { server, path, _, _, token in
            XCTAssertEqual(server, .community); XCTAssertNotEqual(token, "owned-original-token")
            requests.append(path)
            if path == "/identity/api/login" { return self.login() }
            XCTAssertEqual(path, "/sync/v1/state"); return self.state(memory)
        })
        defer { cleanup(owner, cloud) }
        XCTAssertTrue(cloud.ready); XCTAssertTrue(cloud.serverRetired)
        XCTAssertEqual(cloud.accountID, "same-provider-id")
        await cloud.sync(); XCTAssertNotNil(cloud.error); XCTAssertTrue(requests.isEmpty)
        await cloud.signOut(); XCTAssertFalse(cloud.signedIn); XCTAssertTrue(requests.isEmpty)
        await cloud.signIn(username: "owned-user", password: "owned-password", server: .community)
        XCTAssertNil(cloud.error); XCTAssertTrue(cloud.hydrated)
        XCTAssertEqual(cloud.accountID, HarborIdentityServer.community.account("same-provider-id"))
        let saved = try XCTUnwrap(KeychainStore().read(key(owner), as: JSONValue.self))
        XCTAssertEqual(saved["parked"]["same-provider-id"], pending); XCTAssertEqual(saved["pending"], .null)
        XCTAssertEqual(requests, ["/identity/api/login", "/sync/v1/state"])
    }
    func testRefreshRetryRestorationAndLogoutKeepTheServerChosenAtLogin() async throws {
        let memory = ActivationMemory(), owner = memory.identity, server = try HarborIdentityServer("https://owned.example")
        var calls: [String] = [], rejected = false
        let transport: @MainActor (HarborIdentityServer, String, String, JSONValue?, String?) async throws -> JSONValue = { actual, path, _, body, token in
            XCTAssertEqual(actual, server); calls.append(path)
            if path == "/identity/api/login" { return self.login() }
            if path == "/identity/api/token/refresh" {
                XCTAssertNil(token); XCTAssertEqual(body?["refresh"].string, "owned-refresh")
                return .object(["token": .string("owned-refreshed-token"), "refresh": .string("owned-rotated-refresh")])
            }
            if path == "/sync/v1/state" {
                if !rejected { rejected = true; throw HarborError(code: "http-401") }
                XCTAssertEqual(token, "owned-refreshed-token"); return self.state(memory)
            }
            XCTAssertEqual(path, "/auth/logout"); XCTAssertEqual(token, "owned-refreshed-token"); return .object([:])
        }
        let preferences = ProfilePreferences.forOwner(owner), cloud = HarborProfileSync(owner: owner, profile: preferences, serverTransport: transport)
        defer { cleanup(owner, cloud) }
        await cloud.signIn(username: "owned-user", password: "owned-password", server: server)
        XCTAssertNil(cloud.error); XCTAssertTrue(cloud.hydrated)
        let restored = HarborProfileSync(owner: owner, profile: preferences, serverTransport: transport)
        defer { restored.suspendForProfileChange() }
        XCTAssertEqual(restored.server, server); await restored.sync(); XCTAssertNil(restored.error)
        await restored.signOut(); XCTAssertFalse(restored.signedIn)
        XCTAssertEqual(calls, ["/identity/api/login", "/sync/v1/state", "/identity/api/token/refresh", "/sync/v1/state", "/sync/v1/state", "/auth/logout"])
    }
    func testEqualProviderIDsOnDifferentServersActivateSeparateHouseholdsAndSourceSessions() async throws {
        let memory = ActivationMemory(), context = memory.context(), owner = memory.identity
        try context.prepare()
        let source = try XCTUnwrap(context.configuration), originalBinding = try XCTUnwrap(context.binding)
        let a = HarborIdentityServer.community, b = try HarborIdentityServer("https://owned.example")
        let cloud = HarborProfileSync(owner: owner, profile: ProfilePreferences.forOwner(owner), serverTransport: { _, path, _, _, _ in
            if path == "/identity/api/login" { return self.login() }
            XCTAssertEqual(path, "/sync/v1/state"); return self.state(memory)
        })
        func bind(_ cloud: HarborProfileSync, _ context: AppProfileContext) {
            guard let active = context.profiles.active, let binding = context.binding else { return }
            cloud.bindLayoutOwner(binding.settingsOwner, profileID: active.syncID, primary: active.desktop.isPrimary)
            InterfacePreferences.shared.navigation.bind(.local(owner: binding.settingsOwner))
            StreamingPreferences.forOwner(binding.settingsOwner).bind(.local(owner: binding.settingsOwner))
            for page in ["home", "anime"] { cloud.page(page).preferences.bind(.local(owner: binding.settingsOwner)) }
        }
        cloud.bindHouseholdContext(context) { [weak cloud, weak context] in
            if let cloud, let context { bind(cloud, context) }
        }
        bind(cloud, context)
        defer { cleanup(owner, cloud) }
        await cloud.signIn(username: "owned-user", password: "owned-password", server: a); await cloud.sync()
        XCTAssertNil(cloud.error); XCTAssertEqual(context.configuration, source)
        let first = try XCTUnwrap(context.binding)
        XCTAssertEqual(first.personalOwner, originalBinding.personalOwner)
        await cloud.signIn(username: "owned-user", password: "owned-password", server: b); await cloud.sync()
        XCTAssertNil(cloud.error); XCTAssertNotEqual(context.binding?.personalOwner, first.personalOwner)
        XCTAssertNil(context.configuration?.account); XCTAssertTrue(context.configuration?.guestAddons.isEmpty == true)
        XCTAssertEqual(context.profiles.scope, .harbor(account: b.account("same-provider-id")))
        await cloud.signIn(username: "owned-user", password: "owned-password", server: a); await cloud.sync()
        XCTAssertNil(cloud.error); XCTAssertEqual(context.binding, first); XCTAssertEqual(context.configuration, source)
        XCTAssertEqual(memory.sessions?.deviceImportAccount, a.account("same-provider-id"))
    }
    func testAnInvalidated401CannotRefreshACredentialFromThePreviousActivation() async throws {
        let owner = "owned-retired-401-" + UUID().uuidString, preferences = ProfilePreferences.forOwner(owner)
        var requests: [String] = [], invalidate: (() -> Void)?
        let cloud = HarborProfileSync(owner: owner, profile: preferences, serverTransport: { _, path, _, _, _ in
            requests.append(path)
            if path == "/identity/api/login" { return self.login() }
            invalidate?(); throw HarborError(code: "http-401")
        })
        defer { invalidate = nil; cleanup(owner, cloud) }
        invalidate = { cloud.suspendForProfileChange() }
        await cloud.signIn(username: "owned-user", password: "owned-password", server: .community)
        XCTAssertEqual(requests, ["/identity/api/login", "/sync/v1/state"])
        XCTAssertFalse(cloud.hydrated)
    }
    func testInvalidStoredServerDataDoesNotFallBackToAWorkingServerOrContactAnyEndpoint() async throws {
        let owner = "owned-invalid-server-" + UUID().uuidString, preferences = ProfilePreferences.forOwner(owner)
        let malformed = JSONValue.object(["session": .object(["id": .string("same-provider-id"), "username": .string("owned-user"),
            "token": .string("owned-token"), "refresh": .string("owned-refresh"), "server": .string("http://owned.example")])])
        try KeychainStore().write(malformed, key: key(owner))
        var calls = 0
        let cloud = HarborProfileSync(owner: owner, profile: preferences, serverTransport: { _, _, _, _, _ in calls += 1; return .null })
        defer { cleanup(owner, cloud) }
        XCTAssertFalse(cloud.ready); XCTAssertNotNil(cloud.error)
        await cloud.sync(); await cloud.signIn(username: "owned-user", password: "owned-password", server: .community)
        XCTAssertEqual(calls, 0); XCTAssertEqual(try KeychainStore().read(key(owner), as: JSONValue.self), malformed)
    }
    func testExplicitLoginToTheRetiredServerFailsBeforeTheTransportReceivesAPassword() async throws {
        let owner = "owned-retired-login-" + UUID().uuidString, preferences = ProfilePreferences.forOwner(owner)
        var calls = 0
        let cloud = HarborProfileSync(owner: owner, profile: preferences, serverTransport: { _, _, _, _, _ in calls += 1; return .null })
        defer { cleanup(owner, cloud) }
        await cloud.signIn(username: "owned-user", password: "owned-password", server: .original)
        XCTAssertEqual(calls, 0); XCTAssertFalse(cloud.signedIn); XCTAssertNotNil(cloud.error)
    }
}
