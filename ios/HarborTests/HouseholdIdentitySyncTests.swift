import XCTest
@testable import Harbor

@MainActor private final class OwnedHarborIdentityServer {
    var revision: Int64 = 2
    var docs: [String: HarborLayoutDocument] = [:]
    var pushes: [JSONValue] = []
    var failGET = false
    var beforeGET: (() -> Void)?
    func request(_ path: String, _ method: String, _ body: JSONValue?, _ token: String?) async throws -> JSONValue {
        if path == "/identity/api/login" {
            XCTAssertEqual(method, "POST"); XCTAssertNil(token)
            return .object(["token": .string("owned-harbor-token"), "refresh": .string("owned-harbor-refresh"),
                "user": .object(["id": .string("A"), "username": .string("owned-account")])])
        }
        XCTAssertEqual(token, "owned-harbor-token")
        if path == "/sync/v1/state" {
            beforeGET?()
            if failGET { throw URLError(.notConnectedToInternet) }
            return .object(["rev": .integer(revision), "docs": .array(docs.keys.sorted().compactMap { key in docs[key].map {
                .object(["key": .string($0.key), "rev": .integer($0.rev), "value": $0.value])
            } })])
        }
        if path == "/sync/v1/push" {
            let body = try XCTUnwrap(body); pushes.append(body)
            let serialized = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
            for secret in ["owned-stremio-secret", "authKey", "localDataOwner", "localProgressOwner", "private-record", "credential"] { XCTAssertFalse(serialized.contains(secret)) }
            let writes = body["writes"].array; XCTAssertEqual(writes.count, 1)
            let write = try XCTUnwrap(writes.first), key = try XCTUnwrap(write["key"].string)
            XCTAssertEqual(write["baseRev"].numericValue, Double(docs[key]?.rev ?? 0))
            revision += 1; docs[key] = HarborLayoutDocument(key: key, rev: revision, value: write["value"])
            return .object(["results": .array([.object(["key": .string(key), "ok": .bool(true), "rev": .integer(revision)])])])
        }
        if path == "/auth/logout" || path == "/social/me/profile" { return .object([:]) }
        XCTFail("Unexpected owned request: " + path); throw HarborError(code: "owned-request")
    }
}

@MainActor final class HouseholdIdentitySyncTests: XCTestCase {
    private static func bindSurface(_ cloud: HarborProfileSync, context: AppProfileContext) {
        guard let binding = context.binding, let active = context.profiles.active else { return }
        cloud.bindLayoutOwner(binding.settingsOwner, profileID: active.syncID, primary: active.desktop.isPrimary)
        InterfacePreferences.shared.navigation.bind(.local(owner: binding.settingsOwner))
        StreamingPreferences.forOwner(binding.settingsOwner).bind(.local(owner: binding.settingsOwner))
        for page in ["home", "anime"] { cloud.page(page).preferences.bind(.local(owner: binding.settingsOwner)) }
    }
    private func withCloud(_ body: @MainActor (ActivationMemory, AppProfileContext, OwnedHarborIdentityServer, HarborProfileSync) async throws -> Void) async throws {
        let memory = ActivationMemory(), context = memory.context(), server = OwnedHarborIdentityServer()
        try context.prepare()
        let preferences = ProfilePreferences.forOwner(memory.identity)
        let cloud = HarborProfileSync(owner: memory.identity, profile: preferences, transport: { try await server.request($0, $1, $2, $3) })
        cloud.bindHouseholdContext(context) { [weak cloud, weak context] in
            if let cloud, let context { Self.bindSurface(cloud, context: context) }
        }
        Self.bindSurface(cloud, context: context)
        defer {
            server.beforeGET = nil
            cloud.suspendForProfileChange()
            try? KeychainStore().remove("harbor-identity-" + EBookShelf.hash(memory.identity))
            try? KeychainStore().remove("mobile-profile-" + EBookShelf.hash(memory.identity))
        }
        try await body(memory, context, server, cloud)
    }
    func testRealSignInHydratesTheFullRosterAndEditsCreationAndTombstonesUseTheSameAuthenticatedWriter() async throws {
        try await withCloud { memory, context, server, cloud in
            server.docs["account:profiles"] = memory.document([memory.remote(), memory.remote("desktop-second", primary: false)])
            await cloud.signIn(username: "owned-account", password: "owned-password", server: .community); await cloud.sync()
            XCTAssertTrue(cloud.hydrated); XCTAssertNil(cloud.error)
            XCTAssertEqual(context.profiles.profiles.count, 2); XCTAssertEqual(context.profiles.active?.syncID, "desktop-primary")
            XCTAssertTrue(server.pushes.isEmpty, "An identical authenticated pull cannot echo the roster")
            let id = try XCTUnwrap(context.profiles.active?.id)
            try context.profiles.edit(id, fields: ["name": .string("Changed on mobile")])
            await cloud.sync()
            XCTAssertEqual(server.docs["account:profiles"]?.value["profiles"].array.first?["name"].string, "Changed on mobile")
            let created = try context.profiles.create(name: "Mobile person")
            await cloud.sync()
            XCTAssertTrue(server.docs["account:profiles"]?.value["profiles"].array.contains(where: { $0["syncId"].string == created.syncID }) == true)
            try context.profiles.remove(created.id); await cloud.sync()
            let deleted = server.docs["account:profiles"]?.value["profiles"].array.first { $0["syncId"].string == created.syncID }
            XCTAssertNotNil(deleted); XCTAssertNotEqual(deleted?["deletedAt"], .null)
            XCTAssertFalse(cloud.hasPendingChanges)
        }
    }
    func testAnAuthoritativelyEmptyAccountSeedsTheExistingDeviceProfileWithoutUploadingPrivateState() async throws {
        try await withCloud { _, context, server, cloud in
            let before = try XCTUnwrap(context.binding)
            await cloud.signIn(username: "owned-account", password: "owned-password", server: .community); await cloud.sync()
            XCTAssertEqual(context.profiles.active?.id, before.profileID)
            XCTAssertEqual(context.binding?.personalOwner, before.personalOwner)
            XCTAssertEqual(server.pushes.count, 1)
            XCTAssertEqual(server.pushes.first?["writes"].array.first?["key"].string, "account:profiles")
            XCTAssertEqual(server.pushes.first?["writes"].array.first?["baseRev"].numericValue, 0)
            XCTAssertTrue(cloud.hydrated); XCTAssertNil(cloud.error)
        }
    }
    func testAnUnreachableStateGETCannotActivateAHouseholdOrUploadTheDeviceRoster() async throws {
        try await withCloud { memory, context, server, cloud in
            let before = context.profiles.scope
            server.failGET = true
            await cloud.signIn(username: "owned-account", password: "owned-password", server: .community)
            XCTAssertEqual(context.profiles.scope, before); XCTAssertTrue(context.ready)
            XCTAssertNil(memory.sessions?.activeHarborAccount); XCTAssertNil(memory.sessions?.deviceImportAccount)
            XCTAssertTrue(server.pushes.isEmpty); XCTAssertFalse(cloud.hydrated); XCTAssertNotNil(cloud.error)
        }
    }
    func testAProfileGenerationRetiredDuringGETCannotActivateTheLateAccountResponse() async throws {
        try await withCloud { memory, context, server, cloud in
            let before = context.profiles.scope
            server.docs["account:profiles"] = memory.document()
            server.beforeGET = { cloud.suspendForProfileChange() }
            await cloud.signIn(username: "owned-account", password: "owned-password", server: .community)
            XCTAssertEqual(context.profiles.scope, before)
            XCTAssertNil(memory.sessions?.activeHarborAccount); XCTAssertNil(memory.sessions?.deviceImportAccount)
            XCTAssertTrue(server.pushes.isEmpty); XCTAssertFalse(cloud.hydrated)
        }
    }
}
