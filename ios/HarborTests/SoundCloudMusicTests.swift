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
