import XCTest
@testable import Harbor

final class R23TrackersTests: XCTestCase {
    // MARK: AniList and MyAnimeList watched rule

    func testProgressMarksTheFirstAiredEpisodes() {
        let keys = TrackerListWatched.watchedKeys(completed: false, progress: 2, total: 12, airedKeys: ["1:1", "1:2", "1:3"])
        XCTAssertEqual(keys, ["1:1", "1:2"])
    }

    func testCompletedMarksEveryAiredEpisodeWithinTheTotal() {
        XCTAssertEqual(TrackerListWatched.watchedKeys(completed: true, progress: 0, total: 2, airedKeys: ["1:1", "1:2", "1:3"]), ["1:1", "1:2"])
        XCTAssertEqual(TrackerListWatched.watchedKeys(completed: true, progress: 0, total: nil, airedKeys: ["1:1", "1:2", "1:3"]), ["1:1", "1:2", "1:3"])
    }

    func testProgressIsCappedAndNeverNegative() {
        XCTAssertEqual(TrackerListWatched.watchedKeys(completed: false, progress: 9, total: 12, airedKeys: ["1:1", "1:2"]), ["1:1", "1:2"])
        XCTAssertEqual(TrackerListWatched.watchedKeys(completed: false, progress: -1, total: nil, airedKeys: ["1:1"]), [])
    }

    func testAniListEntryIsFoundByAniListAndMyAnimeListIDs() {
        let media = AniListListMedia(id: 10, idMal: 20, romaji: "Show", english: nil, userPreferred: nil, format: "TV", episodes: 12,
                                     poster: nil, background: nil, description: nil, seasonYear: nil, averageScore: nil)
        let entries = TrackerListWatched.aniListProgress([AniListListEntry(status: .current, progress: 3, media: media)])
        XCTAssertEqual(entries["anilist:10"], TrackerListWatched.Progress(completed: false, progress: 3, total: 12))
        XCTAssertEqual(entries["mal:20"], entries["anilist:10"])
    }

    func testMyAnimeListEntryUsesItsWatchedCount() {
        let media = MALListMedia(id: 30, title: "Show", poster: nil, numEpisodes: 24, mediaType: "tv")
        let entries = TrackerListWatched.malProgress([MALListEntry(status: .completed, watched: 0, media: media)])
        XCTAssertEqual(entries["mal:30"], TrackerListWatched.Progress(completed: true, progress: 0, total: 24))
    }

    // MARK: Simkl anime grouping

    func testNormalizedTitleDropsSeasonsAndPunctuation() {
        XCTAssertEqual(SimklAnimeGrouping.normalizedTitle("Attack on Titan Season 2"), "attackontitan")
        XCTAssertEqual(SimklAnimeGrouping.normalizedTitle("Fullmetal Alchemist: Brotherhood"), "fullmetalalchemist")
        XCTAssertEqual(SimklAnimeGrouping.normalizedTitle("Naruto Shippuden"), "naruto")
    }

    func testFranchisesGroupSeasonsAndKeepTheShortestName() {
        let items = [
            SimklAnimeGrouping.Item(simklID: 2, title: "Attack on Titan Season 2", year: 2017),
            SimklAnimeGrouping.Item(simklID: 1, title: "Attack on Titan", year: 2013),
            SimklAnimeGrouping.Item(simklID: 3, title: "Naruto", year: 2002),
        ]
        XCTAssertEqual(SimklAnimeGrouping.franchises(items), [
            SimklAnimeGrouping.Franchise(key: "attackontitan", name: "Attack on Titan", simklIDs: [1, 2], yearStart: 2013, yearEnd: 2017),
            SimklAnimeGrouping.Franchise(key: "naruto", name: "Naruto", simklIDs: [3], yearStart: 2002, yearEnd: 2002),
        ])
    }

    func testYearRangeAndAverageRating() {
        XCTAssertEqual(SimklAnimeGrouping.yearRange(start: 2013, end: 2017), "2013-2017")
        XCTAssertEqual(SimklAnimeGrouping.yearRange(start: 2013, end: 2013), "2013")
        XCTAssertEqual(SimklAnimeGrouping.yearRange(start: nil, end: 2001), "2001")
        XCTAssertEqual(SimklAnimeGrouping.yearRange(start: nil, end: nil), "")
        let ratings: [Int: Double] = [1: 8, 2: 6, 3: 0]
        XCTAssertEqual(SimklAnimeGrouping.averageRating(simklIDs: [1, 2, 3], rating: { ratings[$0] }), 7)
        XCTAssertNil(SimklAnimeGrouping.averageRating(simklIDs: [3, 4], rating: { ratings[$0] }))
    }

    // MARK: Trakt comment requests

    func testTraktCommentRequestBodiesAndPaths() {
        XCTAssertEqual(TraktCommentRequests.postBody(.movie("tt1"), comment: "Great", spoiler: true), JSONValue.object([
            "comment": .string("Great"), "spoiler": .bool(true), "review": .bool(false), "share": .bool(false),
            "movie": .object(["ids": .object(["imdb": .string("tt1")])]),
        ]))
        XCTAssertEqual(TraktCommentRequests.likePath(42), "/comments/42/like")
        XCTAssertEqual(TraktCommentRequests.deletePath(42), "/comments/42")
        XCTAssertEqual(TraktCommentRequests.ratingPath(.show("tt2")), "/shows/tt2/rating")
    }

    func testTraktRatingNeedsTheTMDBID() {
        XCTAssertNil(TraktCommentRequests.ratingBody(.movie("tt1"), tmdb: nil, rating: 9))
        XCTAssertEqual(TraktCommentRequests.ratingBody(.movie("tt1"), tmdb: 603, rating: 9), JSONValue.object([
            "movies": .array([.object(["rating": .integer(9), "ids": .object(["tmdb": .integer(603)])])]),
        ]))
    }
}
