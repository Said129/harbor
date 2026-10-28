import XCTest
@testable import Harbor

private actor OriginRequests {
    let replies: [String: JSONValue]
    private(set) var requested: [String] = []
    init(_ replies: [String: JSONValue]) { self.replies = replies }
    func load(_ url: String) throws -> JSONValue {
        requested.append(url)
        guard let reply = replies[url] else { throw HarborError(code: "http-404") }
        return reply
    }
}
private actor OriginHeldReply {
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    var held: Bool { waiter != nil }
    func load() async -> JSONValue {
        calls += 1; await withCheckedContinuation { waiter = $0 }
        return .object(["meta": .object(["id": .string("owned:1"), "name": .string("Late")])])
    }
    func release() { waiter?.resume(); waiter = nil }
}

@MainActor final class AddonOriginTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "addon-origin-reference", withExtension: "json", subdirectory: "Fixtures"))
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(value["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(value["actual_original_typescript_executed"], .bool(true)); XCTAssertEqual(value["provider_network_requests"].integer, 0)
        XCTAssertEqual(value["executed_module_hashes"].objectValue.count, 5); return value
    }
    private func addon(_ id: String, url: String, type: String = "movie", prefix: String = "owned:") -> Addon {
        .init(manifest: .object(["id": .string(id), "name": .string(id), "resources": .array([.string("stream")]),
            "types": .array([.string(type)]), "idPrefixes": .array([.string(prefix)])]), transportUrl: url, enabled: true)
    }
    func testExecutedDesktopOriginBasesNativeIDsAlternateTypesAndPluginBasesMatch() throws {
        let fixture = try fixture()
        XCTAssertEqual(fixture["base_cases"].array.count, 5)
        for row in fixture["base_cases"].array {
            let addons = try JSONDecoder().decode([Addon].self, from: JSONEncoder().encode(row["addons"]))
            XCTAssertEqual(AddonOriginPolicy.bases(addons, origin: MediaAddonOrigin.parse(row["origin"])), row["expected"].array.compactMap(\.string))
        }
        XCTAssertEqual(fixture["native_cases"].array.count, 18)
        for row in fixture["native_cases"].array {
            XCTAssertEqual(AddonOriginPolicy.isNative(try XCTUnwrap(Media.parse(row["media"], kind: "movie"))), row["expected"] == .bool(true))
        }
        XCTAssertEqual(fixture["type_cases"].array.count, 3)
        for row in fixture["type_cases"].array {
            let addon = try JSONDecoder().decode(Addon.self, from: JSONEncoder().encode(row["addon"]))
            XCTAssertEqual(AddonOriginPolicy.streamTypes(addon, primary: try XCTUnwrap(row["primary"].string), id: try XCTUnwrap(row["id"].string)), row["expected"].array.compactMap(\.string))
        }
        XCTAssertEqual(fixture["plugin_cases"].array.count, 6)
        for row in fixture["plugin_cases"].array { XCTAssertEqual(AddonOriginPolicy.pluginID(try XCTUnwrap(row["base"].string)), row["expected"].string) }
    }
    func testPreferredMetadataRetriesOnlyMatchingInstancesAndUsesOriginalEncodedIdentity() async throws {
        let origin = MediaAddonOrigin(id: "owned", name: "Owned", base: "https://example.org/first/manifest.json")
        let media = Media(id: "owned:東京/a?b#c", type: "series", name: "Saved", addonOrigin: origin)
        let addons = [addon("owned", url: "https://example.org/first/manifest.json"),
            addon("other", url: "https://example.org/other/manifest.json"), addon("owned", url: "https://example.org/second/manifest.json")]
        let urls = AddonOriginPolicy.metadataURLs(media, addons: addons)
        XCTAssertEqual(urls.first, try fixture()["metadata_request"].string); XCTAssertEqual(urls.count, 2)
        let requests = OriginRequests([urls[1]: .object(["meta": .object(["id": .string(media.id), "name": .string("Provider title")])])])
        let result = try await AddonOriginMetadata().value(media, addons: addons) { try await requests.load($0) }
        XCTAssertEqual(result?.name, "Provider title"); XCTAssertEqual(result?.addonOrigin, origin)
        let actual = await requests.requested; XCTAssertEqual(actual, urls)
        XCTAssertNil(AddonOriginPolicy.resourceURL("harbor-plugin://owned/provider", resource: "meta", kind: "movie", id: "owned"))
        XCTAssertNil(AddonOriginPolicy.resourceURL("https://user:password@example.org", resource: "meta", kind: "movie", id: "owned"))
        let privateQuery = try XCTUnwrap(AddonOriginPolicy.resourceURL("https://example.org/config/manifest.json?key=owned", resource: "meta", kind: "movie", id: "owned:1"))
        let components = try XCTUnwrap(URLComponents(string: privateQuery))
        XCTAssertEqual(components.queryItems, [.init(name: "key", value: "owned")]); XCTAssertEqual(components.percentEncodedPath, "/config/meta/movie/owned%3A1.json")
    }
    func testCancelledPreferredMetadataCannotPublishOrContinueToAnotherInstance() async throws {
        let held = OriginHeldReply(), media = Media(id: "owned:1", type: "movie", name: "Owned",
            addonOrigin: .init(id: "owned", name: "Owned", base: "https://example.org/first"))
        let other = addon("owned", url: "https://example.org/second/manifest.json")
        let pending = Task { try await AddonOriginMetadata().value(media, addons: [other]) { _ in await held.load() } }
        for _ in 0..<100 { if await held.held { break }; try await Task.sleep(for: .milliseconds(10)) }
        let isHeld = await held.held; XCTAssertTrue(isHeld)
        pending.cancel(); await held.release()
        do { _ = try await pending.value; XCTFail("Cancelled metadata was returned") } catch { XCTAssertTrue(error is CancellationError) }
        let calls = await held.calls; XCTAssertEqual(calls, 1)
    }
    func testSameMediaIDFromTwoConfiguredOriginsDoesNotShareCachedMetadata() async throws {
        let configuration = MetadataConfiguration(tmdbKey: "", region: "US", language: "en-US", translateTitles: true)
        let first = Media(id: "owned:1", type: "movie", name: "Saved", addonOrigin: .init(id: "owned", name: "Owned", base: "https://example.org/one"))
        var second = first; second.addonOrigin?.base = "https://example.org/two"
        let firstKey = try MediaMetadataStore.key(first, owner: "owned-profile", addons: [], configuration: configuration)
        let secondKey = try MediaMetadataStore.key(second, owner: "owned-profile", addons: [], configuration: configuration)
        XCTAssertNotEqual(firstKey, secondKey)
        XCTAssertFalse(firstKey.contains("example.org")); XCTAssertEqual(firstKey.count, 64)
        let firstURL = try XCTUnwrap(AddonOriginPolicy.metadataURLs(first, addons: []).first)
        let secondURL = try XCTUnwrap(AddonOriginPolicy.metadataURLs(second, addons: []).first)
        let requests = OriginRequests([firstURL: .object(["meta": .object(["id": .string(first.id), "name": .string("First")])]),
            secondURL: .object(["meta": .object(["id": .string(first.id), "name": .string("Second")])])])
        let store = MediaMetadataStore()
        let a = try await store.value(for: firstKey) {
            let value = try await AddonOriginMetadata().value(first, addons: []) { try await requests.load($0) }
            return try XCTUnwrap(value)
        }
        let copiedSecond = second
        let b = try await store.value(for: secondKey) {
            let value = try await AddonOriginMetadata().value(copiedSecond, addons: []) { try await requests.load($0) }
            return try XCTUnwrap(value)
        }
        XCTAssertEqual(a.name, "First"); XCTAssertEqual(b.name, "Second")
        let calls = await requests.requested; XCTAssertEqual(calls.count, 2)
    }
    func testOriginStreamRequestsKeepOtherProvidersRawEpisodeAndDeclaredTypeFallback() async throws {
        let addons = [addon("owned", url: "https://example.org/owned/manifest.json", type: "tv"),
            addon("other", url: "https://example.org/other/manifest.json")]
        let media = Media(id: "owned:1", type: "movie", name: "Saved", addonOrigin: .init(id: "owned", name: "Owned"))
        let service = HarborService(), selection = try await service.streamRequests(media, videoID: media.id, addons: addons)
        XCTAssertEqual(Set(selection.plans.compactMap { $0.addon.manifest["id"].string }), Set(["owned", "other"]))
        let primary = try XCTUnwrap(selection.plans.first { $0.addon.manifest["id"].string == "owned" })
        let fallback = try XCTUnwrap(selection.fallbacks[primary.key]?.first)
        XCTAssertEqual(primary.kind, "movie"); XCTAssertEqual(fallback.kind, "tv")
        let requests = OriginRequests([primary.url: .object(["streams": .array([])]), fallback.url: .object(["streams": .array([.object(["url": .string("https://example.org/video.mp4")])])])])
        let reply = try await AddonOriginReplies.fetch(primary, fallbacks: [fallback]) { try await requests.load($0.url) }
        XCTAssertEqual(reply.0.kind, "tv"); XCTAssertEqual(reply.1?["streams"].array.count, 1); XCTAssertNil(reply.2)
        let actual = await requests.requested; XCTAssertEqual(actual, [primary.url, fallback.url])
        let success = OriginRequests([primary.url: .object(["streams": .array([.object(["url": .string("https://example.org/first.mp4")])])])])
        _ = try await AddonOriginReplies.fetch(primary, fallbacks: [fallback]) { try await success.load($0.url) }
        let firstOnly = await success.requested; XCTAssertEqual(firstOnly, [primary.url])
        var episodic = Media(id: "owned:show", type: "series", name: "Owned", addonOrigin: media.addonOrigin)
        episodic.videos = [.init(id: "owned:show:5:23", season: 5, episode: 23, displaySeason: 1, displayEpisode: 99)]
        let episodeRequests = try await service.streamRequests(episodic, videoID: "owned:show:5:23", addons: addons, season: 5, episode: 23)
        XCTAssertTrue(episodeRequests.plans.allSatisfy { $0.url.contains("owned%3Ashow%3A5%3A23") })
        XCTAssertFalse(episodeRequests.plans.contains { $0.url.contains("99") })
    }
    func testActualNativeRankingAppliesOnlyTheExecutedDesktopOriginBoostAndKeepsEverySource() async throws {
        let streams: JSONValue = .array(["owned", "other"].enumerated().map { index, id in
            .object(["addonId": .string(id), "addonName": .string(id), "title": .string("Owned.2020.1080p.WEB-DL.H264.AAC"),
                "url": .string("https://example.org/\(id).mp4"), "addonPriority": .integer(Int64(index))])
        })
        let normal = Media(id: "tt1234567", type: "movie", name: "Owned")
        var preferred = normal; preferred.addonOrigin = .init(id: "owned", name: "Owned")
        func rank(_ media: Media) async throws -> [JSONValue] {
            let result: JSONValue = try await CoreBridge().call("rank", ["streams": streams, "trust": .object(["disabled": .bool(true)]),
                "score": AddonOriginPolicy.score(media, addonOrder: false)])
            return result["picker"]["all"].array
        }
        let baseline = try await rank(normal), boosted = try await rank(preferred)
        XCTAssertEqual(baseline.count, 2); XCTAssertEqual(boosted.count, 2)
        for row in try fixture()["score_cases"].array {
            guard let id = row["addonId"].string, row["preferAddonId"].string != nil else { continue }
            let first = try XCTUnwrap(baseline.first { $0["addonId"].string == id }?["score"].numericValue)
            let second = try XCTUnwrap(boosted.first { $0["addonId"].string == id }?["score"].numericValue)
            XCTAssertEqual(second - first, row["expected"]["score"].numericValue)
        }
        XCTAssertEqual(boosted.first?["addonId"].string, "owned")
        XCTAssertEqual(boosted.first?["reasons"].array.first(where: { $0["signal"].string == "origin-addon" })?["delta"].numericValue, 250)
    }
    func testNativePluginOriginSelectsItsOwnRunnableSourceAndRespectsGroupingAndMasterPause() throws {
        let repository = "https://example.org/plugins/manifest.json"
        let manifest = try HarborPluginManifest.parse(.object(["plugins": .array(["one", "two"].map {
            .object(["id": .string($0), "name": .string($0), "entry": .string($0 + ".js"), "idPrefixes": .array([.string("tt")])])
        })]), url: repository)
        let plugins = manifest.entries.map { entry in HarborInstalledStreamPlugin(id: HarborPluginManifest.pluginID(repository: repository, entry: entry.id),
            repoURL: repository, repoName: "Owned", entry: entry, code: "", hash: "", etag: nil, installedAt: 0, updatedAt: 0, previous: nil) }
        let target = try XCTUnwrap(plugins.first)
        let origin = MediaAddonOrigin(id: target.id, name: target.entry.name, base: "harbor-plugin://" + target.id + "/provider")
        let chosen = HarborPluginSourceSelection.groups(plugins, type: "movie", ids: ["owned:page"], options: .init(), startingPriority: 2, origin: origin, sourceID: "owned:page")
        XCTAssertEqual(chosen.count, 1); XCTAssertEqual(chosen.first?.plugins.first?.id, target.id); XCTAssertEqual(chosen.first?.pickedID, "owned:page")
        XCTAssertTrue(HarborPluginSourceSelection.groups(plugins, type: "movie", ids: ["owned:page"], options: .init(enabled: false), startingPriority: 0, origin: origin, sourceID: "owned:page").isEmpty)
        let grouped = HarborPluginSourceSelection.groups(plugins, type: "movie", ids: ["tt1234567"], options: .init(groupByRepository: true), startingPriority: 0, origin: origin, sourceID: "tt1234567")
        XCTAssertEqual(grouped.count, 1); XCTAssertEqual(grouped.first?.plugins.count, 2)
        var disabled = plugins; disabled[0].enabled = false
        let other = HarborPluginSourceSelection.groups(disabled, type: "movie", ids: ["tt1234567"], options: .init(), startingPriority: 0, origin: origin, sourceID: "tt1234567")
        XCTAssertEqual(other.count, 1); XCTAssertEqual(other.first?.plugins.first?.id, plugins[1].id)
    }
}
