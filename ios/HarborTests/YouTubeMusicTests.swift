import Foundation
import XCTest
@testable import Harbor

private actor OwnedYouTubeNetwork: HarborNativeNetworkCalling {
    private(set) var requests: [HarborNetworkRequest] = []
    private var challenges: Int
    private var visitors = 0
    init(challenges: Int = 0) { self.challenges = challenges }
    static func search(visitor: String) -> String {
        """
        {"responseContext":{"visitorData":"\(visitor)"},"contents":{"tabbedSearchResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[{"itemSectionRenderer":{}},{"musicShelfRenderer":{"contents":[
        {"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"vK1YiArMDfg"},"thumbnail":{"musicThumbnailRenderer":{"thumbnail":{"thumbnails":[{"url":"https://yt3.googleusercontent.com/owned=w60-h60-l90-rj","width":60},{"url":"https://yt3.googleusercontent.com/owned=w120-h120-l90-rj","width":120}]}}},"badges":[{"musicInlineBadgeRenderer":{"icon":{"iconType":"MUSIC_EXPLICIT_BADGE"}}}],"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"California"}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Lana Del Rey"},{"text":" \u{2022} "},{"text":"Norman Fucking Rockwell!"},{"text":" \u{2022} "},{"text":"5:06"}]}}}]}},
        {"musicItemRendererDisplayPolicy":"MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT","musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"greyedout01"},"flexColumns":[]}},
        {"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"XOLLKo2qQfY"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"West Coast"}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Lana Del Rey"},{"text":" \u{2022} "},{"text":"Ultraviolence"},{"text":" \u{2022} "},{"text":"4:17"}]}}}]}}
        ]}}]}}}}]}}}
        """
    }
    static let formats = """
    {"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[
    {"itag":251,"mimeType":"audio/webm; codecs=\\"opus\\"","bitrate":135763,"url":"https://rr1---sn-owned.googlevideo.com/videoplayback?itag=251"},
    {"itag":140,"mimeType":"audio/mp4; codecs=\\"mp4a.40.2\\"","bitrate":131097,"url":"https://rr1---sn-owned.googlevideo.com/videoplayback?itag=140"},
    {"itag":137,"mimeType":"video/mp4; codecs=\\"avc1\\"","bitrate":4000000,"url":"https://rr1---sn-owned.googlevideo.com/videoplayback?itag=137"}]}}
    """
    static let challenge = #"{"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in to confirm you're not a bot"}}"#
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        let url = try XCTUnwrap(URL(string: request.url))
        let body: String
        switch (url.host, url.path) {
        case ("music.youtube.com", "/youtubei/v1/search"): visitors += 1; body = Self.search(visitor: "CgtOwnedVisitor\(visitors)")
        case ("www.youtube.com", "/youtubei/v1/player"):
            if challenges > 0 { challenges -= 1; body = Self.challenge } else { body = Self.formats }
        default: throw HarborError(code: "owned-unexpected-youtube-route")
        }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data(body.utf8).base64EncodedString(), url: request.url)
    }
}

@MainActor final class YouTubeMusicTests: XCTestCase {
    private func makeService(_ network: OwnedYouTubeNetwork) -> (YouTubeMusicService, UserDefaults) {
        let scope = PluginExecutionScope(owner: "owned-youtube-" + UUID().uuidString, activation: UUID())
        let defaults = UserDefaults(suiteName: "owned-youtube-" + UUID().uuidString)!
        return (YouTubeMusicService(scope: scope, currentScope: { scope }, network: network, defaults: defaults), defaults)
    }
    private func body(_ request: HarborNetworkRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(Data(base64Encoded: XCTUnwrap(request.bodyBase64))))
    }
    private var recording: MusicTrack {
        .init(id: "youtube:vK1YiArMDfg", connectorId: "youtube", sourceId: "vK1YiArMDfg", playbackUrl: nil, title: "California", artist: "Lana Del Rey", album: nil,
              artwork: "", durationSeconds: 306, durationLabel: "5:06")
    }

    func testSearchReadsSongsAndTheVisitorIdTheFollowingPlayerRequestCarries() async throws {
        let network = OwnedYouTubeNetwork(), (service, defaults) = makeService(network)
        defer { service.dispose() }
        XCTAssertTrue(service.enabled, "Desktop plays from YouTube with no setup")
        let result = try await service.search("California", limit: 10)
        XCTAssertEqual(result.tracks.map(\.id), ["youtube:vK1YiArMDfg", "youtube:XOLLKo2qQfY"], "greyed-out rows are not offered")
        let track = try XCTUnwrap(result.tracks.first)
        XCTAssertEqual(track.connectorId, "youtube"); XCTAssertEqual(track.sourceId, "vK1YiArMDfg")
        XCTAssertEqual(track.title, "California"); XCTAssertEqual(track.artist, "Lana Del Rey"); XCTAssertEqual(track.album, "Norman Fucking Rockwell!")
        XCTAssertEqual(track.durationSeconds, 306); XCTAssertEqual(track.durationLabel, "5:06"); XCTAssertEqual(track.explicit, true)
        XCTAssertEqual(track.artwork, "https://yt3.googleusercontent.com/owned=w544-h544-l90-rj")
        XCTAssertNil(result.tracks.last?.explicit)
        XCTAssertEqual(service.health, .healthy)

        let stream = try await service.resolve(track)
        XCTAssertEqual(stream.url.absoluteString, "https://rr1---sn-owned.googlevideo.com/videoplayback?itag=140")
        XCTAssertEqual(stream.mimeType, "audio/mp4"); XCTAssertEqual(stream.bitrate, 131_097)
        XCTAssertEqual(stream.httpHeaders["User-Agent"], YouTubeMusicService.visionAgent)

        let requests = await network.requests
        XCTAssertEqual(requests.count, 2, "the search already named a visitor, so the player needs no extra call")
        let search = requests[0], player = requests[1]
        XCTAssertEqual(search.method, "POST"); XCTAssertNil(search.headers["X-Goog-Visitor-Id"])
        XCTAssertEqual(try body(search)["params"].string, YouTubeMusicService.songsFilter)
        XCTAssertEqual(try body(search)["context"]["client"]["clientName"].string, "WEB_REMIX")
        XCTAssertEqual(player.headers["X-Goog-Visitor-Id"], "CgtOwnedVisitor1")
        XCTAssertEqual(player.headers["X-Youtube-Client-Name"], "101")
        XCTAssertEqual(try body(player)["videoId"].string, "vK1YiArMDfg")
        XCTAssertEqual(try body(player)["context"]["client"]["clientName"].string, "VISIONOS")
        XCTAssertEqual(defaults.string(forKey: YouTubeMusicService.visitorKey), "CgtOwnedVisitor1")
        XCTAssertTrue(requests.allSatisfy(\.publicNetworkOnly)); XCTAssertTrue(requests.allSatisfy(\.openHeaders))

        service.setEnabled(false)
        do { _ = try await service.resolve(track); XCTFail("Turning the source off retires resolution") } catch is CancellationError { }
        let off = try await service.search("California", limit: 10)
        XCTAssertTrue(off.tracks.isEmpty)
    }

    func testABotChallengeGetsOneFreshVisitorBeforeTheTrackIsGivenUp() async throws {
        let network = OwnedYouTubeNetwork(challenges: 1), (service, defaults) = makeService(network)
        defer { service.dispose() }
        let stream = try await service.resolve(recording)
        XCTAssertTrue(stream.url.absoluteString.hasSuffix("itag=140"))
        let requests = await network.requests
        XCTAssertEqual(requests.compactMap { URL(string: $0.url)?.host }, ["music.youtube.com", "www.youtube.com", "music.youtube.com", "www.youtube.com"])
        XCTAssertEqual(requests[1].headers["X-Goog-Visitor-Id"], "CgtOwnedVisitor1")
        XCTAssertNil(requests[2].headers["X-Goog-Visitor-Id"], "the refreshed id is requested without the old one")
        XCTAssertEqual(requests[3].headers["X-Goog-Visitor-Id"], "CgtOwnedVisitor2")
        XCTAssertEqual(defaults.string(forKey: YouTubeMusicService.visitorKey), "CgtOwnedVisitor2")
    }

    func testASecondChallengeReportsTheSourceAsDegraded() async throws {
        let network = OwnedYouTubeNetwork(challenges: 2), (service, _) = makeService(network)
        defer { service.dispose() }
        do { _ = try await service.resolve(recording); XCTFail("Two challenges end the attempt") }
        catch let error as HarborError { XCTAssertEqual(error.code, "music-youtube-challenge") }
        XCTAssertEqual(service.health, .degraded)
    }

    func testFormatChoiceAndPlayabilityRules() throws {
        func response(_ formats: String, status: String = "OK", reason: String = "") throws -> JSONValue {
            try JSONDecoder().decode(JSONValue.self, from: Data(#"{"playabilityStatus":{"status":"\#(status)","reason":"\#(reason)"},"streamingData":{"adaptiveFormats":[\#(formats)]}}"#.utf8))
        }
        let opus = #"{"itag":251,"mimeType":"audio/webm; codecs=\"opus\"","bitrate":135763,"url":"https://rr2.googlevideo.com/videoplayback?itag=251"}"#
        let aac = #"{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":131097,"url":"https://rr2.googlevideo.com/videoplayback?itag=140"}"#
        XCTAssertEqual(YouTubeMusicService.stream(try response(opus + "," + aac))?.mimeType, "audio/mp4", "AAC plays everywhere, so it goes first")
        XCTAssertEqual(YouTubeMusicService.stream(try response(opus))?.mimeType, "audio/webm")
        let scrambled = #"{"itag":251,"mimeType":"audio/webm","signatureCipher":"s=abc"}"#
        let elsewhere = #"{"itag":140,"mimeType":"audio/mp4","url":"https://example.com/audio"}"#
        XCTAssertNil(YouTubeMusicService.stream(try response(scrambled + "," + elsewhere)), "no url, or a url off YouTube's media hosts, is never played")
        if case .challenge = YouTubeMusicService.verdict(try response(scrambled)) { } else { XCTFail("A response with nothing playable reads as a challenge") }
        if case .challenge = YouTubeMusicService.verdict(try response("", status: "LOGIN_REQUIRED", reason: "Sign in to confirm you're not a bot")) { } else { XCTFail("The bot check retries with a new visitor") }
        if case .unavailable = YouTubeMusicService.verdict(try response("", status: "UNPLAYABLE", reason: "This video has been removed by the uploader")) { } else { XCTFail("A removed video is final") }
        if case .unavailable = YouTubeMusicService.verdict(try response("", status: "ERROR", reason: "")) { } else { XCTFail("An error status is final") }
        if case .stream = YouTubeMusicService.verdict(try response(aac)) { } else { XCTFail("A playable response gives a stream") }
    }

    func testSpotifyWebPlayerFollowsOnlyHttpsPages() {
        XCTAssertTrue(SpotifyWebSession.allows(URL(string: "https://open.spotify.com/track/abc")))
        XCTAssertTrue(SpotifyWebSession.allows(URL(string: "https://accounts.spotify.com/login")))
        XCTAssertTrue(SpotifyWebSession.allows(URL(string: "about:blank")))
        XCTAssertFalse(SpotifyWebSession.allows(URL(string: "spotify:track:abc")), "deep links that open the app are not followed")
        XCTAssertFalse(SpotifyWebSession.allows(URL(string: "http://open.spotify.com/")))
        XCTAssertFalse(SpotifyWebSession.allows(nil))
    }

    func testSmallParsingRules() {
        XCTAssertEqual(YouTubeMusicService.seconds("5:06"), 306); XCTAssertEqual(YouTubeMusicService.seconds("1:02:03"), 3723)
        XCTAssertNil(YouTubeMusicService.seconds("Norman Fucking Rockwell!")); XCTAssertNil(YouTubeMusicService.seconds("5:"))
        XCTAssertEqual(YouTubeMusicService.clientVersion(Date(timeIntervalSince1970: 20_698 * 86_400)), "1.20260902.01.00")
        XCTAssertEqual(YouTubeMusicService.clientVersion(Date(timeIntervalSince1970: 20_698 * 86_400 + 86_399)), "1.20260902.01.00")
        XCTAssertEqual(YouTubeMusicService.videoID(recording), "vK1YiArMDfg")
        let other = MusicTrack(id: "youtube:bad id", connectorId: "youtube", sourceId: nil, playbackUrl: nil, title: "x", artist: "y", album: nil, artwork: "", durationSeconds: 0, durationLabel: "")
        XCTAssertNil(YouTubeMusicService.videoID(other))
        XCTAssertEqual(YouTubeMusicService.artwork("https://i.ytimg.com/vi/abc/hqdefault.jpg"), "https://i.ytimg.com/vi/abc/hqdefault.jpg")
    }
}
