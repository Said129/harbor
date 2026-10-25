import XCTest
@testable import Harbor

@MainActor private final class OwnedProfileIdentities {
    let memory: ActivationMemory
    let context: AppProfileContext
    let primary: String
    let secondary: String
    private var clouds: [HarborProfileSync] = []
    private var keys: Set<String> = []
    init() throws {
        let memory = ActivationMemory(); self.memory = memory; context = memory.context()
        try context.prepare(); primary = try XCTUnwrap(context.profiles.active?.id)
        secondary = try context.profiles.create(name: "Other person").id
        remember()
    }
    var identityOwner: String { HarborProfileIdentity.owner(context.profiles.active!, scope: context.profiles.scope) }
    func cloud(_ transport: @escaping @MainActor (HarborIdentityServer, String, String, JSONValue?, String?) async throws -> JSONValue) throws -> HarborProfileSync {
        let binding = try XCTUnwrap(context.binding), owner = identityOwner
        let profile = ProfilePreferences.forOwner(binding.personalOwner)
        let cloud = HarborProfileSync(owner: owner, profile: profile, serverTransport: transport)
        keys.insert(HarborProfileIdentity.key(owner)); clouds.append(cloud); profile.bindIdentitySync(cloud)
        cloud.bindHouseholdContext(context) { [weak self, weak cloud] in
            guard let self, let cloud, let selected = self.context.profiles.active,
                  HarborProfileIdentity.owner(selected, scope: self.context.profiles.scope) == owner else { return }
            self.bind(cloud)
        }
        bind(cloud); return cloud
    }
    func bind(_ cloud: HarborProfileSync) {
        guard let binding = context.binding, let active = context.profiles.active else { return }
        cloud.bindLayoutOwner(binding.settingsOwner, profileID: active.syncID, primary: active.desktop.isPrimary)
        InterfacePreferences.shared.navigation.bind(.local(owner: binding.settingsOwner))
        StreamingPreferences.forOwner(binding.settingsOwner).bind(.local(owner: binding.settingsOwner))
        for page in ["home", "anime"] { cloud.page(page).preferences.bind(.local(owner: binding.settingsOwner)) }
        cloud.bindCachedLayouts(); remember()
    }
    func remember() {
        guard let binding = context.binding else { return }
        let account: String? = if case .harbor(let account) = context.profiles.scope { account } else { nil }
        keys.insert("watched-by-" + HouseholdProfileScope.hash([binding.identityOwner, account == nil ? "local" : "harbor", account ?? ""]))
        for row in context.profiles.profiles {
            let owner = context.profiles.appearanceOwner(row)
            keys.insert("mobile-profile-" + EBookShelf.hash(owner))
            keys.insert(HarborProfileIdentity.key(HarborProfileIdentity.owner(row, scope: context.profiles.scope)))
            let settings = row.desktop.settingsLinked ? binding.sharedSettingsOwner : owner
            var scopes = [NavigationScope.local(owner: settings)]
            if let account { scopes.append(.harbor(owner: settings, account: account, profile: row.syncID, linked: row.desktop.settingsLinked)) }
            for scope in scopes {
                keys.insert(scope.key); keys.insert("native-streaming-" + EBookShelf.hash(settings))
                keys.insert("scoped-streaming-" + EBookShelf.hash(scope.key))
                keys.insert("navigation-sync-" + EBookShelf.hash(scope.key + "|" + row.syncID + ":nav"))
                let bytes = try! JSONEncoder().encode([scope.key, row.syncID + ":services"])
                keys.insert("streaming-sync-" + EBookShelf.hash(String(decoding: bytes, as: UTF8.self)))
                for page in ["home", "anime"] {
                    keys.formUnion(["page-layout-" + EBookShelf.hash(settings + "|" + page), "page-layout-scope-" + EBookShelf.hash(scope.key + "|" + page),
                        "page-layout-sync-" + EBookShelf.hash(scope.key + "|" + row.syncID + ":" + page)])
                }
            }
        }
    }
    func close() {
        remember(); clouds.forEach { $0.unbindHouseholdContext() }
        for key in keys { try? KeychainStore().remove(key) }
    }
}

@MainActor final class ProfileIdentitySessionTests: XCTestCase {
    private func login(_ id: String) -> JSONValue {
        .object(["token": .string("owned-token-" + id), "refresh": .string("owned-refresh-" + id),
            "user": .object(["id": .string(id), "username": .string("Owned " + id)])])
    }
    private func state(_ document: HarborLayoutDocument) -> JSONValue {
        .object(["rev": .integer(document.rev), "docs": .array([.object(["key": .string(document.key), "rev": .integer(document.rev), "value": document.value])])])
    }
    func testTwoProfilesKeepIndependentLoginAndLogoutRecordsAcrossReopeningDespiteSharedSettingsAndStremio() async throws {
        let h = try OwnedProfileIdentities(); defer { h.close() }
        let serverA = try HarborIdentityServer("https://owned-a.example"), serverB = try HarborIdentityServer("https://owned-b.example")
        let aOwner = h.identityOwner
        let a = try h.cloud { server, path, _, _, _ in
            XCTAssertEqual(server, serverA)
            if path == "/identity/api/login" { return self.login("A") }; throw URLError(.notConnectedToInternet)
        }
        await a.signIn(username: "A", password: "owned-password", server: serverA)
        XCTAssertTrue(a.signedIn); XCTAssertFalse(a.hydrated)
        let savedA = try KeychainStore().read(HarborProfileIdentity.key(aOwner), as: JSONValue.self)
        a.unbindHouseholdContext()
        let selected = try await h.context.select(h.secondary); XCTAssertTrue(selected)
        let bOwner = h.identityOwner
        let b = try h.cloud { server, path, _, _, token in
            XCTAssertEqual(server, serverB)
            if path == "/identity/api/login" { return self.login("B") }
            if path == "/auth/logout" { XCTAssertEqual(token, "owned-token-B"); return .object([:]) }
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertFalse(b.signedIn); await b.signIn(username: "B", password: "owned-password", server: serverB)
        XCTAssertTrue(b.signedIn); XCTAssertNotEqual(aOwner, bOwner)
        await b.signOut(); XCTAssertFalse(b.signedIn)
        XCTAssertEqual(try KeychainStore().read(HarborProfileIdentity.key(aOwner), as: JSONValue.self), savedA)
        b.unbindHouseholdContext()
        let returned = try await h.context.select(h.primary); XCTAssertTrue(returned)
        let reopened = try h.cloud { _, _, _, _, _ in XCTFail("Restoration is a cached read"); return .null }
        XCTAssertEqual(reopened.accountID, serverA.account("A")); XCTAssertEqual(reopened.server, serverA)
    }
    func testAProfileChangedDuringTheStateGETCannotActivateItsOldIdentityOrSendAnyRoster() async throws {
        let h = try OwnedProfileIdentities(); defer { h.close() }
        let before = h.context.profiles.scope; var paths: [String] = []
        let cloud = try h.cloud { _, path, _, _, _ in
            paths.append(path)
            if path == "/identity/api/login" { return self.login("A") }
            let changed = try await h.context.select(h.secondary); XCTAssertTrue(changed)
            return self.state(h.memory.document())
        }
        await cloud.signIn(username: "A", password: "owned-password", server: .community)
        XCTAssertEqual(h.context.profiles.scope, before); XCTAssertNil(h.memory.sessions?.activeHarborAccount)
        XCTAssertEqual(paths, ["/identity/api/login", "/sync/v1/state"]); XCTAssertFalse(cloud.hydrated)
        let secondary = try h.cloud { _, _, _, _, _ in XCTFail("A secondary has no inherited credential"); return .null }
        XCTAssertFalse(secondary.signedIn)
    }
    func testAProfileChangedBeforeA401CannotRefreshOrRotateThePreviousPersonsCredential() async throws {
        let h = try OwnedProfileIdentities(); defer { h.close() }
        var paths: [String] = []
        let cloud = try h.cloud { _, path, _, _, _ in
            paths.append(path)
            if path == "/identity/api/login" { return self.login("A") }
            let changed = try await h.context.select(h.secondary); XCTAssertTrue(changed)
            throw HarborError(code: "http-401")
        }
        await cloud.signIn(username: "A", password: "owned-password", server: .community)
        XCTAssertEqual(paths, ["/identity/api/login", "/sync/v1/state"])
        XCTAssertNil(h.memory.sessions?.activeHarborAccount); XCTAssertFalse(cloud.hydrated)
    }
    func testADetachedCoordinatorCannotSyncOrLogOutThePreviousProfileEvenWhenItsLegacyInstanceIsRetained() async throws {
        let h = try OwnedProfileIdentities(); defer { h.close() }
        var calls = 0
        let cloud = try h.cloud { _, path, _, _, _ in
            calls += 1
            if path == "/identity/api/login" { return self.login("A") }; throw URLError(.notConnectedToInternet)
        }
        await cloud.signIn(username: "A", password: "owned-password", server: .community)
        let owner = h.identityOwner, saved = try KeychainStore().read(HarborProfileIdentity.key(owner), as: JSONValue.self)
        cloud.unbindHouseholdContext(); let previousCalls = calls
        await cloud.sync(); await cloud.signOut(); cloud.requestHouseholdSynchronization()
        XCTAssertEqual(calls, previousCalls); XCTAssertTrue(cloud.signedIn)
        XCTAssertEqual(try KeychainStore().read(HarborProfileIdentity.key(owner), as: JSONValue.self), saved)
    }
    func testSigningOutAndReopeningRetainAllCachedSectionsAndSharedWatchAttributionWithoutResurrectingTheLegacyToken() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        h.set("desktop-primary", "nav", h.navigation("Cached nav")); h.set("desktop-primary", "home", h.page("Cached home"))
        h.set("desktop-primary", "anime", .object(["renamed": .object(["continueWatching": .string("Cached anime")])]))
        h.set("desktop-primary", "services", .object(["netflix": .bool(false)])); try await h.run(h.active())
        let binding = try XCTUnwrap(h.context.binding), active = try XCTUnwrap(h.context.profiles.active)
        let owner = HarborProfileIdentity.owner(active, scope: h.context.profiles.scope), key = HarborProfileIdentity.key(owner)
        let legacyKey = HarborProfileIdentity.key(binding.identityOwner), claim = HarborProfileIdentity.claimKey(binding.identityOwner)
        let raw: JSONValue = .object(["session": .object(["id": .string(h.account), "username": .string("Owned"), "token": .string("retired-owned-token"), "refresh": .string("retired-owned-refresh")])])
        try KeychainStore().write(raw, key: key); try KeychainStore().write(raw, key: legacyKey)
        let watchedKey = "watched-by-" + HouseholdProfileScope.hash([binding.identityOwner, "harbor", h.account])
        var networkCalls = 0
        let cloud = HarborProfileSync(owner: owner, profile: ProfilePreferences.forOwner(binding.personalOwner), transport: { _, _, _, _ in networkCalls += 1; return .null })
        defer { cloud.unbindHouseholdContext(); for owned in [key, legacyKey, claim, watchedKey] { try? KeychainStore().remove(owned) } }
        func bind(_ value: HarborProfileSync) {
            value.bindHouseholdContext(h.context) {}; value.bindLayoutOwner(binding.settingsOwner, profileID: active.syncID, primary: true)
            InterfacePreferences.shared.navigation.bind(.local(owner: binding.settingsOwner)); value.bindCachedLayouts()
        }
        bind(cloud)
        let watcher = try XCTUnwrap(h.context.profiles.profiles.first { $0.syncID == "linked-other" })
        try cloud.watchedBy.record(mediaID: "owned-film", profileID: watcher.id)
        await cloud.signOut(); XCTAssertFalse(cloud.signedIn)
        XCTAssertEqual(cloud.page("home").preferences.layout.renamed["discovery-cm-drama"], "Cached home")
        XCTAssertFalse(try HarborProfileIdentity.migrateLegacy(context: h.context))
        let reopened = HarborProfileSync(owner: owner, profile: ProfilePreferences.forOwner(binding.personalOwner), transport: { _, _, _, _ in networkCalls += 1; return .null })
        defer { reopened.unbindHouseholdContext() }; bind(reopened)
        XCTAssertFalse(reopened.signedIn); XCTAssertEqual(reopened.navigation.preferences.value.renamed["anime"], "Cached nav")
        XCTAssertEqual(reopened.page("anime").preferences.layout.renamed["continueWatching"], "Cached anime")
        XCTAssertFalse(reopened.services.preferences.isEnabled("netflix")); XCTAssertEqual(reopened.watchedBy.account, h.account)
        XCTAssertEqual(reopened.watchedBy.value.watcher(mediaID: "owned-film", activeID: active.id, profiles: h.context.profiles.profiles)?.id, watcher.id)
        await reopened.sync(); XCTAssertEqual(networkCalls, 0)
        XCTAssertEqual(try KeychainStore().read(legacyKey, as: JSONValue.self), raw)
    }
    func testExplicitAuthenticationToAnotherHouseholdKeepsTheInitiatingIdentityPrivateAndDoesNotShareItWithOtherProfiles() async throws {
        let h = try OwnedProfileIdentities(); defer { h.close() }
        let serverA = try HarborIdentityServer("https://owned-a.example"), serverB = try HarborIdentityServer("https://owned-b.example")
        let firstOwner = h.identityOwner
        let a = try h.cloud { _, path, _, _, _ in
            if path == "/identity/api/login" { return self.login("A") }; return self.state(h.memory.document())
        }
        await a.signIn(username: "A", password: "owned-password", server: serverA); await a.sync()
        XCTAssertTrue(a.hydrated); XCTAssertEqual(h.context.profiles.scope, .harbor(account: serverA.account("A")))
        a.unbindHouseholdContext()
        let second = try h.context.profiles.create(name: "Other signed in person")
        let selected = try await h.context.select(second.id); XCTAssertTrue(selected)
        let secondOwner = h.identityOwner
        let b = try h.cloud { _, path, _, _, _ in
            if path == "/identity/api/login" { return self.login("B") }
            return self.state(h.memory.document([h.memory.remote("B-primary"), h.memory.remote("B-other", primary: false)]))
        }
        await b.signIn(username: "B", password: "owned-password", server: serverB); await b.sync()
        XCTAssertTrue(b.hydrated); XCTAssertEqual(h.context.profiles.scope, .harbor(account: serverB.account("B")))
        XCTAssertEqual(h.identityOwner, secondOwner); XCTAssertNotEqual(firstOwner, secondOwner)
        let other = try XCTUnwrap(h.context.profiles.profiles.first { $0.syncID == "B-other" })
        let otherOwner = HarborProfileIdentity.owner(other, scope: h.context.profiles.scope)
        XCTAssertNil(try KeychainStore().read(HarborProfileIdentity.key(otherOwner), as: JSONValue.self))
        let first = try XCTUnwrap(KeychainStore().read(HarborProfileIdentity.key(firstOwner), as: JSONValue.self))
        XCTAssertEqual(first["session"]["id"], .string("A"))
        let wire = String(decoding: try JSONEncoder().encode(h.context.profiles.state.wireValue), as: UTF8.self)
        for secret in ["localIdentityOwner", secondOwner, "owned-token-B", "owned-refresh-B"] { XCTAssertFalse(wire.contains(secret)) }
    }
}
