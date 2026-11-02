import Foundation
import XCTest
@testable import Harbor

final class SubtitleMovieHashTests: XCTestCase {
    func testNativeFileAndHTTPRangeHashesAgreeWithOriginalDesktopAndEnrichOnlyTheSelectedVideo() async throws {
        let data = Data(repeating: 1, count: 200000)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("owned-hash-" + UUID().uuidString + ".mkv")
        try data.write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let local = try await SubtitleMovieHashService.compute(.init(url: file.absoluteString, headers: nil, subtitles: nil, via: "test-fixture"))
        let expected = UInt64(200000) &+ (UInt64(0x0101010101010101) &* 8192 &* 2)
        XCTAssertEqual(local.hash, String(format: "%016llx", expected)); XCTAssertEqual(local.size, 200000)
        let server = try SubtitleRangeFixture(data: data); defer { server.stop() }
        let url = try await server.start()
        let remote = try await SubtitleMovieHashService.compute(.init(url: url.absoluteString, headers: ["X-Owned-Video": "owned-only"], subtitles: nil, via: "test-fixture"))
        XCTAssertEqual(remote.hash, local.hash); XCTAssertEqual(remote.size, local.size)
        XCTAssertEqual(server.requestedOffsets, [0, 200000 - 65536])
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertTrue(server.requests.allSatisfy { $0.lowercased().contains("x-owned-video: owned-only") })
        let addon = Addon(manifest: .object(["id": .string("owned"), "name": .string("Owned"), "resources": .array([.string("subtitles")]), "types": .array([.string("movie")]), "idPrefixes": .array([.string("tt")])]), transportUrl: "https://example.org/owned/manifest.json", enabled: true)
        let media = Media(id: "tt0000001", type: "movie", name: "Owned Movie")
        var request = SubtitleRequest(media: media, videoID: media.id, season: nil, episode: nil, addons: [addon], stream: .object(["behaviorHints": .object(["videoSize": .integer(999), "filename": .string("Owned & release.mkv")])]))
        request.movieHash = remote
        let plans = try await request.plans(), plan = try XCTUnwrap(plans.first)
        XCTAssertTrue(plan.url.contains("videoHash=" + local.hash)); XCTAssertTrue(plan.url.contains("videoSize=200000"))
        XCTAssertFalse(plan.url.contains("owned-only")); XCTAssertFalse(plan.url.contains("127.0.0.1"))
        XCTAssertTrue(plan.url.contains("%26")); XCTAssertNil(URLComponents(string: plan.url)?.query)
    }
    func testUnseekableSmallOrCancelledSourcesCannotSupplyAFalseMovieHash() async throws {
        let server = try SubtitleRangeFixture(data: Data(repeating: 0, count: 200000), honorsRanges: false)
        defer { server.stop() }
        let url = try await server.start()
        do {
            _ = try await SubtitleMovieHashService.compute(.init(url: url.absoluteString, headers: nil, subtitles: nil, via: "test-fixture"))
            XCTFail("A full HTTP response must not be treated as the requested range")
        } catch let error as HarborError { XCTAssertEqual(error.code, "subtitle-hash-range") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("owned-small-" + UUID().uuidString)
        try Data([1, 2, 3]).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let source = PlaybackSource(url: file.absoluteString, headers: nil, subtitles: nil, via: "test-fixture")
        do { _ = try await SubtitleMovieHashService.compute(source); XCTFail("Too small to hash") }
        catch let error as HarborError { XCTAssertEqual(error.code, "subtitle-hash-size") }
        let (gate, release) = AsyncStream<Void>.makeStream()
        let cancelled = Task { for await _ in gate { }; try Task.checkCancellation(); return try await SubtitleMovieHashService.compute(source) }
        cancelled.cancel()
        release.finish()
        do { _ = try await cancelled.value; XCTFail("Cancelled lookup must not yield a file identity") }
        catch is CancellationError { }
    }
}
