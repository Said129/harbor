import XCTest
@testable import Harbor

@MainActor final class DebridStreamTests: XCTestCase {
    private let cachedHash = "aabbccddeeff00112233445566778899aabbccdd"
    private let libraryHash = "00112233445566778899aabbccddeeff00112233"
    private let plainHash = "ffeeddccbbaa99887766554433221100ffeeddcc"

    private func torrent(_ hash: String, title: String = "Owned.Show.S01E01.1080p.WEB-DL.H264.AAC", extra: [String: JSONValue] = [:]) -> JSONValue {
        var value: [String: JSONValue] = ["addonId": .string("owned"), "addonName": .string("Owned"), "title": .string(title), "infoHash": .string(hash), "size": .integer(2_000_000_000)]
        for (key, item) in extra { value[key] = item }
        return .object(value)
    }
    private func fixture() throws -> DebridFixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "debrid-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(DebridFixture.self, from: Data(contentsOf: url))
    }

    func testRealRustRankingAppliesProviderFlagsAndAutomaticRankingKeepsThem() async throws {
        let preferences = StreamPreferences.shared, old = preferences.filterLevel
        preferences.filterLevel = "off"; defer { preferences.filterLevel = old }
        let media = Media(id: "tt0903747", type: "series", name: "Owned Show", releaseInfo: "2008")
        let verification = DebridVerification(cached: ["rd": [cachedHash.uppercased()]], library: ["tb": [libraryHash]])
        let ranked: JSONValue = try await CoreBridge().call("rank", [
            "streams": .array([torrent(cachedHash), torrent(libraryHash, title: "Owned.Show.S01E01.720p.WEB-DL.H264.AAC"), torrent(plainHash, title: "Owned.Show.S01E01.480p.WEB-DL.H264.AAC")]),
            "trust": StreamFilterConfiguration(level: "off", addonOrder: true).trust(media, season: 1, episode: 1),
            "score": .object(["activeDebrids": .array([.string("rd"), .string("tb")])]), "debrid": verification.flags])
        let all = ranked["picker"]["all"].array.enumerated().map { StreamOffer(id: $0.offset, raw: $0.element) }
        func offer(_ hash: String) throws -> StreamOffer { try XCTUnwrap(all.first { $0.raw["infoHash"].string == hash }) }
        let cached = try offer(cachedHash), library = try offer(libraryHash), plain = try offer(plainHash)
        XCTAssertEqual(cached.raw["cached"]["rd"], .bool(true)); XCTAssertEqual(cached.raw["cacheVerified"]["rd"], .bool(true)); XCTAssertNotEqual(cached.raw["inLibrary"]["rd"], .bool(true))
        XCTAssertEqual(library.raw["cached"]["tb"], .bool(true)); XCTAssertEqual(library.raw["inLibrary"]["tb"], .bool(true)); XCTAssertEqual(library.raw["cacheVerified"]["tb"], .bool(true))
        XCTAssertTrue(plain.raw["cacheVerified"].objectValue.isEmpty, "A hash no provider confirmed is not verified")
        XCTAssertTrue(cached.automaticallyPlayable && library.automaticallyPlayable); XCTAssertFalse(plain.automaticallyPlayable)
        XCTAssertEqual(cached.pickerStatus, "Cached")
        // Ranking the same offers again, as automatic selection does, rebuilds the flags from them.
        XCTAssertEqual(DebridVerification.from(offers: all.map(\.raw)), DebridVerification(cached: ["rd": [cachedHash]], library: ["tb": [libraryHash]]))
        let automatic = try await HarborService().automaticStreams(all, media: media, season: 1, episode: 1)
        let kept = try XCTUnwrap(automatic.first { $0.raw["infoHash"].string == cachedHash })
        XCTAssertEqual(kept.raw["cacheVerified"]["rd"], .bool(true), "The second ranking keeps the provider verification")
    }

    func testWithoutVerificationTorrentsAreNeverChosenAutomaticallyAndTextMarkersDoNotCount() {
        let marked = StreamOffer(id: 0, raw: torrent(plainHash, extra: ["name": .string("[RD+] ⚡ Owned"), "cached": .object(["rd": .bool(true)])]))
        XCTAssertFalse(marked.automaticallyPlayable, "Only a real provider check verifies a torrent")
        let direct = StreamOffer(id: 1, raw: .object(["addonId": .string("owned"), "addonName": .string("Owned"), "title": .string("Owned"), "url": .string("https://cdn.owned.example/a.mkv")]))
        XCTAssertTrue(direct.automaticallyPlayable)
        let verified = StreamOffer(id: 2, raw: torrent(cachedHash, extra: ["cacheVerified": .object(["rd": .bool(true)])]))
        XCTAssertTrue(verified.automaticallyPlayable)
        XCTAssertEqual(DebridStreamVerifier.hashes([torrent("  AABB  "), torrent("aabb"), direct.raw, torrent("ccdd")]), ["aabb", "ccdd"])
    }

    func testProvidersAreTriedCachedFirstThenInConfiguredOrder() {
        let all = DebridProvider.allCases
        XCTAssertEqual(DebridStreamResolver.order(all, cached: [:]), all)
        XCTAssertEqual(DebridStreamResolver.order(all, cached: ["pm": .bool(true)]).map(\.rawValue), ["pm", "rd", "tb", "ad", "dl"])
        XCTAssertEqual(DebridStreamResolver.order(all, cached: ["dl": .bool(true), "tb": .bool(true), "rd": .bool(false)]).map(\.rawValue), ["tb", "dl", "rd", "ad", "pm"])
    }

    func testProviderErrorClipsAreRejectedLikeDesktopAndOnlyPlainHttpLinksReachThePlayer() throws {
        func link(_ url: String = "https://cdn.owned.example/a.mkv", size: Double? = nil) -> DebridLink {
            DebridLink(url: url, fileIdx: nil, filename: nil, filesize: size, headers: ["Referer": "https://owned.example"], notWebReady: nil, subtitles: [.init(url: "https://cdn.owned.example/a.srt", lang: "es", id: "1")])
        }
        let eighty = 80.0 * 1_048_576, gib = 1_073_741_824.0
        XCTAssertTrue(DebridStreamResolver.validLink(link(), expectedSize: nil), "An unknown size is accepted")
        XCTAssertTrue(DebridStreamResolver.validLink(link(size: 2 * gib), expectedSize: 2 * gib))
        XCTAssertFalse(DebridStreamResolver.validLink(link(size: 10_000_000), expectedSize: nil), "A tiny file is an error clip")
        XCTAssertFalse(DebridStreamResolver.validLink(link(size: 10_000_000), expectedSize: 2 * gib))
        XCTAssertTrue(DebridStreamResolver.validLink(link(size: 10_000_000), expectedSize: 20_000_000), "A genuinely small release is allowed")
        XCTAssertFalse(DebridStreamResolver.validLink(link(size: 300 * 1_048_576), expectedSize: 2 * gib), "Under 40% of the expected size")
        XCTAssertTrue(DebridStreamResolver.validLink(link(size: eighty + 1), expectedSize: nil))
        let source = try XCTUnwrap(DebridStreamResolver.playbackSource(link(), via: .rd))
        XCTAssertEqual(source.via, "rd"); XCTAssertEqual(source.headers?["Referer"], "https://owned.example"); XCTAssertEqual(source.subtitles?.first?.lang, "es")
        for bad in ["javascript:alert(1)", "file:///private/a.mkv", "ftp://owned.example/a.mkv", "https://", "https://owned.example/a\u{0}.mkv", ""] {
            XCTAssertNil(DebridStreamResolver.playbackSource(link(bad), via: .rd), bad)
        }
    }

    func testTorrentOnlyStreamResolvesThroughDebridWithTheEpisodeHintAndDirectStreamsKeepTheNativePath() async throws {
        let fixture = try fixture(), scope = DebridScope(), network = DebridFixtureNetwork(script: try XCTUnwrap(fixture.scripts["flow"]))
        let client = DebridClient(scope: scope.value, currentScope: { scope.value }, transport: DebridTransport(network: network))
        defer { try? client.saveKey("", for: .rd); client.dispose() }
        try client.saveKey(fixture.key, for: .rd)
        let offer = StreamOffer(id: 0, raw: torrent(fixture.hash, extra: ["cached": .object(["rd": .bool(true)])]))
        let source = try await HarborService().resolve(offer, debrid: client, season: 1, episode: 1)
        XCTAssertEqual(source.url, fixture.playable.value?.url); XCTAssertEqual(source.via, "rd")
        let seen = await network.observations
        XCTAssertEqual(seen.first { $0.url.hasSuffix("/selectFiles/RD1") }?.body, "files=1", "The season and episode choose the file")
        // A stream with a URL never touches a provider.
        let direct = StreamOffer(id: 1, raw: .object(["addonId": .string("owned"), "addonName": .string("Owned"), "title": .string("Owned"), "url": .string("https://cdn.owned.example/direct.mkv")]))
        let before = await network.observations.count
        let plain = try await HarborService().resolve(direct, debrid: client)
        XCTAssertEqual(plain.url, "https://cdn.owned.example/direct.mkv")
        let after = await network.observations.count; XCTAssertEqual(before, after)
    }

    func testMissingDebridConfigurationAndSourcesWithoutAnythingToPlayReportDesktopCodes() async throws {
        let scope = DebridScope(), client = DebridClient(scope: scope.value, currentScope: { scope.value }, transport: DebridTransport(network: DebridFixtureNetwork(script: [:])))
        defer { client.dispose() }
        let offer = StreamOffer(id: 0, raw: torrent(cachedHash))
        for debrid in [nil, client] as [DebridClient?] {
            do { _ = try await HarborService().resolve(offer, debrid: debrid); XCTFail("A torrent needs a configured debrid service") }
            catch let error as HarborError { XCTAssertEqual(error.code, "no-debrid-configured"); XCTAssertTrue(error.errorDescription?.contains("Servicios de debrid") == true) }
        }
        do { _ = try await DebridStreamResolver.resolve(.object(["title": .string("No hash")]), client: client); XCTFail("No hash") }
        catch let error as HarborError { XCTAssertEqual(error.code, "no-source") }
        for code in ["not-cached", "unauthorized", "not-premium", "rate-limited", "stub-or-error-video", "all-debrids-failed"] {
            XCTAssertNotNil(HarborError(code: code).errorDescription, code)
        }
    }
}
