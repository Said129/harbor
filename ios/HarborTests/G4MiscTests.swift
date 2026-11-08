import XCTest
@testable import Harbor

/// Desktop parity rules for the Top 10 gate, the home hero, detail genres, the initial season, sidecar music covers
/// and subtitle FPS availability. Fake titles only: no network, no UI.
final class G4MiscTests: XCTestCase {
    private func media(_ id: String, poster: String? = nil, background: String? = nil) -> Media {
        var value = Media(id: id, type: "movie", name: "Title " + id)
        value.poster = poster
        value.background = background
        return value
    }

    private func season(_ number: Int, _ total: Int, _ watched: Int) -> SeasonResumeRules.SeasonInfo {
        SeasonResumeRules.SeasonInfo(number: number, episodeCount: total, watchedCount: watched)
    }

    private func fps(track: Bool = true, text: Bool = true, secondary: Bool = false, sync: Bool = false,
                     video: Bool = true, native: Bool = true) -> SubtitleFPSAvailability.Unavailable? {
        SubtitleFPSAvailability.unavailable(hasTrack: track, textBased: text, hasSecondary: secondary, autoSyncActive: sync,
                                            videoFPSKnown: video, nativeSupported: native)
    }

    func testTopTenNeedsTheChoiceAndTenTitles() {
        XCTAssertFalse(TopTenGate.renders(active: true, count: 9))
        XCTAssertTrue(TopTenGate.renders(active: true, count: 10))
        XCTAssertTrue(TopTenGate.renders(active: true, count: 25))
        XCTAssertFalse(TopTenGate.renders(active: false, count: 25))
    }

    func testFeaturedPoolKeepsItsOrderAndOnlyDedupesAndCaps() {
        let metas = [media("a", poster: "pa"), media("b", background: "bb"), media("a", background: "dup"),
                     media("c"), media("d", poster: "pd"), media("e", background: "be")]
        XCTAssertEqual(HomeHeroSlides.cap(metas).map(\.id), ["a", "b", "c", "d"])
    }

    func testHeroPutsBackdropsFirstAndCapsAtFour() {
        let metas = [
            media("a", poster: "pa"),
            media("b", poster: "pb", background: "bb"),
            media("c", background: "bc"),
            media("d"),
            media("e", poster: "pe", background: ""),
            media("f", background: "bf"),
            media("g", poster: "pg", background: "bg"),
        ]
        XCTAssertEqual(HomeHeroSlides.pick(metas).map(\.id), ["b", "c", "f", "g"])
    }

    func testHeroFallsBackToPosterOnlyTitlesAndDropsTitlesWithoutArtwork() {
        XCTAssertEqual(HomeHeroSlides.pick([media("a", poster: "pa"), media("b")]).map(\.id), ["a"])
        XCTAssertTrue(HomeHeroSlides.pick([media("x")]).isEmpty)
    }

    func testHeroDedupesByIdKeepingTheFirstTitle() {
        let metas = [media("a", background: "one"), media("a", background: "two"), media("b", poster: "p")]
        let slides = HomeHeroSlides.pick(metas)
        XCTAssertEqual(slides.map(\.id), ["a", "b"])
        XCTAssertEqual(slides.first?.background, "one")
    }

    func testDetailShowsThreeGenresAndOpensOnlyDesktopTMDBGenres() {
        XCTAssertEqual(DetailGenreRules.visible(["Drama", "Crime", "Thriller", "Western"]), ["Drama", "Crime", "Thriller"])
        let movie = DetailGenreRules.browseRail(for: "Drama", isSeries: false)
        XCTAssertEqual(movie?.path, "discover/movie")
        XCTAssertEqual(movie?.parameters, ["with_genres": "18"])
        XCTAssertEqual(movie?.kind, "movie")
        let series = DetailGenreRules.browseRail(for: "Drama", isSeries: true)
        XCTAssertEqual(series?.path, "discover/tv")
        XCTAssertEqual(series?.parameters, ["with_genres": "18"])
        XCTAssertNil(DetailGenreRules.browseRail(for: "Science Fiction", isSeries: false))
    }

    func testInitialSeasonFollowsDesktopResumeRules() {
        // A single real season is the first one, even with specials present.
        XCTAssertEqual(SeasonResumeRules.defaultSeason([season(0, 2, 0), season(1, 10, 3)], hint: nil), 1)
        // An unfinished hint season is kept.
        XCTAssertEqual(SeasonResumeRules.defaultSeason([season(1, 10, 10), season(2, 10, 4), season(3, 10, 0)], hint: 2), 2)
        // A finished hint season moves on to a later unfinished season.
        XCTAssertEqual(SeasonResumeRules.defaultSeason([season(1, 10, 10), season(2, 10, 10), season(3, 10, 0)], hint: 2), 3)
        // Without a usable hint, the latest season with progress wins.
        XCTAssertEqual(SeasonResumeRules.defaultSeason([season(1, 10, 10), season(2, 10, 5), season(3, 10, 0)], hint: nil), 2)
        // A hint that is not a real season is ignored.
        XCTAssertEqual(SeasonResumeRules.defaultSeason([season(1, 10, 0), season(2, 10, 0)], hint: 7), 1)
        // Everything finished: the last real season.
        XCTAssertEqual(SeasonResumeRules.defaultSeason([season(1, 10, 10), season(2, 10, 10)], hint: nil), 2)
    }

    func testSidecarCoverUsesDesktopNamesWithoutCaseAndLowestRankWins() {
        XCTAssertEqual(MusicSidecarCover.choose(["track.flac", "Folder.JPG", "cover.png"]), "cover.png")
        XCTAssertEqual(MusicSidecarCover.choose(["front.jpg", "COVER.JPEG"]), "COVER.JPEG")
        XCTAssertNil(MusicSidecarCover.choose(["track.flac", "notes.txt", "art.jpg"]))
    }

    func testSubtitleFPSAvailabilityFollowsDesktopOrderAndDisablesDuringAutoSync() {
        XCTAssertNil(fps())
        XCTAssertEqual(fps(track: false), .noTrack)
        XCTAssertEqual(fps(text: false), .notTextBased)
        XCTAssertEqual(fps(secondary: true, sync: true), .secondaryActive)
        XCTAssertEqual(fps(sync: true), .autoSyncActive)
        XCTAssertEqual(fps(sync: true, video: false), .autoSyncActive)
        XCTAssertEqual(fps(video: false), .videoFPSUnavailable)
        XCTAssertEqual(fps(native: false), .nativeUnavailable)
        XCTAssertTrue(SubtitleFPSAvailability.autoSyncActive(.analyzing))
        XCTAssertTrue(SubtitleFPSAvailability.autoSyncActive(.applying))
        // `synced` is a finished run, not a running one (see SubtitleFPSAvailability.autoSyncActive).
        XCTAssertFalse(SubtitleFPSAvailability.autoSyncActive(.synced))
        XCTAssertFalse(SubtitleFPSAvailability.autoSyncActive(.idle))
        XCTAssertFalse(SubtitleFPSAvailability.autoSyncActive(.failed))
        XCTAssertFalse(SubtitleFPSAvailability.autoSyncActive(.declined))
    }
}
