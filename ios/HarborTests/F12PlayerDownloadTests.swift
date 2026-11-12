import XCTest
@testable import Harbor

final class F12PlayerDownloadTests: XCTestCase {
    private func series() -> Media {
        var media = Media(id: "tt0903747", type: "series", name: "Breaking Bad")
        media.videos = [
            Episode(id: "tt0903747:1:1", season: 1, episode: 1),
            Episode(id: "tt0903747:1:2", season: 1, episode: 2)
        ]
        return media
    }

    private func item(_ media: Media, videoID: String?, status: DownloadStatus, started: TimeInterval, received: Int64 = 0, expected: Int64 = 0) -> DownloadItem {
        let target = ResumeTarget(id: media.id, season: nil, episode: nil, videoId: videoID)
        return DownloadItem(id: UUID(), owner: "owner-hash", media: media, target: target, title: media.name, fileExtension: "mkv",
                            started: Date(timeIntervalSince1970: started), status: status, received: received, expected: expected)
    }

    func testOnlyPlainHttpFilesCanBeDownloaded() {
        XCTAssertTrue(PlayerDownloadPolicy.canDownload(url: "https://example.org/video.mkv"))
        XCTAssertTrue(PlayerDownloadPolicy.canDownload(url: "http://example.org/video.mp4?token=1"))
        XCTAssertTrue(PlayerDownloadPolicy.canDownload(url: "https://example.org/stream"))
        XCTAssertFalse(PlayerDownloadPolicy.canDownload(url: "https://example.org/live/index.m3u8"))
        XCTAssertFalse(PlayerDownloadPolicy.canDownload(url: "https://example.org/manifest.MPD"))
        XCTAssertFalse(PlayerDownloadPolicy.canDownload(url: "/var/mobile/Containers/Data/video.mkv"))
        XCTAssertFalse(PlayerDownloadPolicy.canDownload(url: "file:///var/mobile/video.mkv"))
        XCTAssertFalse(PlayerDownloadPolicy.canDownload(url: "rtmp://example.org/live"))
        XCTAssertFalse(PlayerDownloadPolicy.canDownload(url: ""))
    }

    func testMovieContextNeedsAnOwnerAndADownloadableSource() {
        let movie = Media(id: "tt0111161", type: "movie", name: "The Shawshank Redemption")
        let target = ResumeTarget(id: movie.id, season: nil, episode: nil, videoId: nil)
        let context = PlayerDownloadPolicy.context(media: movie, target: target, owner: "owner", url: "https://example.org/a.mkv")
        XCTAssertEqual(context?.media.id, "tt0111161")
        XCTAssertNil(context?.episode)
        XCTAssertNil(PlayerDownloadPolicy.context(media: movie, target: target, owner: nil, url: "https://example.org/a.mkv"), "no downloads owner")
        XCTAssertNil(PlayerDownloadPolicy.context(media: movie, target: target, owner: "", url: "https://example.org/a.mkv"))
        XCTAssertNil(PlayerDownloadPolicy.context(media: nil, target: target, owner: "owner", url: "https://example.org/a.mkv"), "no title to file it under")
        XCTAssertNil(PlayerDownloadPolicy.context(media: movie, target: target, owner: "owner", url: "https://example.org/live.m3u8"))
    }

    func testOtherTitleTypesAndForeignTargetsStayHidden() {
        let channel = Media(id: "iptv:1", type: "tv", name: "Channel")
        let channelTarget = ResumeTarget(id: channel.id, season: nil, episode: nil, videoId: nil)
        XCTAssertNil(PlayerDownloadPolicy.context(media: channel, target: channelTarget, owner: "owner", url: "https://example.org/a.mkv"))
        let movie = Media(id: "tt0111161", type: "movie", name: "The Shawshank Redemption")
        let other = ResumeTarget(id: "tt9999999", season: nil, episode: nil, videoId: nil)
        XCTAssertNil(PlayerDownloadPolicy.context(media: movie, target: other, owner: "owner", url: "https://example.org/a.mkv"))
    }

    func testEpisodeContextFindsTheEpisodeBeingPlayed() {
        let media = series()
        let target = ResumeTarget(id: media.id, season: 1, episode: 2, videoId: "tt0903747:1:2")
        let context = PlayerDownloadPolicy.context(media: media, target: target, owner: "owner", url: "https://example.org/e2.mkv")
        XCTAssertEqual(context?.episode?.id, "tt0903747:1:2")
        let missing = ResumeTarget(id: media.id, season: 3, episode: 9, videoId: "tt0903747:3:9")
        XCTAssertNil(PlayerDownloadPolicy.context(media: media, target: missing, owner: "owner", url: "https://example.org/e9.mkv"), "an episode the title does not list stays hidden")
    }

    func testLatestDownloadPrefersActiveThenSavedThenFailedAndMatchesTheEpisode() {
        let media = series()
        let failed = item(media, videoID: "tt0903747:1:1", status: .failed, started: 300)
        let saved = item(media, videoID: "tt0903747:1:1", status: .complete, started: 100)
        let active = item(media, videoID: "tt0903747:1:1", status: .downloading, started: 50, received: 5, expected: 10)
        let otherEpisode = item(media, videoID: "tt0903747:1:2", status: .downloading, started: 400)
        let items: [DownloadItem] = [failed, saved, otherEpisode, active]
        XCTAssertEqual(PlayerDownloadPolicy.latest(in: items, mediaID: media.id, videoID: "tt0903747:1:1")?.id, active.id)
        XCTAssertEqual(PlayerDownloadPolicy.latest(in: [failed, saved], mediaID: media.id, videoID: "tt0903747:1:1")?.id, saved.id)
        XCTAssertEqual(PlayerDownloadPolicy.latest(in: [failed], mediaID: media.id, videoID: "tt0903747:1:1")?.id, failed.id)
        XCTAssertNil(PlayerDownloadPolicy.latest(in: items, mediaID: media.id, videoID: "tt0903747:1:3"))
        XCTAssertNil(PlayerDownloadPolicy.latest(in: items, mediaID: "tt0000000", videoID: "tt0903747:1:1"))
    }

    func testNewestOfTheSameKindWins() {
        let movie = Media(id: "tt0111161", type: "movie", name: "The Shawshank Redemption")
        let older = item(movie, videoID: nil, status: .complete, started: 10)
        let newer = item(movie, videoID: nil, status: .complete, started: 20)
        XCTAssertEqual(PlayerDownloadPolicy.latest(in: [older, newer], mediaID: movie.id, videoID: nil)?.id, newer.id)
    }

    func testStateMapsEveryDownloadStatus() {
        let movie = Media(id: "tt0111161", type: "movie", name: "The Shawshank Redemption")
        XCTAssertEqual(PlayerDownloadPolicy.state(for: nil), .start)
        XCTAssertEqual(PlayerDownloadPolicy.state(for: item(movie, videoID: nil, status: .downloading, started: 1, received: 25, expected: 100)),
                       .downloading(fraction: 0.25, paused: false))
        XCTAssertEqual(PlayerDownloadPolicy.state(for: item(movie, videoID: nil, status: .paused, started: 1)),
                       .downloading(fraction: nil, paused: true))
        XCTAssertEqual(PlayerDownloadPolicy.state(for: item(movie, videoID: nil, status: .complete, started: 1)), .saved)
        XCTAssertEqual(PlayerDownloadPolicy.state(for: item(movie, videoID: nil, status: .failed, started: 1)), .failed)
    }

    func testTorrentIdentityNeedsAHash() {
        XCTAssertNil(PlayerDownloadPolicy.torrentIdentity(infoHash: nil, fileIdx: 3))
        XCTAssertNil(PlayerDownloadPolicy.torrentIdentity(infoHash: "", fileIdx: nil))
        let hash = "0123456789abcdef0123456789abcdef01234567"
        let identity = PlayerDownloadPolicy.torrentIdentity(infoHash: hash, fileIdx: 4)
        XCTAssertEqual(identity?.hash, hash)
        XCTAssertEqual(identity?.fileIndex, 4)
        XCTAssertNil(PlayerDownloadPolicy.torrentIdentity(infoHash: hash, fileIdx: nil)?.fileIndex)
    }
}
