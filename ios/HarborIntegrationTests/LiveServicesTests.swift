import XCTest
import CryptoKit
@testable import Harbor

/// Opt-in network integration. These use the production service and embedded
/// C ABI; no catalog, metadata, stream or player response is substituted.
@MainActor
final class LiveServicesTests: XCTestCase {
    private let service = HarborService()
    private let publicAddon = "https://raw.githubusercontent.com/Stremio/stremio-static-addon-example/master/manifest.json"

    private func requireOptIn() throws {
        guard ProcessInfo.processInfo.environment["HARBOR_LIVE_INTEGRATION"] == "1" else {
            throw XCTSkip("Live integration requires explicit opt-in")
        }
    }
    func testNativeSportsLoadsPublishedScoresAndActualBoxscore() async throws {
        try requireOptIn()
        let league = try XCTUnwrap(try SportsLeague.catalog().first { $0.id == "NBA" })
        let events = try await SportsService.shared.events(league, date: "20251025", refresh: true)
        XCTAssertFalse(events.isEmpty)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.league.path, "basketball/nba")
        XCTAssertEqual(event.sides.count, 2)
        XCTAssertTrue(event.sides.allSatisfy { !$0.name.isEmpty && $0.score != nil })
        let summary = try await SportsService.shared.summary(event)
        XCTAssertFalse(summary.groups.isEmpty, "Published team/player statistics must survive native parsing")
        let standings = try await SportsStandingsService.shared.table(league, season: 2026)
        XCTAssertFalse(standings.groups.isEmpty)
        XCTAssertTrue(standings.groups.flatMap(\.rows).contains { !$0.side.name.isEmpty && !$0.cells.isEmpty })
        print("Harbor live Sports: events=\(events.count), statisticGroups=\(summary.groups.count)")
    }

    func testPublishedM3UIsCachedPrivatelyAndChannelsResolveWithNativeCore() async throws {
        try requireOptIn()
        let source = LivePlaylistSource(id: UUID().uuidString.lowercased(), name: "Public playlist integration", url: "https://iptv-org.github.io/iptv/countries/es.m3u")
        let cached = LivePlaylistSource(id: source.id, name: source.name, url: nil)
        let owner = "iptv-test-" + UUID().uuidString
        do {
            let channels = try await LivePlaylistService.shared.load(source, owner: owner, refresh: true)
            let channel = try XCTUnwrap(channels.first { $0.url.hasPrefix("https://") && !$0.drm })
            let headers = JSONValue.object(channel.headers.mapValues(JSONValue.string))
            let offer = StreamOffer(id: 0, raw: .object(["addonId": .string("iptv:" + source.id), "addonName": .string("Live TV"), "url": .string(channel.url), "behaviorHints": .object(["proxyHeaders": .object(["request": headers])])]))
            let playback = try await service.resolve(offer)
            XCTAssertEqual(playback.url, channel.url)
            let reloaded = try await LivePlaylistService.shared.load(cached, owner: owner, refresh: false)
            XCTAssertEqual(reloaded, channels)
            do { _ = try await LivePlaylistService.shared.load(cached, owner: owner + "-other", refresh: false); XCTFail("An unrelated account must not open the private playlist copy") }
            catch let error as HarborError { XCTAssertEqual(error.code, "iptv-url") }
            try await LivePlaylistService.shared.remove(source, owner: owner)
            print("Harbor live M3U: channels=\(channels.count), native resolution/cache/isolation=passed; media transport unverified")
        } catch { try? await LivePlaylistService.shared.remove(source, owner: owner); throw error }
    }

    func testCinemetaCatalogSearchAndMetadataThroughNativeService() async throws {
        try requireOptIn()
        let addon = try await service.install(HarborService.cinemetaManifest)
        let (catalogs, _) = try await service.catalogs([addon])
        XCTAssertFalse(catalogs.isEmpty)
        let preview = try XCTUnwrap(catalogs.flatMap(\.metas).first)
        let metadata = try await service.metadata(preview, addons: [addon])
        XCTAssertEqual(metadata.id, preview.id)
        XCTAssertFalse(metadata.name.isEmpty)
        let (results, _) = try await service.catalogs([addon], search: "Interstellar")
        let count = results.reduce(0) { $0 + $1.metas.count }
        XCTAssertGreaterThan(count, 0)
        let match = try XCTUnwrap(results.flatMap(\.metas).first { $0.id == "tt0816692" && $0.name == "Interstellar" }, "The real movie query must return its matching metadata identity")
        let detail = try await service.metadata(match, addons: [addon])
        XCTAssertFalse(detail.writer?.isEmpty ?? true, "The native detail must preserve writers returned by the real addon")
        let trailers = try XCTUnwrap(detail.details?.trailers)
        XCTAssertFalse(trailers.isEmpty, "Addon trailers must be available without a TMDB key")
        XCTAssertTrue(trailers.allSatisfy { URL(string: $0.url)?.host == "www.youtube.com" })
        let related = try await service.related(detail, addons: [addon])
        XCTAssertFalse(related.isEmpty, "The native detail must retain Desktop's real Cinemeta genre discovery")
        XCTAssertFalse(related.contains { $0.identity == detail.identity })
        var disabled = addon; disabled.enabled = false
        let disabledRelated = try await service.related(detail, addons: [disabled])
        XCTAssertTrue(disabledRelated.isEmpty, "Related titles must respect an explicitly disabled catalog provider")
        print("Harbor live Cinemeta: catalogs=\(catalogs.count) searchItems=\(count) trailers=\(trailers.count) related=\(related.count) metadata=passed")
    }

    func testOfficialAddonCatalogMetadataStreamsAndResolution() async throws {
        try requireOptIn()
        // This addon is installed within the test only; it is not an app default.
        let addon = try await service.install(publicAddon)
        let (catalogs, _) = try await service.catalogs([addon])
        let preview = try XCTUnwrap(catalogs.flatMap(\.metas).first)
        let metadata = try await service.metadata(preview, addons: [addon])
        let videoID = metadata.behaviorHints?.defaultVideoId ?? metadata.id
        let (offers, _) = try await service.streams(metadata, videoID: videoID, addons: [addon])
        let offer = try XCTUnwrap(offers.first)
        let source = try await service.resolve(offer)
        XCTAssertTrue(["http", "https"].contains(URL(string: source.url)?.scheme ?? ""))
        XCTAssertEqual(source.via, "direct")
        print("Harbor live official addon: catalogs=\(catalogs.count) offers=\(offers.count) resolution=passed; media transport unverified")
    }

    func testNativeDownloadPersistsExactPublicBytesAndRemainsAccountScoped() async throws {
        try requireOptIn()
        let downloads = DownloadManager.shared
        let owner = "download-test-\(UUID().uuidString)"
        defer { for item in downloads.list(owner: owner) { downloads.remove(item, owner: owner) } }
        // Original CC0 fixture hosted at a fixed public commit, test input only.
        let source = PlaybackSource(url: "https://raw.githubusercontent.com/Said129/harbor/1f4d5d99282b2eda816cbe0d544cb33b5bc7ee21/ios/HarborTests/Fixtures/render-8bit.mp4", headers: nil, subtitles: nil, via: "direct")
        let media = Media(id: "download-test", type: "movie", name: "Native download test")
        try downloads.start(source: source, media: media, episode: nil, owner: owner, cellular: false)
        let active = try XCTUnwrap(downloads.list(owner: owner).first)
        downloads.toggle(active, owner: "other-\(owner)")
        XCTAssertEqual(downloads.list(owner: owner).first?.status, .downloading)
        downloads.toggle(active, owner: owner)
        XCTAssertEqual(downloads.list(owner: owner).first?.status, .paused)
        downloads.toggle(active, owner: owner)
        XCTAssertEqual(downloads.list(owner: owner).first?.status, .downloading, "Resume must use the current stored state even when the rendered row is older")
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, let item = downloads.list(owner: owner).first, item.status == .downloading {
            try await Task.sleep(for: .milliseconds(250))
        }
        let item = try XCTUnwrap(downloads.list(owner: owner).first)
        XCTAssertEqual(item.status, .complete, item.message ?? "The background download did not complete")
        let file = try downloads.file(item)
        let data = try Data(contentsOf: file)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hash, "27335d1dbe06c76690517ccbf65e26aaa341ca38a3f3cbf71e98e79e50508c59")
        XCTAssertEqual(item.received, Int64(data.count))
        XCTAssertTrue(downloads.list(owner: "other-\(owner)").isEmpty)
        downloads.remove(item, owner: "other-\(owner)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "An action from another account must preserve the actual downloaded bytes")
        XCTAssertEqual(downloads.list(owner: owner).first?.id, item.id)
        downloads.remove(item, owner: owner)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRealGutenbergEPUBLoadsNativeChapters() async throws {
        try requireOptIn()
        let (books, _) = try await EBookService.shared.catalog(query: "Pride and Prejudice", language: "en", page: 1)
        let book = try XCTUnwrap(books.first { $0.id == "gutendex:1342" }, "The production catalog must return the requested Gutenberg book")
        XCTAssertTrue(book.title.localizedCaseInsensitiveContains("Pride and Prejudice"))
        XCTAssertNotNil(book.epub)
        let owner = "ebook-test-\(UUID().uuidString)"
        do {
            let publication = try await EBookService.shared.open(book, owner: owner)
            XCTAssertTrue(publication.title.localizedCaseInsensitiveContains("Pride and Prejudice"))
            XCTAssertGreaterThan(publication.chapters.count, 1)
            let blocks = try await EBookService.shared.blocks(book, owner: owner, chapter: 1)
            XCTAssertFalse(blocks.isEmpty)
            XCTAssertTrue(blocks.contains { !$0.text.isEmpty })
            try await EBookService.shared.remove(book, owner: owner)
        } catch { try? await EBookService.shared.remove(book, owner: owner); throw error }
    }
}
