import XCTest
@testable import Harbor

/// Desktop's Catalogs pins and hidden catalogs (`catalogs.tsx`, `catalogs/use-catalog-list.ts`, `catalogs/catalog-manage-list.tsx`).
final class CatalogPinsTests: XCTestCase {
    private let addonID = "org.owned"

    private func row(_ catalogID: String, kind: String = "movie") -> CatalogRow {
        let definition = CatalogDefinition(id: catalogID, type: kind, name: catalogID, extra: [])
        let manifest: JSONValue = .object(["id": .string(addonID), "name": .string("Owned")])
        let addon = Addon(manifest: manifest, transportUrl: "https://example.org/owned/manifest.json", enabled: true)
        let plan = RequestPlan(key: addonID + ":" + kind + ":" + catalogID, url: "https://example.org/owned/catalog/" + catalogID + ".json", title: catalogID, kind: kind, addon: addon, addonPriority: 0, timeoutMs: 8_000, catalog: definition)
        return CatalogRow(plan: plan, metas: [])
    }

    private func ids(_ rows: [CatalogRow]) -> [String] {
        rows.compactMap { (row: CatalogRow) -> String? in row.plan.catalog?.id }
    }

    func testCatalogKeyUsesManifestIDTypeAndCatalogID() {
        XCTAssertEqual(HomeCatalogFilter.catalogKey(row("top")), "org.owned-movie-top")
        XCTAssertEqual(HomeCatalogFilter.catalogKey(row("top", kind: "series")), "org.owned-series-top")
        XCTAssertFalse(HomeCatalogFilter.catalogKey(row("top")).contains("https"))
    }

    func testToggledAddsThenRemovesAKey() {
        XCTAssertEqual(HomeCatalogFilter.toggled([], "a"), ["a"])
        XCTAssertEqual(HomeCatalogFilter.toggled(["a", "b"], "a"), ["b"])
        XCTAssertEqual(HomeCatalogFilter.toggled(["a"], "b"), ["a", "b"])
    }

    func testMovingPinSwapsWithNeighbourAndStopsAtEdges() {
        XCTAssertEqual(HomeCatalogFilter.movingPin(["a", "b", "c"], "b", by: -1), ["b", "a", "c"])
        XCTAssertEqual(HomeCatalogFilter.movingPin(["a", "b", "c"], "b", by: 1), ["a", "c", "b"])
        XCTAssertEqual(HomeCatalogFilter.movingPin(["a", "b"], "a", by: -1), ["a", "b"])
        XCTAssertEqual(HomeCatalogFilter.movingPin(["a", "b"], "b", by: 1), ["a", "b"])
        XCTAssertEqual(HomeCatalogFilter.movingPin(["a"], "z", by: 1), ["a"])
    }

    func testPinnedRowsFollowPinnedOrderAndSkipStaleKeys() {
        let rows = [row("top"), row("pop"), row("new")]
        let sections = HomeCatalogFilter.catalogSections(rows, pinned: ["org.owned-movie-new", "org.owned-movie-gone", "org.owned-movie-top"], hidden: [])
        XCTAssertEqual(ids(sections.pinned), ["new", "top"])
        XCTAssertEqual(ids(sections.rest), ["pop"])
    }

    func testPinnedRowStaysInPinnedSectionWhenHidden() {
        let rows = [row("top"), row("pop")]
        let sections = HomeCatalogFilter.catalogSections(rows, pinned: ["org.owned-movie-top"], hidden: ["org.owned-movie-top"])
        XCTAssertEqual(ids(sections.pinned), ["top"])
        XCTAssertEqual(ids(sections.rest), ["pop"])
    }

    func testRestDropsPinnedAndHiddenRowsKeepingOrder() {
        let rows = [row("top"), row("pop"), row("new"), row("old")]
        let sections = HomeCatalogFilter.catalogSections(rows, pinned: ["org.owned-movie-top"], hidden: ["org.owned-movie-pop"])
        XCTAssertEqual(ids(sections.rest), ["new", "old"])
    }

    func testHiddenCountCountsAllGivenRowsAndIgnoresUnknownKeys() {
        let rows = [row("top"), row("pop"), row("new")]
        XCTAssertEqual(HomeCatalogFilter.hiddenCount(rows, hidden: ["org.owned-movie-top", "org.owned-movie-pop"]), 2)
        XCTAssertEqual(HomeCatalogFilter.hiddenCount(rows, hidden: ["org.owned-movie-missing"]), 0)
        XCTAssertEqual(HomeCatalogFilter.hiddenCount([row("pop")], hidden: ["org.owned-movie-top", "org.owned-movie-pop"]), 1)
    }

    func testCatalogPreferenceKeysAreKeptPerProfile() {
        XCTAssertTrue(ProfileSettingsStore.keys.contains("catalogsPinned"))
        XCTAssertTrue(ProfileSettingsStore.keys.contains("catalogsHidden"))
        XCTAssertTrue(ProfileSettingsStore.keys.contains("homeShowAllAddonRows"))
    }
}
