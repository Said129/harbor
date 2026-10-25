import XCTest
@testable import Harbor

private actor OwnedArtworkRequests {
    var urls: [String] = []
    func record(_ url: String) { urls.append(url) }
}
@MainActor private final class OwnedArtworkAppearance: ProfileAppearancePersistence {
    var value: MobileProfile?
    func readAppearance(_ key: String) throws -> MobileProfile? { value }
    func writeAppearance(_ value: MobileProfile, key: String) throws { self.value = value }
}

@MainActor final class HarborArtworkServerTests: XCTestCase {
    private let avatar = "/avatars/owned-unbundled-avatar.webp"
    private func index(_ suffix: String, count: Int = 2) -> JSONValue {
        .object(["v": .integer(1), "art": .object(Dictionary(uniqueKeysWithValues: (1...count).map {
            ("owned-art-\($0)", .object(["bg": .string("https://images.example/\(suffix)-\($0).jpg"),
                "logo": .string("https://images.example/\(suffix)-\($0).png"), "desc": .string("Owned description \($0)")]))
        }))])
    }
    private func document(_ memory: ActivationMemory) -> HarborLayoutDocument {
        var row = memory.remote().objectValue; row["avatar"] = .string(avatar)
        return memory.document([.object(row)])
    }
    func testAdditionalPortableAvatarsStayOnTheirAccountServerAndBundledAvatarsNeedNoNetwork() throws {
        let server = try HarborIdentityServer("https://owned.example:8443")
        XCTAssertEqual(server.avatar(.string(avatar)), "https://owned.example:8443" + avatar)
        XCTAssertNil(server.avatar(.string("https://other.example/image.webp")))
        XCTAssertNil(server.avatar(.string("/avatars/../identity/api/me")))
        XCTAssertNil(HarborIdentityServer.original.avatar(.string(avatar)))
        let bundled = HouseholdAppearanceBinding.project(name: "Owned", color: nil, avatar: .string("/avatars/harbor_animal_01.webp"), server: server)
        XCTAssertEqual(bundled.avatar, "harbor_animal_01"); XCTAssertNil(bundled.remoteAvatar)
        let remote = HouseholdAppearanceBinding.project(name: "Owned", color: nil, avatar: .string(avatar), server: server)
        XCTAssertEqual(remote.remoteAvatar, "https://owned.example:8443" + avatar)
    }
    func testTheArtworkOriginSurvivesHouseholdRestorationAndDoesNotEnterThePortableRoster() throws {
        let memory = ActivationMemory(), context = memory.context(), server = try HarborIdentityServer("https://owned.example")
        try context.prepare()
        let account = server.account("owned-user"), doc = document(memory)
        try context.activateHarbor(account: account, document: doc, artworkServer: server)
        let active = try XCTUnwrap(context.profiles.active)
        let appearance = ProfilePreferences.forOwner(context.profiles.appearanceOwner(active))
        XCTAssertEqual(appearance.value.remoteAvatar, server.base + avatar)
        context.reload(); XCTAssertTrue(context.ready)
        XCTAssertEqual(context.profiles.state.artworkServer, server)
        XCTAssertEqual(appearance.value.remoteAvatar, server.base + avatar)
        let wire = String(decoding: try JSONEncoder().encode(context.profiles.state.wireValue), as: UTF8.self)
        XCTAssertFalse(wire.contains("owned.example")); XCTAssertFalse(wire.contains("artworkServer"))
        XCTAssertTrue(wire.contains("owned-unbundled-avatar.webp"))
    }
    func testAnArtworkMetadataWriteFailureCannotActivateANewHouseholdOrClaimPrivateDeviceSessions() throws {
        let memory = ActivationMemory(), context = memory.context(), server = try HarborIdentityServer("https://owned.example")
        try context.prepare(); let before = context.binding, scope = context.profiles.scope
        memory.failRoster = true
        XCTAssertThrowsError(try context.activateHarbor(account: server.account("owned-user"), document: document(memory), artworkServer: server))
        XCTAssertEqual(context.binding, before); XCTAssertEqual(context.profiles.scope, scope)
        XCTAssertNil(memory.sessions?.deviceImportAccount); XCTAssertNil(memory.sessions?.activeHarborAccount)
        XCTAssertTrue(context.ready)
    }
    func testTheLegacyAppearanceFacadeAlsoResolvesAdditionalAvatarsUsingTheExplicitServer() throws {
        let persistence = OwnedArtworkAppearance(), preferences = ProfilePreferences(owner: "owned-art-" + UUID().uuidString, persistence: persistence)
        let server = try HarborIdentityServer("https://owned.example")
        try preferences.adopt(.object(["name": .string("Owned"), "avatar": .string(avatar)]), accountID: server.account("owned-user"), server: server)
        XCTAssertEqual(preferences.value.remoteAvatar, server.base + avatar)
        XCTAssertEqual(persistence.value?.remoteAvatar, server.base + avatar)
    }
    func testTheDailyIndexUsesTheLivePublicEndpointAndEnrichesWithoutChangingMediaIdentity() async throws {
        let requests = OwnedArtworkRequests(), updated = index("updated")
        let art = AnimeArtwork(seed: try JSONEncoder().encode(index("seed")), fetch: { url in await requests.record(url); return updated })
        await art.refresh()
        let original = Media(id: "owned-art-1", type: "anime", name: "Owned title")
        let enriched = await art.enrich([original])
        let result = try XCTUnwrap(enriched.first)
        XCTAssertEqual(result.identity, original.identity); XCTAssertEqual(result.name, original.name)
        XCTAssertEqual(result.background, "https://images.example/updated-1.jpg")
        XCTAssertEqual(result.logo, "https://images.example/updated-1.png")
        XCTAssertEqual(result.description, "Owned description 1")
        let urls = await requests.urls
        XCTAssertEqual(urls, ["https://harborcommunity.site/anime-hero-art.json"])
    }
    func testMalformedOrTruncatedDailyIndexesKeepTheShippedArtworkAndDoNotReplaceTheCache() async throws {
        for candidate in [index("too-small", count: 1), .array([])] {
            let cache = FileManager.default.temporaryDirectory.appendingPathComponent("owned-art-cache-" + UUID().uuidString + ".json")
            defer { try? FileManager.default.removeItem(at: cache) }
            let art = AnimeArtwork(seed: try JSONEncoder().encode(index("seed")), cacheURL: cache, fetch: { _ in candidate })
            await art.refresh()
            let media = await art.enrich([Media(id: "owned-art-1", type: "anime", name: "Owned")])
            XCTAssertEqual(media.first?.background, "https://images.example/seed-1.jpg")
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        }
    }
    func testConcurrentDailyUpdatesAndLaterEnrichmentUseOnlyOneRequestAndRetainOfflineSeed() async throws {
        let requests = OwnedArtworkRequests()
        let art = AnimeArtwork(seed: try JSONEncoder().encode(index("seed")), fetch: { url in
            await requests.record(url); try await Task.sleep(for: .milliseconds(20)); throw URLError(.notConnectedToInternet)
        })
        async let first: Void = art.refresh()
        async let second: Void = art.refresh()
        _ = await (first, second)
        let media = await art.enrich([Media(id: "owned-art-1", type: "anime", name: "Owned")])
        XCTAssertEqual(media.first?.background, "https://images.example/seed-1.jpg")
        await art.refresh(); let urls = await requests.urls; XCTAssertEqual(urls.count, 1)
    }
    func testProductionIdentityActivationPassesTheChosenArtworkServerThroughToTheAppearance() async throws {
        let memory = ActivationMemory(), context = memory.context(), server = try HarborIdentityServer("https://owned.example")
        try context.prepare()
        let doc = document(memory), owner = memory.identity, preferences = ProfilePreferences.forOwner(memory.identity)
        let cloud = HarborProfileSync(owner: owner, profile: preferences, serverTransport: { actual, path, _, _, _ in
            XCTAssertEqual(actual, server)
            if path == "/identity/api/login" {
                return .object(["token": .string("owned-token"), "refresh": .string("owned-refresh"),
                    "user": .object(["id": .string("owned-user"), "username": .string("owned-user")])])
            }
            XCTAssertEqual(path, "/sync/v1/state")
            return .object(["rev": .integer(doc.rev), "docs": .array([.object(["key": .string(doc.key), "rev": .integer(doc.rev), "value": doc.value])])])
        })
        cloud.bindHouseholdContext(context) {}
        defer {
            cloud.suspendForProfileChange()
            try? KeychainStore().remove("harbor-identity-" + EBookShelf.hash(owner))
            try? KeychainStore().remove("mobile-profile-" + EBookShelf.hash(owner))
        }
        await cloud.signIn(username: "owned-user", password: "owned-password", server: server)
        XCTAssertEqual(context.profiles.state.artworkServer, server)
        let active = try XCTUnwrap(context.profiles.active)
        XCTAssertEqual(ProfilePreferences.forOwner(context.profiles.appearanceOwner(active)).value.remoteAvatar, server.base + avatar)
    }
}
