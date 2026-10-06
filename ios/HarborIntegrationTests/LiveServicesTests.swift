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
        print("Harbor live Sports: events=\(events.count), statisticGroups=\(summary.groups.count)")
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
        XCTAssertTrue(results.flatMap(\.metas).contains { $0.id == "tt0816692" && $0.name == "Interstellar" }, "The real movie query must return its matching metadata identity")
        print("Harbor live Cinemeta: catalogs=\(catalogs.count) searchItems=\(count) metadata=passed")
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
        defer { for item in downloads.list(owner: owner) { downloads.remove(item) } }
        // Original CC0 fixture hosted at a fixed public commit, test input only.
        let source = PlaybackSource(url: "https://raw.githubusercontent.com/Said129/harbor/1f4d5d99282b2eda816cbe0d544cb33b5bc7ee21/ios/HarborTests/Fixtures/render-8bit.mp4", headers: nil, subtitles: nil, via: "direct")
        let media = Media(id: "download-test", type: "movie", name: "Native download test")
        try downloads.start(source: source, media: media, episode: nil, owner: owner, cellular: false)
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
        downloads.remove(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRealGutenbergEPUBLoadsNativeChapters() async throws {
        try requireOptIn()
        let value = try await HTTPClient().json("https://gutendex.com/books/1342", timeout: 30)
        let title = try XCTUnwrap(value["title"].string)
        let url = try XCTUnwrap(value["formats"]["application/epub+zip"].string)
        let book = EBook(id: "gutendex:1342", title: title, epub: url)
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
