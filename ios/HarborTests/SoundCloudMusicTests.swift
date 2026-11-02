import Foundation
import XCTest
@testable import Harbor

private actor OwnedSoundCloudNetwork: HarborNativeNetworkCalling {
    private(set) var requests: [HarborNetworkRequest] = []
    static let recording = """
    {"id":77,"title":"Owned Song","duration":180000,"streamable":true,"policy":"ALLOW","user":{"username":"Owned Artist"},"media":{"transcodings":[{"url":"https://api-v2.soundcloud.com/media/owned","preset":"aac_160k","snipped":false,"format":{"protocol":"hls","mime_type":"audio/mp4"}}]}}
    """
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        let url = try XCTUnwrap(URL(string: request.url))
        let body: String
        switch (url.host, url.path) {
        case ("soundcloud.com", "/"): body = "<script src=\"https://a-v2.sndcdn.com/assets/owned.js\"></script>"
        case ("a-v2.sndcdn.com", _): body = "client_id:\"" + String(repeating: "a", count: 32) + "\""
        case (_, "/search/tracks"): body = "{\"collection\":[" + Self.recording + "]}"
        case (_, "/tracks"): body = "[" + Self.recording + "]"
        case (_, "/media/owned"): body = "{\"url\":\"https://audio.sndcdn.com/owned-fixture.m3u8\"}"
        default: throw HarborError(code: "owned-unexpected-soundcloud-route")
        }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(body.utf8).base64EncodedString(), url: request.url)
    }
}
@MainActor final class SoundCloudMusicTests: XCTestCase {
    func testConsentSearchPublicIdentityAndFullStreamResolutionUseRealNativeRequests() async throws {
        let scope = PluginExecutionScope(owner: "owned-cloud-" + UUID().uuidString, activation: UUID()), network = OwnedSoundCloudNetwork()
        let service = SoundCloudMusicService(scope: scope, currentScope: { scope }, network: network)
        defer { service.setEnabled(false); service.dispose() }
        let absent = try await service.search("Owned Song", limit: 10)
        XCTAssertTrue(absent.tracks.isEmpty)
        let beforeConsent = await network.requests
        XCTAssertTrue(beforeConsent.isEmpty)
        service.setEnabled(true)
        let result = try await service.search("Owned Song", limit: 10), track = try XCTUnwrap(result.tracks.first)
        XCTAssertEqual(track.id, "soundcloud:77"); XCTAssertEqual(track.artist, "Owned Artist")
        let stream = try await service.resolve(track)
        XCTAssertEqual(stream.url.absoluteString, "https://audio.sndcdn.com/owned-fixture.m3u8")
        XCTAssertEqual(stream.mimeType, "application/vnd.apple.mpegurl"); XCTAssertEqual(stream.bitrate, 160_000)
        let requests = await network.requests
        XCTAssertEqual(requests.filter { URL(string: $0.url)?.host == "soundcloud.com" }.count, 1)
        XCTAssertTrue(requests.allSatisfy(\.publicNetworkOnly))
        XCTAssertTrue(requests.filter { URL(string: $0.url)?.host == "api-v2.soundcloud.com" }.allSatisfy { URLComponents(string: $0.url)?.queryItems?.contains { $0.name == "client_id" } == true })
        service.setEnabled(false)
        do { _ = try await service.resolve(track); XCTFail("Revoking source consent retires resolution") } catch is CancellationError { }
    }
    func testTypedSoundCloudSearchIncludesOriginalArtistAndPlaylistBucketsAndToleratesSideFailure() async throws {
        let scope = PluginExecutionScope(owner: "owned-cloud-typed-" + UUID().uuidString, activation: UUID()), network = TypedSoundCloudNetwork()
        let service = SoundCloudMusicService(scope: scope, currentScope: { scope }, network: network)
        defer { service.setEnabled(false); service.dispose() }
        service.setEnabled(true)
        let result = try await service.search("  Owned  ", limit: 80)
        XCTAssertEqual(result.tracks.count, 1)
        XCTAssertEqual(result.artists.first?.name, "Owned artist")
        XCTAssertEqual(result.artists.first?.artwork, "https://i1.sndcdn.com/owned-t500x500.jpg")
        XCTAssertEqual(result.playlists.first?.name, "Owned playlist")
        let requests = await network.requests
        let api = requests.compactMap { URLComponents(string: $0.url) }.filter { $0.host == "api-v2.soundcloud.com" }
        XCTAssertEqual(Set(api.map(\.path)), Set(["/search/tracks", "/search/users", "/search/playlists"]))
        XCTAssertEqual(api.first { $0.path == "/search/tracks" }?.queryItems?.first { $0.name == "limit" }?.value, "50")
        XCTAssertEqual(api.first { $0.path == "/search/users" }?.queryItems?.first { $0.name == "limit" }?.value, "12")
        XCTAssertTrue(api.allSatisfy { $0.queryItems?.contains { $0.name == "q" && $0.value == "Owned" } == true })
        await network.failSideBuckets()
        let fallback = try await service.search("Owned", limit: 5)
        XCTAssertEqual(fallback.tracks.count, 1); XCTAssertTrue(fallback.artists.isEmpty); XCTAssertTrue(fallback.playlists.isEmpty)
        XCTAssertEqual(service.health, .healthy)
    }
    func testTranscodingKeepsOriginalPreferenceAndDoesNotChooseEncryptedOrPreviewOnlyStreams() throws {
        func entry(_ proto: String, preset: String, snipped: Bool = false) -> JSONValue {
            .object(["url": .string("https://api-v2.soundcloud.com/owned"), "preset": .string(preset), "snipped": .bool(snipped), "format": .object(["protocol": .string(proto)])])
        }
        let hls = entry("hls", preset: "aac_160k"), progressive = entry("progressive", preset: "mp3_0_0"), preview = entry("progressive", preset: "mp3_0_0", snipped: true)
        func selected(_ entries: [JSONValue]) -> JSONValue? { SoundCloudMusicService.transcoding(.object(["media": .object(["transcodings": .array(entries)])])) }
        XCTAssertEqual(selected([hls, progressive]), progressive)
        XCTAssertEqual(selected([hls, preview]), hls)
        XCTAssertNil(selected([entry("ctr-hls", preset: "aac_160k"), entry("hls", preset: "abr_sq")]))
        let blocked = try JSONDecoder().decode(JSONValue.self, from: Data("{\"id\":77,\"title\":\"Owned\",\"policy\":\"BLOCK\"}".utf8))
        XCTAssertNil(SoundCloudMusicService.track(blocked))
    }
}

private actor TypedSoundCloudNetwork: HarborNativeNetworkCalling {
    private(set) var requests: [HarborNetworkRequest] = []
    private var failed = false
    func failSideBuckets() { failed = true }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        let url = try XCTUnwrap(URL(string: request.url))
        let body: String
        switch (url.host, url.path) {
        case ("soundcloud.com", "/"): body = "<script src=\"https://a-v2.sndcdn.com/assets/owned.js\"></script>"
        case ("a-v2.sndcdn.com", _): body = "client_id:\"" + String(repeating: "a", count: 32) + "\""
        case (_, "/search/tracks"): body = "{\"collection\":[" + OwnedSoundCloudNetwork.recording + "]}"
        case (_, "/search/users"):
            if failed { throw HarborError(code: "owned-side-unavailable") }
            body = #"{"collection":[{"id":5,"username":" Owned artist ","avatar_url":"https://i1.sndcdn.com/owned-large.jpg"},{"id":6,"username":" "}]}"#
        case (_, "/search/playlists"):
            if failed { throw HarborError(code: "owned-side-unavailable") }
            body = #"{"collection":[{"id":7,"title":"Owned playlist","track_count":1}]}"#
        default: throw HarborError(code: "owned-unexpected-cloud-request")
        }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(body.utf8).base64EncodedString(), url: request.url)
    }
}
