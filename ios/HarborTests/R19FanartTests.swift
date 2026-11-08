import XCTest
@testable import Harbor

/// The anime detail page's Fanart use (`AnimeFanartArtwork`): which title asks, with which id, and how the answer fills the hero.
final class R19FanartTests: XCTestCase {
    private func anime(_ id: String = "kitsu:7", type: String = "series") -> Media {
        Media(id: id, type: type, name: "Show")
    }

    func testWithoutAFanartKeyNothingIsAsked() {
        XCTAssertNil(AnimeFanartArtwork.tvdbID(for: anime(), seriesID: 81189, fanartKey: ""))
        XCTAssertNil(AnimeFanartArtwork.tvdbID(for: anime(), seriesID: 81189, fanartKey: "   "))
        XCTAssertNil(AnimeFanartArtwork.tvdbID(for: anime(), seriesID: 81189, fanartKey: "a/b"))
    }

    func testWithAFanartKeyAnimeSeriesIsAskedWithItsTVDBID() {
        XCTAssertEqual(AnimeFanartArtwork.tvdbID(for: anime(), seriesID: 81189, fanartKey: "test-key"), 81189)
        XCTAssertEqual(AnimeFanartArtwork.tvdbID(for: anime("mal:21", type: "anime"), seriesID: 81189, fanartKey: "test-key"), 81189)
    }

    func testOnlyAnimeWithAUsableTVDBIDQualifies() {
        XCTAssertNil(AnimeFanartArtwork.tvdbID(for: anime(), seriesID: nil, fanartKey: "test-key"))
        XCTAssertNil(AnimeFanartArtwork.tvdbID(for: anime(), seriesID: 0, fanartKey: "test-key"))
        // Anime movies would need a TMDB id, which iOS does not keep for anime titles.
        XCTAssertNil(AnimeFanartArtwork.tvdbID(for: anime("kitsu:9", type: "movie"), seriesID: 81189, fanartKey: "test-key"))
        // Titles that are not anime keep their own artwork path.
        XCTAssertNil(AnimeFanartArtwork.tvdbID(for: Media(id: "tt0111161", type: "series", name: "Show"), seriesID: 81189, fanartKey: "test-key"))
    }

    func testFanartLogoFillsOnlyAMissingLogo() {
        let art = FanartTV.Art(logo: "https://assets.fanart.tv/logo.png", backdrop: nil, backdrops: [])
        var empty = anime()
        empty.logo = ""
        XCTAssertEqual(AnimeFanartArtwork.merged(empty, with: art).logo, "https://assets.fanart.tv/logo.png")
        XCTAssertNil(AnimeFanartArtwork.merged(anime(), with: art).background)

        var existing = anime()
        existing.logo = "https://artwork.example/addon-logo.png"
        XCTAssertEqual(AnimeFanartArtwork.merged(existing, with: art).logo, "https://artwork.example/addon-logo.png")
    }

    func testBestBackdropBecomesTheHeroOnlyWhenTheTitleHasNone() {
        let art = FanartTV.Art(logo: nil, backdrop: "https://assets.fanart.tv/b2.jpg", backdrops: ["https://assets.fanart.tv/b2.jpg", "https://assets.fanart.tv/b1.jpg"])
        XCTAssertEqual(AnimeFanartArtwork.merged(anime(), with: art).background, "https://assets.fanart.tv/b2.jpg")

        var withHero = anime()
        withHero.background = "https://artwork.example/hero.jpg"
        XCTAssertEqual(AnimeFanartArtwork.merged(withHero, with: art).background, "https://artwork.example/hero.jpg")
    }

    func testRankedBackdropsJoinTheGalleryWithoutDuplicates() {
        let art = FanartTV.Art(logo: nil, backdrop: "https://assets.fanart.tv/b2.jpg", backdrops: ["https://assets.fanart.tv/b2.jpg", "https://assets.fanart.tv/b1.jpg"])
        var media = anime()
        var details = MediaDetails()
        details.backdrops = ["https://assets.fanart.tv/b1.jpg", "https://artwork.example/own.jpg"]
        media.details = details
        let merged = AnimeFanartArtwork.merged(media, with: art)
        XCTAssertEqual(merged.details?.backdrops, ["https://assets.fanart.tv/b1.jpg", "https://artwork.example/own.jpg", "https://assets.fanart.tv/b2.jpg"])
    }

    func testEmptyAnswerLeavesTheTitleUnchanged() {
        let media = anime()
        let empty = FanartTV.Art(logo: nil, backdrop: nil, backdrops: [])
        XCTAssertEqual(AnimeFanartArtwork.merged(media, with: empty), media)
        XCTAssertNil(AnimeFanartArtwork.merged(media, with: empty).details)
    }
}
