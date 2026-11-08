import XCTest
@testable import Harbor

/// Manga, music and sports gaps closed against Desktop 0.9.132: pure decisions only, no network and no UI.
final class R22MmsTests: XCTestCase {
    private struct R22Track: Equatable {
        let id: String
        let recording: String
        let video: Bool
    }

    // MARK: Manga book spreads (Desktop book-view.tsx)

    func testSpreadSampleIndicesUseFirstAndQuartilePagesWithoutDuplicates() {
        XCTAssertEqual(MangaSpreadRules.sampleIndices(count: 0), [])
        XCTAssertEqual(MangaSpreadRules.sampleIndices(count: 1), [0])
        XCTAssertEqual(MangaSpreadRules.sampleIndices(count: 2), [0, 1])
        XCTAssertEqual(MangaSpreadRules.sampleIndices(count: 10), [0, 2, 5, 7])
    }

    func testRepresentativeAspectIsLowerMedianOfValidMeasurements() {
        XCTAssertEqual(MangaSpreadRules.representativeAspect([]), 1.4, accuracy: 0.0001)
        XCTAssertEqual(MangaSpreadRules.representativeAspect([0.1, 7]), 1.4, accuracy: 0.0001)
        XCTAssertEqual(MangaSpreadRules.representativeAspect([1.4, 1.5, 0.9, 1.6]), 1.4, accuracy: 0.0001)
        XCTAssertEqual(MangaSpreadRules.representativeAspect([1.0, 1.5]), 1.0, accuracy: 0.0001)
    }

    func testSinglePageModeOpensWideAndTallPagesAlone() {
        XCTAssertFalse(MangaSpreadRules.singlePageMode(aspect: 1.4, isMobile: false))
        XCTAssertTrue(MangaSpreadRules.singlePageMode(aspect: 1.1, isMobile: false))
        XCTAssertTrue(MangaSpreadRules.singlePageMode(aspect: 2.0, isMobile: false))
        XCTAssertFalse(MangaSpreadRules.singlePageMode(aspect: 1.2, isMobile: false))
        XCTAssertFalse(MangaSpreadRules.singlePageMode(aspect: 1.9, isMobile: false))
        XCTAssertTrue(MangaSpreadRules.singlePageMode(aspect: 1.4, isMobile: true))
    }

    // MARK: Manga Suwayomi categories (Desktop provider.ts categoryTags)

    func testCategoriesKeepNumericIdsAndSortByServerOrder() throws {
        let json = #"[{"id":2,"name":"B","order":2},{"id":"1","name":"A","order":1},{"id":"x","name":"bad","order":0},{"id":3,"name":"C"},{"id":-1,"name":"neg","order":0},{"id":4,"order":0},{"id":"2","name":"Duplicate","order":4}]"#
        let values = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)).array
        XCTAssertEqual(MangaCategoryRules.categories(from: values), [
            MangaCategory(id: "3", name: "C"),
            MangaCategory(id: "1", name: "A"),
            MangaCategory(id: "2", name: "B"),
        ])
    }

    func testCategoryOrderAcceptsStringsAndFallsBackToZero() {
        XCTAssertEqual(MangaCategoryRules.orderValue(.string("4")), 4)
        XCTAssertEqual(MangaCategoryRules.orderValue(.string("nope")), 0)
        XCTAssertEqual(MangaCategoryRules.orderValue(.null), 0)
        XCTAssertEqual(MangaCategoryRules.digitsID(.number(3)), "3")
        XCTAssertNil(MangaCategoryRules.digitsID(.number(3.5)))
    }

    func testSavedCategorySearchMatchesTitlesAndDeduplicatesAfterFiltering() {
        let other = MangaBook(id: "1", title: "Unrelated title", author: "Harbor")
        let match = MangaBook(id: "1", title: "Harbor Vol. 1")
        let duplicate = MangaBook(id: "1", title: "Harbor duplicate")
        let second = MangaBook(id: "2", title: "HARBOR Vol. 2")
        XCTAssertEqual(MangaCategoryRules.books([other, match, duplicate, second], matching: " harbor "), [match, second])
        XCTAssertEqual(MangaCategoryRules.books([other, match, duplicate, second], matching: ""), [other, second])
    }

    func testMangaRepositoryURLsUseDesktopIndexRulesAndRejectCredentials() {
        XCTAssertEqual(MangaExtensionRepository.indexURL(for: " https://github.com/acme/manga.git "),
                       "https://raw.githubusercontent.com/acme/manga/repo/index.min.json")
        XCTAssertEqual(MangaExtensionRepository.indexURL(for: "https://github.com/acme/manga/tree/main"),
                       "https://raw.githubusercontent.com/acme/manga/main/index.min.json")
        XCTAssertEqual(MangaExtensionRepository.indexURL(for: "https://host.example/shelf/"),
                       "https://host.example/shelf/index.min.json")
        XCTAssertEqual(MangaExtensionRepository.indexURL(for: "https://host.example/index.json?format=1"),
                       "https://host.example/index.json?format=1")
        XCTAssertNil(MangaExtensionRepository.indexURL(for: "https://user@host.example/repo"))
        XCTAssertNil(MangaExtensionRepository.indexURL(for: "file:///repo/index.json"))
    }

    // MARK: Music queue continuation (Desktop queue-continuation.ts)

    func testExcludedAddsHistoryOnlyInDiscoverMode() {
        let current = R22Track(id: "c", recording: "rc", video: false)
        let queue = [R22Track(id: "q", recording: "rq", video: false)]
        let history = [R22Track(id: "h", recording: "rh", video: false)]
        XCTAssertEqual(MusicQueueContinuationRules.excluded(current: current, queue: queue, history: history, discover: false).map(\.id), ["c", "q"])
        XCTAssertEqual(MusicQueueContinuationRules.excluded(current: current, queue: queue, history: history, discover: true).map(\.id), ["c", "q", "h"])
    }

    func testFreshContinuationDropsExcludedRecordingsDuplicatesAndVideo() {
        let excluded = [R22Track(id: "c", recording: "rc", video: false)]
        let candidates = [
            R22Track(id: "a", recording: "r1", video: false),
            R22Track(id: "b", recording: "r1", video: false),
            R22Track(id: "c", recording: "rz", video: false),
            R22Track(id: "d", recording: "rc", video: false),
            R22Track(id: "v", recording: "r2", video: true),
            R22Track(id: "e", recording: "r3", video: false),
        ]
        let kept = MusicQueueContinuationRules.fresh(candidates, excluded: excluded, allowVideo: false,
                                                     isVideo: { $0.video }, key: { $0.id }, recording: { $0.recording })
        XCTAssertEqual(kept.map(\.id), ["a", "e"])
        let withVideo = MusicQueueContinuationRules.fresh(candidates, excluded: excluded, allowVideo: true,
                                                          isVideo: { $0.video }, key: { $0.id }, recording: { $0.recording })
        XCTAssertEqual(withVideo.map(\.id), ["a", "v", "e"])
    }

    // MARK: Music local folder rescan (Desktop local/scan.rs)

    func testModifiedSecondsMatchesDesktopWholeSecondsRule() {
        XCTAssertEqual(MusicFolderRescanRules.modifiedSeconds(nil), 0)
        XCTAssertEqual(MusicFolderRescanRules.modifiedSeconds(Date(timeIntervalSince1970: -5)), 0)
        XCTAssertEqual(MusicFolderRescanRules.modifiedSeconds(Date(timeIntervalSince1970: 1_700_000_000.9)), 1_700_000_000)
    }

    func testUnchangedFileNeedsSameSizeAndModifiedTime() {
        XCTAssertTrue(MusicFolderRescanRules.unchanged(knownSize: 100, knownModified: 5, size: 100, modified: 5))
        XCTAssertFalse(MusicFolderRescanRules.unchanged(knownSize: 100, knownModified: 5, size: 101, modified: 5))
        XCTAssertFalse(MusicFolderRescanRules.unchanged(knownSize: 100, knownModified: 5, size: 100, modified: 6))
        XCTAssertFalse(MusicFolderRescanRules.unchanged(knownSize: nil, knownModified: nil, size: 100, modified: 5))
    }

    func testPruneRemovesIndexedPathsTheScanDidNotSee() {
        XCTAssertEqual(MusicFolderRescanRules.removedPaths(indexed: ["a", "b", "c"], seen: ["a", "c"]), ["b"])
    }

    // MARK: Sports home team (Desktop favourites.ts setHomeTeam and toggleFavouriteTeam)

    func testToggledHomeSetsReplacesAndClearsPerGroup() {
        var home: [String: String] = [:]
        home = SportsRules.toggledHome(home, group: "soccer", id: "epl:1")
        XCTAssertEqual(home, ["soccer": "epl:1"])
        home = SportsRules.toggledHome(home, group: "soccer", id: "epl:2")
        XCTAssertEqual(home, ["soccer": "epl:2"])
        home = SportsRules.toggledHome(home, group: "soccer", id: "epl:2")
        XCTAssertEqual(home, [:])
    }

    func testUnfavouriteClearsOnlyTheHomeSlotOfThatTeam() {
        let home = ["soccer": "epl:1", "basketball": "nba:9"]
        XCTAssertEqual(SportsRules.homeAfterUnfavourite(home, group: "soccer", id: "epl:1"), ["basketball": "nba:9"])
        XCTAssertEqual(SportsRules.homeAfterUnfavourite(home, group: "soccer", id: "epl:2"), home)
    }

    func testLegacySportsPreferencesDecodeWithoutHomeKey() throws {
        let legacy = Data(#"{"leagues":["EPL"],"favorites":["epl:1"]}"#.utf8)
        let decoded = try JSONDecoder().decode(SportsPersonalization.self, from: legacy)
        XCTAssertEqual(decoded.leagues, ["EPL"])
        XCTAssertEqual(decoded.favorites, ["epl:1"])
        XCTAssertEqual(decoded.home, [:])
        let empty = try JSONDecoder().decode(SportsPersonalization.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.leagues, SportsPersonalization().leagues)
    }

    private func sportsEvent(_ id: String, state: String, at seconds: TimeInterval,
                             home: (String, String?, Bool), away: (String, String?, Bool)) -> SportsEvent {
        SportsEvent(id: id, eventID: id,
                    league: SportsLeague(id: "epl", title: "EPL", path: "soccer/eng.1", group: "soccer", logo: nil),
                    title: home.0 + " v " + away.0, date: Date(timeIntervalSince1970: seconds), state: state, status: "",
                    sides: [SportsSide(id: "h", name: home.0, logo: nil, score: home.1, winner: home.2),
                            SportsSide(id: "a", name: away.0, logo: nil, score: away.1, winner: away.2)],
                    venue: "", broadcasts: [], link: nil)
    }

    func testSportsOutcomeFollowsWinnerFlagsThenScores() {
        let win = sportsEvent("1", state: "post", at: 100, home: ("Arsenal", "2", false), away: ("Chelsea", "1", false))
        XCTAssertEqual(SportsRules.outcome(win, team: "arsenal"), .win)
        XCTAssertEqual(SportsRules.outcome(win, team: "Chelsea"), .loss)
        let draw = sportsEvent("2", state: "post", at: 100, home: ("A", "1", false), away: ("B", "1.0", false))
        XCTAssertEqual(SportsRules.outcome(draw, team: "A"), .draw)
        let flagged = sportsEvent("3", state: "post", at: 100, home: ("A", nil, false), away: ("B", nil, true))
        XCTAssertEqual(SportsRules.outcome(flagged, team: "A"), .loss)
        let missing = sportsEvent("4", state: "post", at: 100, home: ("A", "", false), away: ("B", "2", false))
        XCTAssertNil(SportsRules.outcome(missing, team: "A"))
        let live = sportsEvent("5", state: "in", at: 100, home: ("A", "1", false), away: ("B", "0", false))
        XCTAssertNil(SportsRules.outcome(live, team: "A"))
        XCTAssertNil(SportsRules.outcome(win, team: ""))
    }

    func testNextFixturePrefersLiveThenEarliestUpcoming() {
        let live = sportsEvent("live", state: "in", at: 500, home: ("A", nil, false), away: ("B", nil, false))
        let soon = sportsEvent("soon", state: "pre", at: 300, home: ("A", nil, false), away: ("B", nil, false))
        let later = sportsEvent("later", state: "pre", at: 400, home: ("A", nil, false), away: ("B", nil, false))
        XCTAssertEqual(SportsRules.nextFixture([later, soon, live])?.id, "live")
        XCTAssertEqual(SportsRules.nextFixture([later, soon])?.id, "soon")
        XCTAssertNil(SportsRules.nextFixture([]))
    }

    func testRecentFormReadsOldestFirstAndLastResultIsNewest() {
        let olderWin = sportsEvent("w", state: "post", at: 100, home: ("A", "1", false), away: ("B", "0", false))
        let middle = sportsEvent("d", state: "post", at: 200, home: ("A", "0", false), away: ("B", "0", false))
        let newest = sportsEvent("l", state: "post", at: 300, home: ("A", "0", false), away: ("B", "2", false))
        XCTAssertEqual(SportsRules.lastResult([olderWin, newest, middle])?.id, "l")
        XCTAssertEqual(SportsRules.recentForm([olderWin, middle, newest], team: "A"), [.win, .draw, .loss])
        XCTAssertEqual(SportsRules.recentForm([olderWin, middle, newest], team: "A", size: 2), [.draw, .loss])
    }

    func testMergedReplacesSameIdAndKeepsDesktopOrder() {
        let base = [sportsEvent("x", state: "pre", at: 300, home: ("A", nil, false), away: ("B", nil, false)),
                    sportsEvent("y", state: "pre", at: 100, home: ("A", nil, false), away: ("B", nil, false))]
        let extra = [sportsEvent("x", state: "in", at: 300, home: ("A", "1", false), away: ("B", "0", false))]
        let merged = SportsRules.merged(base, extra)
        XCTAssertEqual(merged.map(\.id), ["x", "y"])
        XCTAssertEqual(merged.first?.state, "in")
    }
}
