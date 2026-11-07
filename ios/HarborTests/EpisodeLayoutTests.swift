import XCTest
@testable import Harbor

final class EpisodeLayoutTests: XCTestCase {
    func testLayoutFallsBackToListForMissingOrUnknownValues() {
        XCTAssertEqual(EpisodeLayoutPolicy.layout(nil), .list)
        XCTAssertEqual(EpisodeLayoutPolicy.layout("bogus"), .list)
        XCTAssertEqual(EpisodeLayoutPolicy.layout("strip"), .strip)
        XCTAssertEqual(EpisodeLayoutPolicy.layout("grid"), .grid)
        XCTAssertEqual(EpisodeLayoutPolicy.Layout.allCases.map(\.rawValue), ["list", "strip", "grid"])
    }

    func testDesktopDefaultsAndChoices() {
        XCTAssertEqual(EpisodeLayoutPolicy.defaultLayout, .list)
        XCTAssertEqual(EpisodeLayoutPolicy.defaultCardScale, 1)
        XCTAssertEqual(EpisodeLayoutPolicy.cardScaleChoices, [1, 1.2, 1.45])
    }

    func testCardScaleFallsBackToOne() {
        XCTAssertEqual(EpisodeLayoutPolicy.cardScale(nil), 1)
        XCTAssertEqual(EpisodeLayoutPolicy.cardScale(0), 1)
        XCTAssertEqual(EpisodeLayoutPolicy.cardScale(-2), 1)
        XCTAssertEqual(EpisodeLayoutPolicy.cardScale(Double.nan), 1)
        XCTAssertEqual(EpisodeLayoutPolicy.cardScale(1.45), 1.45)
    }

    func testStripAndGridWidthsScaleLikeDesktop() {
        XCTAssertEqual(EpisodeLayoutPolicy.stripWidth(1), 244)
        XCTAssertEqual(EpisodeLayoutPolicy.stripWidth(1.2), 293)
        XCTAssertEqual(EpisodeLayoutPolicy.stripWidth(1.45), 354)
        XCTAssertEqual(EpisodeLayoutPolicy.stripWidth(nil), 244)
        XCTAssertEqual(EpisodeLayoutPolicy.gridMinimumWidth(1), 232)
        XCTAssertEqual(EpisodeLayoutPolicy.gridMinimumWidth(1.2), 278)
        XCTAssertEqual(EpisodeLayoutPolicy.gridMinimumWidth(1.45), 336)
        XCTAssertEqual(EpisodeLayoutPolicy.gridMinimumWidth(0), 232)
    }

    func testStillFollowsHDSettingForTMDBOnly() {
        let w300 = "https://image.tmdb.org/t/p/w300/abc.jpg"
        let original = "https://image.tmdb.org/t/p/original/abc.jpg"
        XCTAssertEqual(EpisodeLayoutPolicy.still(w300, hd: true), original)
        XCTAssertEqual(EpisodeLayoutPolicy.still(original, hd: false), w300)
        XCTAssertEqual(EpisodeLayoutPolicy.still("https://episodes.example.com/1.jpg", hd: true), "https://episodes.example.com/1.jpg")
        XCTAssertNil(EpisodeLayoutPolicy.still(nil, hd: true))
    }

    func testArtworkPixelsGrowWithHD() {
        XCTAssertEqual(EpisodeLayoutPolicy.artworkPixels(hd: true), 1000)
        XCTAssertEqual(EpisodeLayoutPolicy.artworkPixels(hd: false), 600)
    }

    func testEpisodeDisplaySettingsAreKeptPerProfile() {
        XCTAssertTrue(ProfileSettingsStore.keys.isSuperset(of: ["episodeLayout", "episodeCardScale", "hdEpisodeImages"]))
    }
}
