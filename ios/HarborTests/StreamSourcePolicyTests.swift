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
        // Beta carries the rank the chosen order gives its requests (0) but a far worse release,
        // so Harbor ranking alone puts Alpha first and only the priority reorder can lift Beta.
        func stream(_ name: String, priority: Int, index: Int, title: String) -> JSONValue {
            .object(["addonId": .string(name), "addonName": .string(name), "addonPriority": .integer(Int64(priority)), "addonReturnIdx": .integer(Int64(index)),
                     "title": .string(title), "url": .string("https://\(name).example.org/\(index).mkv"), "size": .integer(title.contains("2160p") ? 40_000_000_000 : 700_000_000)])
        }
        let best = "Owned.Film.2020.2160p.BluRay.REMUX.HEVC.DTS-HD.MA.7.1", worst = "Owned.Film.2020.480p.DVDRip.XviD.MP3"
        let ranked: JSONValue = try await CoreBridge().call("rank", [
            "streams": .array([stream("alpha", priority: 1, index: 0, title: best), stream("beta", priority: 0, index: 0, title: worst),
                               stream("alpha", priority: 1, index: 1, title: best)]),
            "trust": StreamFilterConfiguration(level: "off", addonOrder: false).trust(media, season: nil, episode: nil),
            // Harbor ranking, so only the chosen priority can put Beta first.
            "score": AddonOriginPolicy.score(media, addonOrder: false)])
        XCTAssertEqual(ranked["picker"]["all"].array.first?["addonId"].string, "alpha", "Precondition: the score alone ranks Alpha first")
        let unordered = HarborService.ordered(ranked, addons: [addon("alpha"), addon("beta")], preferences: StreamFilterConfiguration(level: "off", addonOrder: false))
        XCTAssertEqual(unordered.first?.raw["addonId"].string, "alpha", "Without a chosen order the ranking is untouched")
        let preferences = StreamFilterConfiguration(level: "off", addonOrder: false, sources: StreamSourceSettings(priority: [.init(key: "beta", name: "Beta")]))
        let ordered = HarborService.ordered(ranked, addons: [addon("alpha"), addon("beta")], preferences: preferences)
        XCTAssertEqual(ordered.map { $0.raw["addonId"].string }, ["beta", "alpha", "alpha"])
        XCTAssertEqual(ordered.map(\.id), [0, 1, 2], "Offers are numbered after reordering")
    }

    func testAutoplaySettlesOnThePlayableFloorQuorumOrCap() {
        let start = ContinuousClock.now
        let playable = offer(0, ["url": .string("https://cdn.example.org/a.mp4"), "title": .string("Film.2020.1080p")])
        let unnamed = offer(1, ["url": .string("https://cdn.example.org/b.mp4"), "nameAbsent": .bool(true)])
        var floor = StreamAutoSettle(started: start)
        XCTAssertFalse(floor.shouldStart(now: start, top: nil, candidates: [], hasResults: false, answered: 0, total: 5, done: false, protecting: false))
        XCTAssertFalse(floor.shouldStart(now: start + .milliseconds(100), top: playable, candidates: [playable], hasResults: true, answered: 1, total: 5, done: false, protecting: false),
                       "Too soon after the first result")
        XCTAssertTrue(floor.shouldStart(now: start + .milliseconds(1700), top: playable, candidates: [playable], hasResults: true, answered: 1, total: 5, done: false, protecting: false),
                      "A playable top settles 1.5 s after the first result")

        var quorum = StreamAutoSettle(started: start)
        XCTAssertFalse(quorum.shouldStart(now: start, top: unnamed, candidates: [unnamed], hasResults: true, answered: 3, total: 5, done: false, protecting: false))
        XCTAssertFalse(quorum.shouldStart(now: start + .milliseconds(1600), top: unnamed, candidates: [unnamed], hasResults: true, answered: 3, total: 5, done: false, protecting: false),
                       "A top without its own name waits for most addons")
        XCTAssertTrue(quorum.shouldStart(now: start + .milliseconds(1700), top: unnamed, candidates: [unnamed], hasResults: true, answered: 4, total: 5, done: false, protecting: false),
                      "80 % of the addons answered")

        var cap = StreamAutoSettle(started: start)
        XCTAssertFalse(cap.shouldStart(now: start + .seconds(2), top: unnamed, candidates: [unnamed], hasResults: true, answered: 1, total: 5, done: false, protecting: false))
        XCTAssertTrue(cap.shouldStart(now: start + .seconds(10), top: unnamed, candidates: [unnamed], hasResults: true, answered: 1, total: 5, done: false, protecting: false),
                      "Ten seconds after the start nothing waits any longer")

        var done = StreamAutoSettle(started: start)
        XCTAssertFalse(done.shouldStart(now: start, top: nil, candidates: [], hasResults: false, answered: 5, total: 5, done: true, protecting: false))
        XCTAssertTrue(done.shouldStart(now: start, top: unnamed, candidates: [unnamed], hasResults: true, answered: 5, total: 5, done: true, protecting: true),
                      "Every addon answered: start even a protected choice")
    }

    func testAutoplayEpisodeChecksAndConfidentStart() {
        let start = ContinuousClock.now
        let named = offer(0, ["url": .string("https://cdn.example.org/a.mkv"), "behaviorHints": .object(["filename": .string("Show.S01E03.1080p.WEB-DL.mkv")])])
        let otherEpisode = offer(1, ["url": .string("https://cdn.example.org/b.mkv"), "episode": .integer(4), "season": .integer(1)])
        let pack = offer(2, ["url": .string("https://cdn.example.org/c.mkv"), "behaviorHints": .object(["filename": .string("Show.S01.Complete.1080p.mkv")])])
        let settle = StreamAutoSettle(started: start, season: 1, episode: 3)
        XCTAssertTrue(settle.qualifies(named)); XCTAssertFalse(settle.qualifies(otherEpisode)); XCTAssertFalse(settle.qualifies(pack))
        XCTAssertTrue(settle.qualifies(offer(3, ["episode": .integer(3), "season": .integer(1)])))
        XCTAssertTrue(StreamAutoSettle(started: start).qualifies(pack), "A film has no episode to check")

        var waitsForPack = StreamAutoSettle(started: start, season: 1, episode: 3)
        _ = waitsForPack.shouldStart(now: start, top: pack, candidates: [pack], hasResults: true, answered: 1, total: 5, done: false, protecting: false)
        XCTAssertFalse(waitsForPack.shouldStart(now: start + .seconds(5), top: pack, candidates: [pack], hasResults: true, answered: 1, total: 5, done: false, protecting: false),
                       "A season pack is not the episode, so only the quorum or the cap can settle")

        let instant = offer(4, ["url": .string("https://cdn.example.org/d.mkv"), "name": .string("⚡ Instant 1080p"), "episode": .integer(3), "season": .integer(1)])
        var confident = StreamAutoSettle(started: start, season: 1, episode: 3)
        XCTAssertFalse(confident.shouldStart(now: start, top: instant, candidates: [instant], hasResults: true, answered: 1, total: 5, done: false, protecting: false))
        XCTAssertTrue(confident.shouldStart(now: start + .milliseconds(400), top: instant, candidates: [instant], hasResults: true, answered: 1, total: 5, done: false, protecting: false),
                      "A confident instant source starts after the 350 ms grace")
        var protected = StreamAutoSettle(started: start, season: 1, episode: 3)
        _ = protected.shouldStart(now: start, top: instant, candidates: [instant], hasResults: true, answered: 1, total: 5, done: false, protecting: true)
        XCTAssertFalse(protected.shouldStart(now: start + .seconds(3), top: instant, candidates: [instant], hasResults: true, answered: 1, total: 5, done: false, protecting: true),
                       "The remembered source has not answered yet")

        let torrentio = offer(5, ["url": .string("https://cdn.example.org/e.mkv"), "name": .string("⚡ Instant"), "addonName": .string("Torrentio")])
        XCTAssertTrue(StreamAutoSettle(started: start).highConfidence(torrentio))
        XCTAssertFalse(StreamAutoSettle(started: start, strongAddon: true).highConfidence(torrentio), "MediaFusion or Comet outrank Torrentio's own marker")
        XCTAssertTrue(StreamAutoSettle.strong([addon("comet")]))
    }

    func testPickerFilterWidensLikeDesktop() {
        var strict = StreamPickerFilter()
        XCTAssertEqual(strict.level("strict"), "strict")
        strict.widen("strict")
        XCTAssertEqual(strict.level("strict"), "balanced", "Search wider first relaxes Strict to Balanced")
        strict.widen("strict")
        XCTAssertEqual(strict.level("strict"), "off", "A second wider search shows everything")
        var balanced = StreamPickerFilter()
        balanced.widen("balanced")
        XCTAssertEqual(balanced.level("balanced"), "off")
        XCTAssertEqual(StreamPickerFilter(showAll: true).level("strict"), "off")
        XCTAssertEqual(StreamPickerFilter().level("off"), "off")
    }

    func testRejectionGroupsUseDesktopLabels() {
        let groups = StreamRejections.groups(["title-mismatch", "suspicious-extension:exe", "title-mismatch", "season-mismatch:2-vs-1",
                                              "episode-mismatch:3-vs-4", "cinema-window-12d", "something-new"])
        XCTAssertEqual(groups.map(\.label), ["wrong movie", "wrong episode", "sketchy files", "cam rips", "something-new"])
        XCTAssertEqual(groups.map(\.count), [2, 2, 1, 1, 1])
        XCTAssertEqual(StreamRejections.label("size-too-large-90gb"), "oversized")
        XCTAssertEqual(StreamRejections.label("dead-torrent-zero-seeders"), "dead torrents")
    }

    func testDebridVerificationMergeKeepsEachHashOnce() {
        var value = DebridVerification(cached: ["rd": ["a"]], library: [:])
        value.merge(DebridVerification(cached: ["rd": ["a", "b"], "tb": ["c"]], library: ["rd": ["d"]]))
        XCTAssertEqual(value, DebridVerification(cached: ["rd": ["a", "b"], "tb": ["c"]], library: ["rd": ["d"]]))
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
