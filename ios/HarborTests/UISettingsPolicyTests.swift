import XCTest
@testable import Harbor

/// Desktop's small settings: `mpvQuality`, `spoilerSkipNext`, `playerTitleSeriesFirst` and `deleteWatchedDownloads` (pure rules only).
final class UISettingsPolicyTests: XCTestCase {
    func testMpvQualityFallsBackToBalancedForUnknownValues() {
        XCTAssertEqual(UISettingsPolicy.mpvQuality(nil), "balanced")
        XCTAssertEqual(UISettingsPolicy.mpvQuality(""), "balanced")
        XCTAssertEqual(UISettingsPolicy.mpvQuality("ultra"), "balanced")
        XCTAssertEqual(UISettingsPolicy.mpvQuality("performance"), "performance")
        XCTAssertEqual(UISettingsPolicy.mpvQuality("quality"), "quality")
    }

    func testBalancedAddsNoMpvOptions() {
        XCTAssertEqual(UISettingsPolicy.mpvQualityLines("balanced"), [])
        XCTAssertEqual(UISettingsPolicy.mpvQualityLines(nil), [])
        XCTAssertEqual(UISettingsPolicy.mpvQualityLines("unknown"), [])
    }

    func testPerformanceProfileMatchesDesktopLinesInOrder() {
        XCTAssertEqual(UISettingsPolicy.mpvQualityLines("performance"), [
            "scale=bilinear", "cscale=bilinear", "dscale=bilinear", "dither=no",
            "deband=no", "vd-lavc-fast=yes", "interpolation=no", "hdr-compute-peak=no"
        ])
    }

    func testQualityProfileMatchesDesktopLinesInOrder() {
        let lines = UISettingsPolicy.mpvQualityLines("quality")
        XCTAssertEqual(lines.count, 10)
        XCTAssertEqual(lines.first, "scale=ewa_lanczossharp")
        XCTAssertEqual(lines[2], "dscale=mitchell")
        XCTAssertEqual(lines[5], "dither-depth=auto")
        XCTAssertEqual(lines.last, "hdr-compute-peak=yes")
    }

    func testSpoilerMaskIsClearWhenSpoilersAreNotHidden() {
        let mask = UISettingsPolicy.spoilerMask(hideSpoilers: false, blurThumbnails: true, hideTitles: true, hideDescriptions: true,
                                                skipNext: true, watched: false, isNextUp: false)
        XCTAssertFalse(mask.active)
    }

    func testSpoilerMaskIsClearForWatchedEpisodes() {
        let mask = UISettingsPolicy.spoilerMask(hideSpoilers: true, blurThumbnails: true, hideTitles: true, hideDescriptions: true,
                                                skipNext: false, watched: true, isNextUp: false)
        XCTAssertFalse(mask.active)
    }

    func testSpoilerSkipNextKeepsTheNextEpisodeClear() {
        let next = UISettingsPolicy.spoilerMask(hideSpoilers: true, blurThumbnails: true, hideTitles: true, hideDescriptions: true,
                                                skipNext: true, watched: false, isNextUp: true)
        XCTAssertFalse(next.active)
        let later = UISettingsPolicy.spoilerMask(hideSpoilers: true, blurThumbnails: true, hideTitles: true, hideDescriptions: false,
                                                 skipNext: true, watched: false, isNextUp: false)
        XCTAssertEqual(later, UISettingsPolicy.SpoilerMask(thumbnail: true, title: true, description: false))
    }

    func testSpoilerMaskBlursTheNextEpisodeWhenSkipIsOff() {
        let mask = UISettingsPolicy.spoilerMask(hideSpoilers: true, blurThumbnails: false, hideTitles: true, hideDescriptions: true,
                                                skipNext: false, watched: false, isNextUp: true)
        XCTAssertEqual(mask, UISettingsPolicy.SpoilerMask(thumbnail: false, title: true, description: true))
        XCTAssertTrue(mask.active)
    }

    func testTitleLinesKeepTheTitleFirstByDefault() {
        let lines = UISettingsPolicy.titleLines(title: "Episode 3", subtitle: "Show", seriesFirst: false)
        XCTAssertEqual(lines.primary, "Episode 3")
        XCTAssertEqual(lines.secondary, "Show")
    }

    func testTitleLinesSwapWhenSeriesFirstAndSubtitleExists() {
        let lines = UISettingsPolicy.titleLines(title: "Episode 3", subtitle: "Show", seriesFirst: true)
        XCTAssertEqual(lines.primary, "Show")
        XCTAssertEqual(lines.secondary, "Episode 3")
    }

    func testTitleLinesDoNotSwapWithoutASubtitle() {
        let none = UISettingsPolicy.titleLines(title: "Movie", subtitle: nil, seriesFirst: true)
        XCTAssertEqual(none.primary, "Movie")
        XCTAssertNil(none.secondary)
        let empty = UISettingsPolicy.titleLines(title: "Movie", subtitle: "", seriesFirst: true)
        XCTAssertEqual(empty.primary, "Movie")
        XCTAssertEqual(empty.secondary, "")
    }

    func testWatchedDownloadIsRemovedOnlyWhenEnabledAndNearlyFinished() {
        XCTAssertTrue(UISettingsPolicy.removesWatchedDownload(enabled: true, progress: 0.9))
        XCTAssertTrue(UISettingsPolicy.removesWatchedDownload(enabled: true, progress: 1))
        XCTAssertFalse(UISettingsPolicy.removesWatchedDownload(enabled: true, progress: 0.89))
        XCTAssertFalse(UISettingsPolicy.removesWatchedDownload(enabled: false, progress: 1))
        XCTAssertFalse(UISettingsPolicy.removesWatchedDownload(enabled: true, progress: .nan))
    }
}
