import XCTest
@testable import Harbor

/// Desktop's non-score poster badges (`components/pick-card.tsx`: DUB, New, the watchlist bookmark) and the Details row for MAL
/// (`views/detail/hero-ratings.tsx`), through the pure policy in `Services/CardTagBadges.swift`.
final class CardTagBadgesTests: XCTestCase {
    private func feedRow(malID: Int64? = nil, anilistID: Int64? = nil) -> JSONValue {
        var inner: [String: JSONValue] = [:]
        if let malID { inner["idMal"] = .integer(malID) }
        if let anilistID { inner["id"] = .integer(anilistID) }
        return .object(["media": .object(["media": .object(inner)])])
    }

    func testWatchlistPositionDefaultsToTopEnd() {
        XCTAssertEqual(CardWatchlistPosition.restored(nil), .topEnd)
        XCTAssertEqual(CardWatchlistPosition.restored("sideways"), .topEnd)
        XCTAssertEqual(CardWatchlistPosition.restored("off"), .off)
        XCTAssertEqual(CardWatchlistPosition.restored("bottomStart"), .bottomStart)
    }

    func testBookmarkShowsOnlyForSavedTitlesWithAPosition() {
        XCTAssertTrue(CardTagPolicy.showsBookmark(.topEnd, bookmarked: true))
        XCTAssertFalse(CardTagPolicy.showsBookmark(.off, bookmarked: true))
        XCTAssertFalse(CardTagPolicy.showsBookmark(.topEnd, bookmarked: false))
        XCTAssertNil(CardTagPolicy.bookmarkPlacement(.off, tagCount: 0))
    }

    func testBookmarkCornersMatchDesktop() {
        XCTAssertEqual(CardTagPolicy.bookmarkPlacement(.topEnd, tagCount: 0), CardBookmarkPlacement(isTop: true, isStart: false, topInset: 6))
        XCTAssertEqual(CardTagPolicy.bookmarkPlacement(.bottomStart, tagCount: 0), CardBookmarkPlacement(isTop: false, isStart: true, topInset: 0))
        XCTAssertEqual(CardTagPolicy.bookmarkPlacement(.bottomEnd, tagCount: 2), CardBookmarkPlacement(isTop: false, isStart: false, topInset: 0))
    }

    func testTopStartBookmarkStacksBelowTags() {
        XCTAssertEqual(CardTagPolicy.bookmarkPlacement(.topStart, tagCount: 0)?.topInset, 6)
        XCTAssertEqual(CardTagPolicy.bookmarkPlacement(.topStart, tagCount: 1)?.topInset, 34)
        XCTAssertEqual(CardTagPolicy.bookmarkPlacement(.topStart, tagCount: 2)?.topInset, 62)
        XCTAssertEqual(CardTagPolicy.circleTop(9), 118)
    }

    func testNewTagNeedsTheExactCurrentYear() {
        XCTAssertTrue(CardTagPolicy.isNew(releaseInfo: "2026", year: 2026))
        XCTAssertFalse(CardTagPolicy.isNew(releaseInfo: "2025", year: 2026))
        XCTAssertFalse(CardTagPolicy.isNew(releaseInfo: "2026–", year: 2026))
        XCTAssertFalse(CardTagPolicy.isNew(releaseInfo: nil, year: 2026))
    }

    func testDubComesBeforeNewWhenBothShow() {
        let tags = CardTagPolicy.tags(id: "mal:5", releaseInfo: "2026", year: 2026, showsCardTags: true, showsDub: true, hasDub: true)
        XCTAssertEqual(tags, [.dub, .new])
        XCTAssertLessThanOrEqual(tags.count, CardTagPolicy.maximumTags)
    }

    func testShowTagsOffRemovesNewButNotDub() {
        XCTAssertEqual(CardTagPolicy.tags(id: "anilist:21", releaseInfo: "2026", year: 2026, showsCardTags: false, showsDub: true, hasDub: true), [.dub])
        XCTAssertEqual(CardTagPolicy.tags(id: "tt0111161", releaseInfo: "2026", year: 2026, showsCardTags: true, showsDub: true, hasDub: true), [.new])
    }

    func testDubNeedsAnimeIDAndSettingAndFeedMatch() {
        XCTAssertEqual(CardTagPolicy.tags(id: "tt0111161", releaseInfo: nil, year: 2026, showsCardTags: true, showsDub: true, hasDub: true), [])
        XCTAssertEqual(CardTagPolicy.tags(id: "mal:5", releaseInfo: nil, year: 2026, showsCardTags: true, showsDub: false, hasDub: true), [])
        XCTAssertEqual(CardTagPolicy.tags(id: "mal:5", releaseInfo: nil, year: 2026, showsCardTags: true, showsDub: true, hasDub: false), [])
    }

    func testAnimeCardIDPrefixes() {
        for id in ["kitsu:1", "mal:2", "anilist:3", "anidb:4", "simkl:5"] {
            XCTAssertTrue(CardTagPolicy.isAnimeCardID(id), id)
        }
        XCTAssertFalse(CardTagPolicy.isAnimeCardID("tt0111161"))
        XCTAssertFalse(CardTagPolicy.isAnimeCardID("malx:1"))
    }

    func testDubIndexMatchesMalAndAnilistIDs() {
        let index = AnimeDubIndex(rows: [feedRow(malID: 5, anilistID: 21), feedRow(anilistID: 30)])
        XCTAssertTrue(index.hasDub("mal:5"))
        XCTAssertTrue(index.hasDub("anilist:21"))
        XCTAssertTrue(index.hasDub("anilist:30"))
        XCTAssertFalse(index.hasDub("mal:30"))
        XCTAssertFalse(index.hasDub("mal:6"))
        XCTAssertFalse(index.hasDub("kitsu:5"))
        XCTAssertFalse(index.hasDub("mal:abc"))
    }

    func testEmptyFeedHasNoDub() {
        XCTAssertFalse(AnimeDubIndex(rows: []).hasDub("mal:5"))
        XCTAssertFalse(AnimeDubIndex(rows: [feedRow()]).hasDub("mal:5"))
    }

    func testMalDetailShowsCatalogScoreUnlessHidden() {
        var anime = Media(id: "mal:5", type: "anime", name: "Test")
        anime.imdbRating = "8.4"
        let item = CardTagPolicy.malDetailItem(anime, detailHidden: [])
        XCTAssertEqual(item?.value, "8.4")
        XCTAssertEqual(item?.label, "MyAnimeList")
        XCTAssertEqual(DetailRatings.shortName("mal"), "MAL", "the detail chip prints MAL, as the card chip does")
        XCTAssertNil(CardTagPolicy.malDetailItem(anime, detailHidden: ["mal"]))
    }

    func testMalDetailNeedsAnAnimeIDAndAScore() {
        var movie = Media(id: "tt0111161", type: "movie", name: "Test")
        movie.imdbRating = "9.3"
        XCTAssertNil(CardTagPolicy.malDetailItem(movie, detailHidden: []))
        let unscored = Media(id: "kitsu:7", type: "anime", name: "Test")
        XCTAssertNil(CardTagPolicy.malDetailItem(unscored, detailHidden: []))
    }
}
