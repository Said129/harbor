import XCTest
@testable import Harbor

/// Addon management, Continue Watching and resume gaps closed against Desktop 0.9.132: pure decisions only,
/// no network and no UI.
final class R21AddonsTests: XCTestCase {
    private func addon(_ id: String?, _ url: String, enabled: Bool = true) -> Addon {
        let manifest: JSONValue = id.map { JSONValue.object(["id": JSONValue.string($0)]) } ?? JSONValue.object([:])
        return Addon(manifest: manifest, transportUrl: url, enabled: enabled)
    }

    private func media(_ id: String, _ type: String = "series") -> Media {
        Media.parse(.object(["id": .string(id), "type": .string(type), "name": .string("Title")]), kind: type)!
    }

    private func entry(_ t: UInt64) -> ResumeEntry {
        ResumeEntry(ms: 1, t: t)
    }

    // MARK: Desktop installFromUrl (behaviors 48)

    func testReinstallByManifestIDReplacesInPlace() {
        let list = [addon("a", "https://a.example/manifest.json"), addon("b", "https://b.example/manifest.json"), addon("c", "https://c.example/manifest.json")]
        let next = AddonInstallOrder.merged(list, installing: addon("b", "https://b2.example/manifest.json"))
        XCTAssertEqual(next.map(\.transportUrl), ["https://a.example/manifest.json", "https://b2.example/manifest.json", "https://c.example/manifest.json"])
    }

    func testReinstallBySameURLKeepsDisabledStateAndPosition() {
        let list = [addon("a", "https://a.example/manifest.json"), addon("b", "https://b.example/manifest.json", enabled: false), addon("c", "https://c.example/manifest.json")]
        let next = AddonInstallOrder.merged(list, installing: addon("b", "https://b.example/manifest.json", enabled: true))
        XCTAssertEqual(next.map(\.transportUrl), ["https://a.example/manifest.json", "https://b.example/manifest.json", "https://c.example/manifest.json"])
        XCTAssertEqual(next[1].enabled, false)
    }

    func testNewAddonWithoutMatchGoesLast() {
        let list = [addon("a", "https://a.example/manifest.json")]
        let next = AddonInstallOrder.merged(list, installing: addon("z", "https://z.example/manifest.json"))
        XCTAssertEqual(next.map(\.transportUrl), ["https://a.example/manifest.json", "https://z.example/manifest.json"])
    }

    func testAddonsWithoutManifestIDAreNotReplacedByEachOther() {
        let list = [addon(nil, "https://x.example/manifest.json"), addon(nil, "https://y.example/manifest.json")]
        let next = AddonInstallOrder.merged(list, installing: addon(nil, "https://z.example/manifest.json"))
        XCTAssertEqual(next.map(\.transportUrl), ["https://x.example/manifest.json", "https://y.example/manifest.json", "https://z.example/manifest.json"])
    }

    func testEmptyManifestIDIsNotAMatch() {
        let list = [addon("", "https://x.example/manifest.json")]
        let next = AddonInstallOrder.merged(list, installing: addon("", "https://z.example/manifest.json"))
        XCTAssertEqual(next.count, 2)
    }

    // MARK: Desktop lastPlayedEpisode (behaviors 267)

    func testLastPlayedEpisodeIsTheNewestEntryOfThisSeries() {
        let entries = ["tt1|s1e2": entry(5), "tt1|s2e1": entry(9), "tt1|s0e4": entry(50), "tt10|s3e1": entry(99), "tt1|sxe2": entry(70)]
        let hit = SeriesLastPlayedEpisode.find(seriesID: "tt1", entries: entries)
        XCTAssertEqual(hit?.season, 2)
        XCTAssertEqual(hit?.episode, 1)
        XCTAssertEqual(hit?.entry.t, 9)
    }

    func testLastPlayedEpisodeIgnoresMoviesAndEmptySeries() {
        XCTAssertNil(SeriesLastPlayedEpisode.find(seriesID: "tt1", entries: [:]))
        XCTAssertNil(SeriesLastPlayedEpisode.find(seriesID: "tt1", entries: ["tt1": entry(3), "tt1|s0e0": entry(4)]))
    }

    func testLastPlayedEpisodeTieKeepsTheFirstKeyInOrder() {
        let hit = SeriesLastPlayedEpisode.find(seriesID: "tt1", entries: ["tt1|s2e1": entry(9), "tt1|s1e1": entry(9)])
        XCTAssertEqual(hit?.season, 1)
    }

    // MARK: Desktop addon catalogs (behaviors 63)

    func testAddonCatalogTypeIsNotContent() {
        XCTAssertFalse(AddonCatalogRules.isContentType("addon_catalog"))
        XCTAssertFalse(AddonCatalogRules.isContentType("Addon_Catalog"))
        XCTAssertTrue(AddonCatalogRules.isContentType("movie"))
    }

    func testCatalogDiscoveryKeepsFirstNormalizedNamePerKindAndAllowsAll() {
        func row(_ key: String, _ title: String, _ kind: String = "movie", empty: Bool = false) -> CatalogRow {
            let source = addon("test", "https://example.com/manifest.json")
            let plan = RequestPlan(key: key, url: source.transportUrl, title: title, kind: kind,
                addon: source, addonPriority: 0, timeoutMs: 8_000, catalog: nil)
            return CatalogRow(plan: plan, metas: empty ? [] : [media(key, kind)])
        }
        let rows = [row("empty", "Popular", empty: true), row("one", "Popular Movies!"), row("two", "popular"),
                    row("other-kind", "Popular TV Shows", "series"), row("distinct", "Most popular")]
        XCTAssertEqual(AddonCatalogRules.discoveredRows(rows).map(\.id), ["one", "other-kind", "distinct"])
        XCTAssertEqual(AddonCatalogRules.discoveredRows(rows, showAll: true).map(\.id), ["one", "two", "other-kind", "distinct"])
        XCTAssertEqual(AddonCatalogRules.normalizedName("MOVIES_2", kind: "movie"), "movies 2::movie")
    }

    func testLegacyCatalogCapabilitiesSurviveNativeRequestPlanning() async throws {
        let manifest: JSONValue = .object([
            "id": .string("legacy"), "name": .string("Legacy"),
            "catalogs": .array([.object([
                "id": .string("search"), "name": .string("Search"), "type": .string("movie"),
                "extraSupported": .array([.string("search"), .string("skip"), .null])
            ])])
        ])
        let core = CoreBridge()
        let addon: Addon = try await core.call("installAddon", ["url": .string("https://example.com/manifest.json"), "manifest": manifest])
        let plans: [RequestPlan] = try await core.call("catalogs", ["addons": try .encoded([addon]),
            "search": .string("test"), "genre": .null, "skip": .integer(20)])
        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plans.count, 1)
        XCTAssertTrue(plan.url.hasSuffix("/search=test&skip=20.json"))
        XCTAssertEqual(plan.catalog?.supports("skip"), true)
        XCTAssertEqual(plan.catalog?.supports("search"), true)
    }

    func testSeriesBaseIDStripsEpisodeSuffixOnlyForSeriesAndAnime() {
        XCTAssertEqual(AddonCatalogRules.seriesBaseID(id: "tt1:1:2", type: "series"), "tt1")
        XCTAssertEqual(AddonCatalogRules.seriesBaseID(id: "tt1:1:2", type: "anime"), "tt1")
        XCTAssertEqual(AddonCatalogRules.seriesBaseID(id: "tt1:1:2", type: "movie"), "tt1:1:2")
    }

    func testEpisodeMetasCollapseToOneSeriesEntry() {
        let collapsed = AddonCatalogRules.collapseEpisodeMetas([media("tt1:1:1"), media("tt1:1:2"), media("tt2"), media("tt1:2:1")])
        XCTAssertEqual(collapsed.map(\.id), ["tt1", "tt2"])
    }

    func testUniqueMetasAreUnchanged() {
        let metas = [media("tt1"), media("tt2")]
        XCTAssertEqual(AddonCatalogRules.collapseEpisodeMetas(metas).map(\.id), ["tt1", "tt2"])
    }

    // MARK: Desktop Continue Watching merge (behaviors 266)

    func testCloudAnimeLeavesTheCloudListOnlyWhileTheLocalCopyIsShown() {
        XCTAssertFalse(ContinueWatchingSortRules.keepsCloudRecord(id: "kitsu:1", localVisible: true))
        XCTAssertFalse(ContinueWatchingSortRules.keepsCloudRecord(id: "anilist:3", localVisible: true))
        XCTAssertTrue(ContinueWatchingSortRules.keepsCloudRecord(id: "kitsu:1", localVisible: false))
        XCTAssertTrue(ContinueWatchingSortRules.keepsCloudRecord(id: "tt1", localVisible: true))
    }

    func testSortKeyTakesTheNewerResumeTimestamp() {
        XCTAssertEqual(ContinueWatchingSortRules.sortKey(activity: 5, resumeTimestamp: 9), 9)
        XCTAssertEqual(ContinueWatchingSortRules.sortKey(activity: 5, resumeTimestamp: 1), 5)
        XCTAssertEqual(ContinueWatchingSortRules.sortKey(activity: 5, resumeTimestamp: nil), 5)
    }
}
