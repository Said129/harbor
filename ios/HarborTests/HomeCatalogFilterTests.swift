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
}
