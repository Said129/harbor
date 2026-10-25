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
        clouds.removeAll()
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
        var documents: [String: [String: HarborLayoutDocument]] = ["A": ["account:profiles": h.memory.document()],
            "B": ["account:profiles": h.memory.document([h.memory.remote("B-primary"), h.memory.remote("B-other", primary: false)])]]
        var pushes: [JSONValue] = []
        func exchange(_ account: String, _ path: String, _ method: String, _ body: JSONValue?, _ token: String?) throws -> JSONValue {
            if path == "/identity/api/login" { XCTAssertEqual(method, "POST"); XCTAssertNil(token); return self.login(account) }
            XCTAssertEqual(token, "owned-token-" + account)
            if path == "/sync/v1/state" {
                XCTAssertEqual(method, "GET")
                let docs = documents[account] ?? [:]
                return .object(["rev": .integer(docs.values.map(\.rev).max() ?? 0), "docs": .array(docs.keys.sorted().compactMap { key in
                    docs[key].map { .object(["key": .string($0.key), "rev": .integer($0.rev), "value": $0.value]) }
                })])
            }
            guard path == "/sync/v1/push", method == "POST" else { XCTFail("Unexpected owned identity request"); throw HarborError(code: "owned-request") }
            let body = try XCTUnwrap(body); pushes.append(body)
            let writes = body["writes"].array; XCTAssertEqual(writes.count, 1)
            let write = try XCTUnwrap(writes.first), key = try XCTUnwrap(write["key"].string)
            let revision = documents[account]?[key]?.rev ?? 0
            XCTAssertEqual(write["baseRev"].numericValue, Double(revision))
            documents[account, default: [:]][key] = .init(key: key, rev: revision + 1, value: write["value"])
            return .object(["results": .array([.object(["key": .string(key), "ok": .bool(true), "rev": .integer(revision + 1)])])])
        }
        let firstOwner = h.identityOwner
        let secondarySyncID = try XCTUnwrap(h.context.profiles.profiles.first { $0.id == h.secondary }).syncID
        let a = try h.cloud { server, path, method, body, token in
            XCTAssertEqual(server, serverA); return try exchange("A", path, method, body, token)
        }
        await a.signIn(username: "A", password: "owned-password", server: serverA); await a.sync()
        XCTAssertTrue(a.hydrated, a.error ?? "Identity A did not hydrate"); XCTAssertEqual(h.context.profiles.scope, .harbor(account: serverA.account("A")))
        XCTAssertTrue(documents["A"]?["account:profiles"]?.value["profiles"].array.contains(where: { $0["syncId"].string == secondarySyncID }) == true,
            "The pre-existing secondary must be acknowledged rather than dropped during first-account activation")
        a.unbindHouseholdContext()
        let second = try h.context.profiles.create(name: "Other signed in person")
        let selected = try await h.context.select(second.id); XCTAssertTrue(selected)
        let secondOwner = h.identityOwner
        let b = try h.cloud { server, path, method, body, token in
            XCTAssertEqual(server, serverB); return try exchange("B", path, method, body, token)
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
        XCTAssertFalse(pushes.isEmpty)
        let uploaded = String(decoding: try JSONEncoder().encode(pushes), as: UTF8.self)
        for secret in ["localIdentityOwner", firstOwner, secondOwner, "owned-token-A", "owned-token-B", "owned-stremio-secret"] { XCTAssertFalse(uploaded.contains(secret)) }
    }
    func testSharedWatchAttributionStaysCurrentAcrossPrivateIdentityCoordinatorsWithoutSharingTheirCredentials() async throws {
        let h = try OwnedHouseholdLayouts(); defer { h.close() }
        let initial = try XCTUnwrap(h.context.binding), primary = try XCTUnwrap(h.context.profiles.active)
        let aOwner = HarborProfileIdentity.owner(primary, scope: h.context.profiles.scope)
        let aKey = HarborProfileIdentity.key(aOwner)
        let watchKey = "watched-by-" + HouseholdProfileScope.hash([initial.identityOwner, "harbor", h.account])
        let credential: JSONValue = .object(["session": .object(["id": .string(h.account), "username": .string("Owned watch account"),
            "token": .string("owned-retired-watch-token"), "refresh": .string("owned-retired-watch-refresh")])])
        try KeychainStore().write(credential, key: aKey)
        defer { for key in [aKey, watchKey] { try? KeychainStore().remove(key) } }
        var calls = 0
        let a = HarborProfileSync(owner: aOwner, profile: ProfilePreferences.forOwner(initial.personalOwner), transport: { _, _, _, _ in calls += 1; return .null })
        func bind(_ value: HarborProfileSync) throws {
            let binding = try XCTUnwrap(h.context.binding), active = try XCTUnwrap(h.context.profiles.active)
            value.bindHouseholdContext(h.context) {}; value.bindLayoutOwner(binding.settingsOwner, profileID: active.syncID, primary: active.desktop.isPrimary)
            InterfacePreferences.shared.navigation.bind(.local(owner: binding.settingsOwner)); value.bindCachedLayouts()
        }
        try bind(a); let first = a.watchedBy
        XCTAssertTrue(a.signedIn); XCTAssertNotNil(first.requestSync)
        a.unbindHouseholdContext(); try await h.select("linked-other")
        let secondary = try XCTUnwrap(h.context.profiles.active), next = try XCTUnwrap(h.context.binding)
        let bOwner = HarborProfileIdentity.owner(secondary, scope: h.context.profiles.scope)
        let b = HarborProfileSync(owner: bOwner, profile: ProfilePreferences.forOwner(next.personalOwner), transport: { _, _, _, _ in calls += 1; return .null })
        defer { a.unbindHouseholdContext(); b.unbindHouseholdContext() }
        try bind(b); let second = b.watchedBy
        XCTAssertTrue(first === second, "The fixed account attribution bucket must not become stale private copies")
        try second.record(mediaID: "owned-shared-watch", profileID: secondary.id)
        await b.sync(); XCTAssertFalse(b.signedIn); XCTAssertEqual(calls, 0)
        b.unbindHouseholdContext(); try await h.select("desktop-primary"); try bind(a)
        XCTAssertEqual(a.watchedBy.value.watcher(mediaID: "owned-shared-watch", activeID: primary.id, profiles: h.context.profiles.profiles)?.id, secondary.id)
        XCTAssertNotEqual(aOwner, bOwner); XCTAssertTrue(a.signedIn); XCTAssertFalse(b.signedIn)
        XCTAssertEqual(try KeychainStore().read(aKey, as: JSONValue.self), credential)
        XCTAssertNil(try KeychainStore().read(HarborProfileIdentity.key(bOwner), as: JSONValue.self))
        await a.sync(); XCTAssertEqual(calls, 0)
    }
}
