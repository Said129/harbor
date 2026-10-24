import XCTest
@testable import Harbor

final class DesktopPageLayoutTests: XCTestCase {
    func testDesktopHomePullTranslatesRealRowIDsOptionsAndExplicitRankChoicesWithoutChangingMobileOnlyRows() throws {
        let map = DesktopPageRowMap(page: "home")
        let raw: JSONValue = .object(["order": .array([.string("cm-drama"), .string("future-row"), .string("tmdb-trending-movies")]),
            "hidden": .array([.string("anime-airing")]), "renamed": .object(["cm-drama": .string("Drama familiar")]),
            "numerals": .array([.string("cm-drama")]), "heroSource": .string("tmdb-trending-movies"),
            "playButtonSquare": .bool(true), "secondaryMoreInfo": .bool(true), "cwTop": .bool(true)])
        var local = PageLayout(); local.order = ["local-only", "discovery-tmdb-trending-movies", "discovery-cm-drama"]
        local.hidden = ["local-only"]; local.renamed = ["local-only": "Device row"]; local.numerals = ["local-only"]
        let value = try DesktopPageLayout(page: "home", raw: raw).native(preserving: local, mapping: map)
        XCTAssertEqual(value.order, ["local-only", "discovery-cm-drama", "discovery-tmdb-trending-movies"])
        XCTAssertEqual(value.hidden, ["local-only", "discovery-anime-airing"])
        XCTAssertEqual(value.renamed, ["local-only": "Device row", "discovery-cm-drama": "Drama familiar"])
        XCTAssertEqual(value.numerals, ["local-only", "discovery-cm-drama"])
        XCTAssertTrue(value.plain.contains("discovery-cm-top-movies")); XCTAssertFalse(value.plain.contains("discovery-cm-drama"))
        XCTAssertEqual(value.heroSource, "discovery-tmdb-trending-movies")
        XCTAssertTrue(value.playButtonSquare); XCTAssertTrue(value.secondaryMoreInfo); XCTAssertTrue(value.cwTop)
    }

    func testEditingHomePreservesUnsupportedRowsListsCustomSourcesFutureFieldsAndUnchangedLongDesktopNames() throws {
        let map = DesktopPageRowMap(page: "home"), longName = String(repeating: "A", count: 140)
        let custom: JSONValue = .array([.object(["id": .string("folder-owned"), "type": .string("future-source"), "future": .integer(7)])])
        let raw: JSONValue = .object(["order": .array([.string("cm-drama"), .string("future-row"), .string("cm-comedy")]),
            "hidden": .array([.string("future-hidden"), .string("cm-drama")]),
            "renamed": .object(["future-row": .string("Keep me"), "cm-drama": .string(longName)]),
            "numerals": .array([.string("future-rank")]), "heroSource": .string("future-hero"),
            "customSources": custom, "listRows": .array([.string("owned-list")]), "futureSetting": .object(["version": .integer(3)])])
        let desktop = try DesktopPageLayout(page: "home", raw: raw)
        var local = desktop.native(preserving: PageLayout(), mapping: map)
        local.order = ["discovery-cm-comedy", "discovery-cm-drama"]; local.hidden.remove("discovery-cm-drama")
        local.renamed["discovery-cm-comedy"] = "Comedias"; local.numerals.insert("discovery-cm-comedy"); local.cwTop = true
        let result = try desktop.applying(local, mapping: map).raw
        XCTAssertEqual(result["order"], .array([.string("cm-comedy"), .string("future-row"), .string("cm-drama")]))
        XCTAssertEqual(result["hidden"], .array([.string("future-hidden")]))
        XCTAssertEqual(result["renamed"]["cm-drama"], .string(longName)); XCTAssertEqual(result["renamed"]["cm-comedy"], .string("Comedias"))
        XCTAssertEqual(result["renamed"]["future-row"], raw["renamed"]["future-row"])
        XCTAssertEqual(result["numerals"], .array([.string("future-rank"), .string("cm-comedy")]))
        XCTAssertEqual(result["heroSource"], .string("future-hero")); XCTAssertEqual(result["customSources"], custom)
        XCTAssertEqual(result["listRows"], raw["listRows"]); XCTAssertEqual(result["futureSetting"], raw["futureSetting"])
        XCTAssertEqual(result["cwTop"], .bool(true))
    }

    func testAnimeUsesEveryOriginalSpecKeyAndSpecialAniListAndAwardKeysButDoesNotPublishItsHeroOrHomeOptions() throws {
        let map = DesktopPageRowMap(page: "anime"), specs = try DesktopAnimeRows.read().rows
        XCTAssertEqual(specs.count, 20)
        for spec in specs { XCTAssertEqual(map.desktop("discovery-anime-" + spec.key), spec.key) }
        XCTAssertEqual(map.desktop("discovery-anilist-trending"), "anilistTrending")
        XCTAssertEqual(map.desktop("discovery-anilist-top100"), "anilistTop100")
        XCTAssertEqual(map.desktop("discovery-anime-awards"), "awards"); XCTAssertNil(map.desktop("discovery-anime-picks"))
        let raw: JSONValue = .object(["order": .array([.string("continueWatching"), .string("anilistTop100"), .string("airing"), .string("yourMalLists")]),
            "hidden": .array([.string("yourAnilistLists")]), "renamed": .object(["continueWatching": .string("Continuar")]), "future": .integer(4)])
        let desktop = try DesktopPageLayout(page: "anime", raw: raw)
        var local = desktop.native(preserving: PageLayout(), mapping: map)
        local.order = ["discovery-anime-airing", "discovery-anilist-top100"]; local.playButtonSquare = true
        local.cwTop = true; local.heroSource = "discovery-anilist-top100"
        let result = try desktop.applying(local, mapping: map).raw
        XCTAssertEqual(result["order"], .array([.string("continueWatching"), .string("airing"), .string("anilistTop100"), .string("yourMalLists")]))
        XCTAssertEqual(result["hidden"], raw["hidden"]); XCTAssertEqual(result["renamed"], raw["renamed"])
        XCTAssertEqual(result["future"], .integer(4)); XCTAssertEqual(result["playButtonSquare"], .null)
        XCTAssertEqual(result["cwTop"], .null); XCTAssertEqual(result["heroSource"], .null)
    }

    func testConfiguredAddonInstancesShareOnlyPublicDesktopIdentityAndNeverSerializeTheirConfigurationURLs() throws {
        let first = catalog("https://addon.example/private-first/config-token/manifest.json", key: "request-private-first")
        let second = catalog("https://addon.example/private-second/other-token/manifest.json", key: "request-private-second")
        let home = DesktopPageRowMap(page: "home", rails: [first, second]), anime = DesktopPageRowMap(page: "anime", rails: [first, second])
        XCTAssertEqual(home.desktop(first.id), "org.owned.catalog-series-anime")
        XCTAssertEqual(anime.desktop(first.id), "addon:org.owned.catalog-series-anime")
        XCTAssertEqual(Set(home.native("org.owned.catalog-series-anime")), [first.id, second.id])
        let desktop = try DesktopPageLayout(page: "anime", raw: .object(["hidden": .array([.string("addon:org.owned.catalog-series-anime")])]))
        var local = desktop.native(preserving: PageLayout(), mapping: anime)
        XCTAssertTrue(local.hidden.contains(first.id)); XCTAssertTrue(local.hidden.contains(second.id))
        local.order = [second.id, first.id]
        let result = try desktop.applying(local, mapping: anime).raw
        XCTAssertEqual(result["order"], .array([.string("addon:org.owned.catalog-series-anime")]))
        let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        for privateValue in ["private-first", "private-second", "config-token", "other-token", "request-private"] { XCTAssertFalse(encoded.contains(privateValue)) }
    }

    func testLateCatalogRegistrationCanReprojectAnUnchangedShadowWithoutDroppingAnUnknownProvider() throws {
        let row = catalog("https://addon.example/owned/manifest.json", key: "request-owned")
        var map = DesktopPageRowMap(page: "home")
        let raw: JSONValue = .object(["hidden": .array([.string("org.owned.catalog-series-anime")]), "renamed": .object(["org.owned.catalog-series-anime": .string("Anime de casa")])])
        let desktop = try DesktopPageLayout(page: "home", raw: raw)
        let before = desktop.native(preserving: PageLayout(), mapping: map)
        XCTAssertFalse(before.hidden.contains(row.id)); map.register([row])
        let after = desktop.native(preserving: before, mapping: map)
        XCTAssertTrue(after.hidden.contains(row.id)); XCTAssertEqual(after.renamed[row.id], "Anime de casa")
        XCTAssertEqual(try desktop.applying(after, mapping: map).raw["hidden"], raw["hidden"])
    }

    func testMalformedLayoutNeverBecomesDefaultsAndNativeOnlyIDsNeverEnterTheWire() throws {
        for raw: JSONValue in [.null, .array([]), .object(["order": .string("wrong")]), .object(["hidden": .array([.integer(7)])]),
            .object(["renamed": .object(["cm-drama": .bool(false)])]), .object(["cwTop": .string("yes")]), .object(["heroSource": .integer(1)])] {
            XCTAssertThrowsError(try DesktopPageLayout(page: "home", raw: raw))
        }
        XCTAssertThrowsError(try DesktopPageLayout(page: "movies", raw: .object([:])))
        var local = PageLayout(); local.order = ["native-secret-row"]; local.hidden = ["native-secret-row"]; local.renamed = ["native-secret-row": "Private"]
        let result = try DesktopPageLayout(page: "home", raw: .object([:])).applying(local, mapping: .init(page: "home")).raw
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(result), as: UTF8.self).contains("native-secret"))
        XCTAssertThrowsError(try DesktopPageLayout(page: "home", raw: .object([:])).applying(local, mapping: .init(page: "anime")))
    }

    private func catalog(_ url: String, key: String) -> PageRail {
        let addon = Addon(manifest: .object(["id": .string("org.owned.catalog")]), transportUrl: url, enabled: true)
        let definition = CatalogDefinition(id: "anime", type: "series", name: "Owned", extra: [])
        return .catalog(CatalogRow(plan: .init(key: key, url: url, title: "Owned", kind: "series", addon: addon, addonPriority: 0, timeoutMs: 1_000, catalog: definition), metas: []))
    }
}
