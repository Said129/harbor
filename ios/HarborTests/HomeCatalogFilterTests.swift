import XCTest
@testable import Harbor

/// Desktop's "Hide watched titles in catalogs" and "Hide unreleased titles" rules (`customizable-rows.tsx`, `playback-history.ts`).
final class HomeCatalogFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func media(_ id: String, name: String = "Title", released: String? = nil, releaseInfo: String? = nil) -> Media {
        var value = Media(id: id, type: "movie", name: name)
        value.released = released
        value.releaseInfo = releaseInfo
        return value
    }

    private func rail(_ id: String, _ metas: [Media], personal: PersonalDiscoverySource? = nil) -> DiscoveryRail {
        DiscoveryRail(id: id, title: id, kind: "movie", path: id, metas: metas, personal: personal)
    }

    func testUnreleasedByFullDate() {
        XCTAssertTrue(HomeCatalogFilter.isUnreleased(media("tt1", released: "2030-01-01T00:00:00.000Z"), now: now, calendar: utcCalendar))
        XCTAssertFalse(HomeCatalogFilter.isUnreleased(media("tt1", released: "2020-01-01T00:00:00Z"), now: now, calendar: utcCalendar))
    }

    func testUnreleasedByPlainDate() {
        XCTAssertTrue(HomeCatalogFilter.isUnreleased(media("tt1", released: "2030-06-01"), now: now, calendar: utcCalendar))
        XCTAssertFalse(HomeCatalogFilter.isUnreleased(media("tt1", released: "2020-06-01"), now: now, calendar: utcCalendar))
    }

    func testUnreleasedByYearOnlyWhenNoDate() {
        XCTAssertTrue(HomeCatalogFilter.isUnreleased(media("tt1", releaseInfo: "2031"), now: now, calendar: utcCalendar))
        XCTAssertFalse(HomeCatalogFilter.isUnreleased(media("tt1", releaseInfo: "2027"), now: now, calendar: utcCalendar))
    }

    func testUnreleasedIsFalseWithoutAnyDate() {
        XCTAssertFalse(HomeCatalogFilter.isUnreleased(media("tt1"), now: now, calendar: utcCalendar))
    }

    func testReleaseYearReadsLeadingDigits() {
        XCTAssertEqual(HomeCatalogFilter.releaseYear("2019-2023"), 2019)
        XCTAssertNil(HomeCatalogFilter.releaseYear(nil))
        XCTAssertNil(HomeCatalogFilter.releaseYear("TBA"))
    }

    func testTitleKeyForImdbTmdbAndOtherIds() {
        XCTAssertEqual(HomeCatalogFilter.titleKey("tt1234567"), "imdb:tt1234567")
        XCTAssertEqual(HomeCatalogFilter.titleKey("tmdb:movie:603"), "tmdb:603")
        XCTAssertNil(HomeCatalogFilter.titleKey("tmdb:movie:x"))
        XCTAssertNil(HomeCatalogFilter.titleKey("kitsu:1"))
        XCTAssertNil(HomeCatalogFilter.titleKey("tt"))
    }

    func testWatchTitleKeyNormalizesNames() {
        XCTAssertEqual(HomeCatalogFilter.watchTitleKey("The Office (2005)"), "theoffice")
        XCTAssertEqual(HomeCatalogFilter.watchTitleKey("Spider-Man: No Way Home"), "spidermannowayhome")
        XCTAssertEqual(HomeCatalogFilter.watchTitleKey(""), "")
        XCTAssertEqual(HomeCatalogFilter.watchTitleKey(nil), "")
    }

    func testWatchedContainsByIdKeyAndName() {
        var watched = HomeCatalogFilter.Watched()
        watched.ids.insert("tt1")
        XCTAssertTrue(watched.contains(media("tt1")))

        var byKey = HomeCatalogFilter.Watched()
        byKey.keys.insert("tmdb:603")
        XCTAssertTrue(byKey.contains(media("tmdb:movie:603")))

        var byName = HomeCatalogFilter.Watched()
        byName.names.insert("theoffice")
        XCTAssertTrue(byName.contains(media("tt9", name: "The Office (2005)")))
        XCTAssertFalse(byName.contains(media("tt10", name: "Other")))
    }

    func testApplyWithBothFlagsOffReturnsRailsUnchanged() {
        var watched = HomeCatalogFilter.Watched()
        watched.ids.insert("tt1")
        let rails = [rail("a", [media("tt1"), media("tt2")])]
        let result = HomeCatalogFilter.apply(rails, hideWatched: false, hideUnreleased: false, watched: watched, now: now)
        XCTAssertEqual(result.map(\.id), ["a"])
        XCTAssertEqual(result.first?.metas.map(\.id), ["tt1", "tt2"])
    }

    func testApplyRemovesWatchedAndUnreleasedItems() {
        var watched = HomeCatalogFilter.Watched()
        watched.ids.insert("tt1")
        let metas = [
            media("tt1", released: "2020-01-01"),
            media("tt2", released: "2030-01-01"),
            media("tt3", released: "2020-01-01"),
        ]
        let result = HomeCatalogFilter.apply([rail("a", metas)], hideWatched: true, hideUnreleased: true, watched: watched, now: now)
        XCTAssertEqual(result.first?.metas.map(\.id), ["tt3"])
    }

    func testApplyDropsEmptiedRailButKeepsPersonalRail() {
        var watched = HomeCatalogFilter.Watched()
        watched.ids.insert("tt1")
        let source = PersonalDiscoverySource(available: { true }, page: { _ in [] })
        let rails = [
            rail("plain", [media("tt1")]),
            rail("personal", [media("tt1")], personal: source),
        ]
        let result = HomeCatalogFilter.apply(rails, hideWatched: true, hideUnreleased: false, watched: watched, now: now)
        XCTAssertEqual(result.map(\.id), ["personal"])
        XCTAssertEqual(result.first?.metas.count, 0)
    }

    private func languageMedia(_ id: String, language: String?) -> Media {
        var value = media(id)
        value.originalLanguage = language
        return value
    }

    private func discoveryMetaIDs(_ rails: [PageRail]) -> [[String]] {
        rails.compactMap { (rail: PageRail) -> [String]? in
            if case .discovery(let row) = rail { return row.metas.map(\.id) }
            return nil
        }
    }

    private func watchRecord(_ id: String) -> LibraryRecord {
        LibraryRecord(raw: .object([
            "_id": .string(id), "type": .string("series"), "name": .string("Title " + id),
            "removed": .bool(false), "temp": .bool(false), "_mtime": .string("2026-10-17T10:00:00Z"),
            "state": .object(["season": .integer(1), "episode": .integer(2), "video_id": .string(id + ":1:2"), "timeOffset": .integer(1_000), "duration": .integer(100_000)])
        ]))
    }

    func testKeepsLanguageOnlyForListedOrUnknownLanguages() {
        XCTAssertTrue(HomeCatalogFilter.keepsLanguage(languageMedia("tt1", language: "en"), languages: []))
        XCTAssertTrue(HomeCatalogFilter.keepsLanguage(languageMedia("tt1", language: "ja"), languages: ["ja"]))
        XCTAssertTrue(HomeCatalogFilter.keepsLanguage(languageMedia("tt1", language: nil), languages: ["ja"]))
        XCTAssertTrue(HomeCatalogFilter.keepsLanguage(languageMedia("tt1", language: ""), languages: ["ja"]))
        XCTAssertFalse(HomeCatalogFilter.keepsLanguage(languageMedia("tt1", language: "en"), languages: ["ja"]))
    }

    func testEmptyLanguageListLeavesPageRailsUnchanged() {
        let rails: [PageRail] = [.discovery(rail("a", [languageMedia("tt1", language: "en")])), .continuing(kind: "series")]
        let result = HomeCatalogFilter.homeLanguageRails(rails, languages: [])
        XCTAssertEqual(result.map(\.id), ["discovery-a", "continueWatching"])
        XCTAssertEqual(discoveryMetaIDs(result), [["tt1"]])
    }

    func testLanguageFilterKeepsListedAndUnknownTitlesOnly() {
        let metas = [languageMedia("tt1", language: "ja"), languageMedia("tt2", language: "fr"), languageMedia("tt3", language: nil)]
        let result = HomeCatalogFilter.homeLanguageRails([.discovery(rail("a", metas))], languages: ["ja"])
        XCTAssertEqual(discoveryMetaIDs(result), [["tt1", "tt3"]])
    }

    func testLanguageFilterDropsRowsLeftEmptyButKeepsPersonalRowsAndLists() {
        let source = PersonalDiscoverySource(available: { true }, page: { _ in [] })
        let rails: [PageRail] = [
            .discovery(rail("plain", [languageMedia("tt1", language: "fr")])),
            .discovery(rail("personal", [languageMedia("tt2", language: "fr")], personal: source)),
            .continuing(kind: "series"),
        ]
        let result = HomeCatalogFilter.homeLanguageRails(rails, languages: ["ja"])
        XCTAssertEqual(result.map(\.id), ["discovery-personal", "continueWatching"])
        XCTAssertEqual(discoveryMetaIDs(result), [[]])
    }

    func testContinueWatchingLeavesAnimeOutOnlyWhenSettingIsOn() {
        let records = [watchRecord("kitsu:1"), watchRecord("tt1"), watchRecord("tt2")]
        let filtered = HomeCatalogFilter.continueWatching(records, animeOnlyInAnimeRoom: true, detectedAnime: ["tt2"])
        XCTAssertEqual(filtered.map(\.id), ["tt1"])
        let unfiltered = HomeCatalogFilter.continueWatching(records, animeOnlyInAnimeRoom: false, detectedAnime: ["tt2"])
        XCTAssertEqual(unfiltered.map(\.id), ["kitsu:1", "tt1", "tt2"])
    }

    func testAddonRowsRepeatingABuiltInRowAreMergedUnlessShowAll() {
        let addonRows = ["Trending|movie", "Mine|movie", "Trending|movie"]
        let merged = HomeCatalogFilter.uniqueAddonRows(addonRows, takenKeys: ["Trending|movie"], key: { (row: String) -> String in row }, showAll: false)
        XCTAssertEqual(merged, ["Mine|movie"])
        let all = HomeCatalogFilter.uniqueAddonRows(addonRows, takenKeys: ["Trending|movie"], key: { (row: String) -> String in row }, showAll: true)
        XCTAssertEqual(all, addonRows)
    }

    func testAddonRowsAreDeduplicatedAgainstEachOther() {
        let rows = ["Popular|series", "Popular|series", "Other|series"]
        let result = HomeCatalogFilter.uniqueAddonRows(rows, takenKeys: [], key: { (row: String) -> String in row }, showAll: false)
        XCTAssertEqual(result, ["Popular|series", "Other|series"])
    }
}
