import XCTest
@testable import Harbor

/// Desktop's streaming-sources settings: source mode (`lib/streams/mode.ts`), stream priority
/// (`addon-priority.ts`, `priority-partition.ts`), addon wait time and the Stremio picker layout.
@MainActor final class StreamSourcePolicyTests: XCTestCase {
    private let hash = "aabbccddeeff00112233445566778899aabbccdd"

    private func offer(_ id: Int, _ fields: [String: JSONValue]) -> StreamOffer {
        var value: [String: JSONValue] = ["addonId": .string("owned"), "addonName": .string("Owned")]
        for (key, item) in fields { value[key] = item }
        return StreamOffer(id: id, raw: .object(value))
    }
    private func addon(_ id: String, streams: Bool = true, url: String? = nil) -> Addon {
        Addon(manifest: .object(["id": .string(id), "name": .string(id.capitalized),
                                 "resources": .array(streams ? [.string("stream")] : [.string("catalog")])]),
              transportUrl: url ?? "https://\(id).example.org/manifest.json", enabled: true)
    }

    func testPeerToPeerExcludesDebridMarkedAndProviderConfirmedTorrents() {
        XCTAssertTrue(StreamSourcePolicy.isPeerToPeer(offer(0, ["infoHash": .string(hash), "title": .string("Show.S01E01.1080p")]).raw))
        XCTAssertFalse(StreamSourcePolicy.isPeerToPeer(offer(0, ["infoHash": .string(hash), "name": .string("[RD+] Torrentio")]).raw))
        XCTAssertFalse(StreamSourcePolicy.isPeerToPeer(offer(0, ["infoHash": .string(hash), "name": .string("Comet ⚡")]).raw))
        XCTAssertFalse(StreamSourcePolicy.isPeerToPeer(offer(0, ["infoHash": .string(hash), "cached": .object(["rd": .bool(true)])]).raw))
        XCTAssertFalse(StreamSourcePolicy.isPeerToPeer(offer(0, ["url": .string("https://cdn.example.org/a.mkv")]).raw), "A link is never P2P")
    }

    func testDirectMediaEvidenceIgnoresPlainWatchPages() {
        XCTAssertFalse(StreamSourcePolicy.hasDirectMediaEvidence(offer(0, ["url": .string("https://example.org/watch/123")]).raw))
        XCTAssertTrue(StreamSourcePolicy.hasDirectMediaEvidence(offer(0, ["url": .string("https://cdn.example.org/a.MKV?token=1")]).raw))
        XCTAssertTrue(StreamSourcePolicy.hasDirectMediaEvidence(offer(0, ["url": .string("https://example.org/v"), "behaviorHints": .object(["videoSize": .integer(1_000)])]).raw))
        XCTAssertTrue(StreamSourcePolicy.hasDirectMediaEvidence(offer(0, ["url": .string("https://example.org/v"), "behaviorHints": .object(["notWebReady": .bool(true)])]).raw))
        XCTAssertTrue(StreamSourcePolicy.hasDirectMediaEvidence(offer(0, ["url": .string("https://example.org/v"), "behaviorHints": .object(["proxyHeaders": .object(["request": .object(["Referer": .string("x")])])])]).raw))
        XCTAssertTrue(StreamSourcePolicy.hasDirectMediaEvidence(offer(0, ["url": .string("rtmp://live.example.org/a")]).raw))
        XCTAssertFalse(StreamSourcePolicy.hasDirectMediaEvidence(offer(0, ["url": .string("#")]).raw))
        XCTAssertTrue(StreamSourcePolicy.hasDirectMediaEvidence(offer(0, ["infoHash": .string(hash), "name": .string("[TB+]")]).raw))
        XCTAssertFalse(StreamSourcePolicy.hasDirectMediaEvidence(offer(0, ["infoHash": .string(hash)]).raw))
    }

    func testSourceModeNeverEmptiesThePicker() {
        let peer = offer(0, ["infoHash": .string(hash)])
        let direct = offer(1, ["url": .string("https://cdn.example.org/a.mp4")])
        let watchPage = offer(2, ["url": .string("https://example.org/watch")])
        XCTAssertEqual(StreamSourcePolicy.filter([peer, direct, watchPage], mode: .both).map(\.id), [0, 1, 2])
        XCTAssertEqual(StreamSourcePolicy.filter([peer, direct, watchPage], mode: .addons).map(\.id), [1, 2])
        XCTAssertEqual(StreamSourcePolicy.filter([peer, watchPage], mode: .addons).map(\.id), [0, 2],
                       "Watch pages alone are not enough to hide the torrents")
        XCTAssertEqual(StreamSourcePolicy.filter([peer, direct], mode: .p2p).map(\.id), [0])
        XCTAssertEqual(StreamSourcePolicy.filter([direct], mode: .p2p).map(\.id), [1])
        XCTAssertEqual(StreamMode(stored: "future-mode"), .both)
        XCTAssertEqual(StreamMode(stored: nil), .both)
        XCTAssertEqual(StreamMode(stored: "addons"), .addons)
    }

    func testPriorityNeedsAChosenOrderAndTwoStreamAddons() throws {
        let first = addon("alpha"), second = addon("beta"), catalog = addon("catalog", streams: false)
        XCTAssertNil(StreamAddonPriority.ranker(addons: [first, second], priority: []))
        XCTAssertNil(StreamAddonPriority.ranker(addons: [first, catalog], priority: [.init(key: "alpha", name: "Alpha")]))
        let ranker = try XCTUnwrap(StreamAddonPriority.ranker(addons: [first, second, catalog], priority: [.init(key: "beta", name: "Beta")]))
        XCTAssertEqual(ranker.rank(index: 1, addon: second), 0)
        XCTAssertEqual(ranker.rank(index: 0, addon: first), 1, "Unlisted addons follow, in addon order")
        XCTAssertEqual(StreamAddonPriority.key(Addon(manifest: .object([:]), transportUrl: "https://host.example.org:8443/x/manifest.json", enabled: true)),
                       "host:host.example.org:8443")
        XCTAssertEqual(StreamAddonPriority.key(addon(" MixedCase ")), "mixedcase")
    }

    func testPriorityEntriesKeepUninstalledAddonsAndAppendNewOnes() {
        let entries = StreamAddonPriority.entries(addons: [addon("alpha"), addon("beta"), addon("catalog", streams: false)],
                                                  priority: [.init(key: "gone", name: "Gone"), .init(key: "beta", name: "Old name"), .init(key: "beta", name: "Twice")])
        XCTAssertEqual(entries.map(\.entry.key), ["gone", "beta", "alpha"])
        XCTAssertEqual(entries.map(\.installed), [false, true, true])
        XCTAssertEqual(entries[1].entry.name, "Beta", "An installed addon shows its current name")
    }

    func testPriorityOrderIsStableAndOnlyWhenActive() {
        let offers = [offer(0, ["addonPriority": .integer(2)]), offer(1, ["addonPriority": .integer(0)]),
                      offer(2, ["addonPriority": .integer(2)]), offer(3, [:]), offer(4, ["addonPriority": .integer(1)])]
        XCTAssertEqual(StreamAddonPriority.order(offers, active: true).map(\.id), [1, 4, 0, 2, 3])
        XCTAssertEqual(StreamAddonPriority.order(offers, active: false).map(\.id), [0, 1, 2, 3, 4])
    }

    func testRequestsGetTheWaitTimeFloorAndChosenRanks() {
        let fast = addon("alpha"), slow = addon("torrentio")
        func plan(_ addon: Addon, _ index: Int, _ timeout: Int) -> RequestPlan {
            RequestPlan(key: "\(index):stream", url: addon.transportUrl, title: addon.name, kind: "movie", addon: addon,
                        addonPriority: index, timeoutMs: timeout, catalog: nil)
        }
        let requests = HarborService.StreamRequests(plans: [plan(fast, 0, 8_000), plan(slow, 1, 22_000)], fallbacks: ["0:stream": [plan(fast, 0, 8_000)]])
        let standard = StreamAddonPriority.tune(requests, settings: StreamSourceSettings(), addons: [fast, slow])
        XCTAssertEqual(standard.plans.map(\.timeoutMs), [30_000, 30_000], "Desktop's default wait is 30 seconds")
        XCTAssertEqual(standard.plans.map(\.addonPriority), [0, 1])
        XCTAssertEqual(standard.fallbacks["0:stream"]?.map(\.timeoutMs), [30_000])
        let short = StreamAddonPriority.tune(requests, settings: StreamSourceSettings(timeoutSeconds: 15, priority: [.init(key: "torrentio", name: "Torrentio")]),
                                             addons: [fast, slow])
        XCTAssertEqual(short.plans.map(\.timeoutMs), [15_000, 22_000], "Slow aggregators keep their own longer budget")
        XCTAssertEqual(short.plans.map(\.addonPriority), [1, 0])
        XCTAssertEqual(StreamSourceSettings.clamped(3), 8)
        XCTAssertEqual(StreamSourceSettings.clamped(500), 120)
        XCTAssertEqual(StreamAddonPriority.pluginStart(addons: [fast, slow], settings: StreamSourceSettings(priority: [.init(key: "torrentio", name: "T")])), 3)
        XCTAssertEqual(StreamAddonPriority.pluginStart(addons: [fast, slow], settings: StreamSourceSettings()), 2)
    }

    func testRealRankingFollowsTheChosenAddonOrder() async throws {
        let media = Media(id: "tt0000001", type: "movie", name: "Owned Film", releaseInfo: "2020")
        func stream(_ name: String, priority: Int, index: Int) -> JSONValue {
            .object(["addonId": .string(name), "addonName": .string(name), "addonPriority": .integer(Int64(priority)), "addonReturnIdx": .integer(Int64(index)),
                     "title": .string("Owned.Film.2020.1080p.WEB-DL.H264.AAC"), "url": .string("https://\(name).example.org/\(index).mp4")])
        }
        let ranked: JSONValue = try await CoreBridge().call("rank", [
            "streams": .array([stream("alpha", priority: 1, index: 0), stream("beta", priority: 0, index: 0), stream("alpha", priority: 1, index: 1)]),
            "trust": StreamFilterConfiguration(level: "off", addonOrder: false).trust(media, season: nil, episode: nil),
            // Harbor ranking, so only the chosen priority can put Beta first.
            "score": AddonOriginPolicy.score(media, addonOrder: false)])
        let preferences = StreamFilterConfiguration(level: "off", addonOrder: false, sources: StreamSourceSettings(priority: [.init(key: "beta", name: "Beta")]))
        let ordered = HarborService.ordered(ranked, addons: [addon("alpha"), addon("beta")], preferences: preferences)
        XCTAssertEqual(ordered.map { $0.raw["addonId"].string }, ["beta", "alpha", "alpha"])
        XCTAssertEqual(ordered.map(\.id), [0, 1, 2], "Offers are numbered after reordering")
    }

    func testStremioRowTextAndOrder() {
        let long = String(repeating: "a", count: 95)
        let row = offer(0, ["name": .string("  "), "title": .string(long + "\nsecond line")])
        XCTAssertEqual(StremioPickerPresentation.headline(row), "Owned", "An empty name falls back to the addon")
        XCTAssertEqual(StremioPickerPresentation.description(row, full: true), long + "\nsecond line")
        XCTAssertEqual(StremioPickerPresentation.description(row, full: false), String(repeating: "a", count: 90) + "…\nsecond line")
        XCTAssertEqual(StremioPickerPresentation.description(offer(0, ["description": .string(" only ")]), full: false), "only")

        let addons = [addon("alpha", url: "https://a.example.org/manifest.json"), addon("beta", url: "https://b.example.org/manifest.json")]
        let downloading = offer(0, ["addonUrl": .string("https://a.example.org/manifest.json"), "name": .string("RD download")])
        let watchHub = offer(1, ["addonId": .string("org.watchhub"), "addonUrl": .string("https://a.example.org/manifest.json")])
        let second = offer(2, ["addonUrl": .string("https://b.example.org/manifest.json")])
        let instant = offer(3, ["addonUrl": .string("https://b.example.org/manifest.json"), "name": .string("⚡ Instant")])
        let first = offer(4, ["addonUrl": .string("https://a.example.org/manifest.json")])
        let all = [downloading, watchHub, second, instant, first]
        XCTAssertEqual(StremioPickerPresentation.ordered(all, addons: addons, preserveOrder: false).map(\.id), [4, 3, 2, 0, 1])
        XCTAssertEqual(StremioPickerPresentation.ordered(all, addons: addons, preserveOrder: true).map(\.id), [0, 1, 2, 3, 4])
        let options = StremioPickerPresentation.addonOptions([second, first, instant], addons: addons)
        XCTAssertEqual(options.map(\.id), ["https://a.example.org/manifest.json", "https://b.example.org/manifest.json"])
        XCTAssertEqual(options.map(\.count), [1, 2])
    }
}
