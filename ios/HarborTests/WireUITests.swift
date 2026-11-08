import XCTest
@testable import Harbor

/// The pure helpers behind the player title order (`playerTitleSeriesFirst`) and the watched-download removal (`deleteWatchedDownloads`).
final class WireUITests: XCTestCase {
    private func series() -> Media {
        var show = Media(id: "tt0000001", type: "series", name: "Show")
        show.videos = [
            Episode(id: "tt0000001:1:2", season: 1, episode: 2, name: "Second"),
            Episode(id: "tt0000001:1:3", season: 1, episode: 3, name: "  "),
            Episode(id: "tt0000001:2:1", season: 2, episode: 1)
        ]
        return show
    }

    func testEpisodeLineMatchesDesktopFormat() {
        XCTAssertEqual(PlayerTitleLines.episodeLine(season: 1, episode: 2, name: "Pilot"), "S1 E2 · Pilot")
        XCTAssertEqual(PlayerTitleLines.episodeLine(season: 3, episode: 10, name: nil), "S3 E10")
        XCTAssertEqual(PlayerTitleLines.episodeLine(season: 3, episode: 10, name: "   "), "S3 E10")
    }

    func testEpisodeLineWithoutNumbersKeepsOnlyTheName() {
        XCTAssertEqual(PlayerTitleLines.episodeLine(season: nil, episode: 4, name: "Named"), "Named")
        XCTAssertNil(PlayerTitleLines.episodeLine(season: nil, episode: nil, name: ""))
        XCTAssertNil(PlayerTitleLines.episodeLine(season: 1, episode: nil, name: nil))
    }

    func testEpisodeLeadsWithTheEpisodeLineByDefault() {
        let target = ResumeTarget(id: "tt0000001", season: 1, episode: 2, videoId: "tt0000001:1:2")
        let lines = PlayerTitleLines.lines(title: "Show · Second", media: series(), target: target, seriesFirst: false)
        XCTAssertEqual(lines.primary, "S1 E2 · Second")
        XCTAssertEqual(lines.secondary, "Show")
    }

    func testSeriesFirstLeadsWithTheShowName() {
        let target = ResumeTarget(id: "tt0000001", season: 1, episode: 2, videoId: "tt0000001:1:2")
        let lines = PlayerTitleLines.lines(title: "Show · Second", media: series(), target: target, seriesFirst: true)
        XCTAssertEqual(lines.primary, "Show")
        XCTAssertEqual(lines.secondary, "S1 E2 · Second")
    }

    func testEpisodeWithoutANameShowsTheEpisodeCodeOnly() {
        let target = ResumeTarget(id: "tt0000001", season: 2, episode: 1, videoId: "tt0000001:2:1")
        let lines = PlayerTitleLines.lines(title: "Show", media: series(), target: target, seriesFirst: false)
        XCTAssertEqual(lines.primary, "S2 E1")
        XCTAssertEqual(lines.secondary, "Show")
    }

    func testMovieKeepsTheTitleAloneEvenWithSeriesFirst() {
        let movie = Media(id: "tt0000009", type: "movie", name: "Movie")
        let target = ResumeTarget(id: "tt0000009", season: nil, episode: nil, videoId: nil)
        for seriesFirst in [false, true] {
            let lines = PlayerTitleLines.lines(title: "Movie", media: movie, target: target, seriesFirst: seriesFirst)
            XCTAssertEqual(lines.primary, "Movie")
            XCTAssertNil(lines.secondary)
        }
    }

    func testMissingMediaKeepsTheTitleAlone() {
        let target = ResumeTarget(id: "tt0000001", season: 1, episode: 2, videoId: nil)
        let lines = PlayerTitleLines.lines(title: "Loose title", media: nil, target: target, seriesFirst: true)
        XCTAssertEqual(lines.primary, "Loose title")
        XCTAssertNil(lines.secondary)
    }

    func testRemovalNeedsTheSettingAndADownload() {
        XCTAssertTrue(WatchedDownloadRemoval.shouldRemove(enabled: true, viaDownload: true, positionMs: 900, durationMs: 1_000))
        XCTAssertFalse(WatchedDownloadRemoval.shouldRemove(enabled: false, viaDownload: true, positionMs: 1_000, durationMs: 1_000))
        XCTAssertFalse(WatchedDownloadRemoval.shouldRemove(enabled: true, viaDownload: false, positionMs: 1_000, durationMs: 1_000))
    }

    func testRemovalWaitsForNinetyPercent() {
        XCTAssertFalse(WatchedDownloadRemoval.shouldRemove(enabled: true, viaDownload: true, positionMs: 899, durationMs: 1_000))
        XCTAssertTrue(WatchedDownloadRemoval.shouldRemove(enabled: true, viaDownload: true, positionMs: 950, durationMs: 1_000))
    }

    func testRemovalIgnoresUnknownDurations() {
        XCTAssertFalse(WatchedDownloadRemoval.shouldRemove(enabled: true, viaDownload: true, positionMs: 1_000, durationMs: 0))
        XCTAssertFalse(WatchedDownloadRemoval.shouldRemove(enabled: true, viaDownload: true, positionMs: 1_000, durationMs: .nan))
        XCTAssertFalse(WatchedDownloadRemoval.shouldRemove(enabled: true, viaDownload: true, positionMs: .nan, durationMs: 1_000))
    }
}
