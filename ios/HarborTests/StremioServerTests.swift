import XCTest
@testable import Harbor

/// Desktop's remote streaming server policy and client (`lib/stremio-server.ts`, `lib/torrent/stremio-stream.ts`,
/// `lib/streams/resolve.ts`). The transport is canned, so no test touches the network.
final class StremioServerTests: XCTestCase {
    private final class RequestBox: @unchecked Sendable {
        var requests: [URLRequest] = []
    }

    private struct CannedTransport: StremioServerTransport {
        let status: Int
        let body: Data
        var failure = false
        var box: RequestBox?

        func send(_ request: URLRequest) async throws -> StremioServerReply {
            box?.requests.append(request)
            if failure { throw URLError(.cannotConnectToHost) }
            return StremioServerReply(status: status, data: body)
        }
    }

    private func client(status: Int = 200, body: String = "{}", failure: Bool = false, box: RequestBox? = nil) -> StremioServerClient {
        StremioServerClient(transport: CannedTransport(status: status, body: Data(body.utf8), failure: failure, box: box))
    }

    // MARK: Address

    func testNormalizedAddressAddsSchemeAndDropsTrailingSlashes() {
        XCTAssertEqual(StremioServerPolicy.normalized("192.168.1.50:11470/"), "http://192.168.1.50:11470")
        XCTAssertEqual(StremioServerPolicy.normalized("  https://home.example/stremio//  "), "https://home.example/stremio")
        XCTAssertEqual(StremioServerPolicy.normalized("HTTP://Host.example:11470"), "HTTP://Host.example:11470")
        XCTAssertEqual(StremioServerPolicy.normalized("   "), "")
    }

    func testStoredAddressTrimsWhitespaceAndSlashes() {
        XCTAssertEqual(StremioServerPolicy.storedAddress(" http://10.0.0.2:11470/// "), "http://10.0.0.2:11470")
        XCTAssertEqual(StremioServerPolicy.storedAddress("/"), "")
    }

    func testWellFormedRequiresHTTPSchemeAndHost() {
        XCTAssertTrue(StremioServerPolicy.isWellFormed("http://192.168.1.50:11470"))
        XCTAssertTrue(StremioServerPolicy.isWellFormed("https://home.example"))
        XCTAssertFalse(StremioServerPolicy.isWellFormed("ftp://host.example"))
        XCTAssertFalse(StremioServerPolicy.isWellFormed("http://"))
        XCTAssertFalse(StremioServerPolicy.isWellFormed(""))
    }

    func testEngineBaseIsTheSavedServerOrNil() {
        XCTAssertEqual(StremioServerPolicy.engineBase(address: "http://10.0.0.2:11470/"), "http://10.0.0.2:11470")
        XCTAssertNil(StremioServerPolicy.engineBase(address: ""))
    }

    // MARK: Strict policy

    func testStrictOnlyCountsWithAnAddress() {
        XCTAssertFalse(StremioServerPolicy.isStrict(address: "", flag: true))
        XCTAssertFalse(StremioServerPolicy.isStrict(address: "http://10.0.0.2:11470", flag: false))
        XCTAssertTrue(StremioServerPolicy.isStrict(address: "http://10.0.0.2:11470", flag: true))
    }

    func testStrictBlocksLocalFallbackAndPicksTheStrictFailureCode() {
        XCTAssertFalse(StremioServerPolicy.localFallbackAllowed(address: "http://10.0.0.2:11470", flag: true))
        XCTAssertTrue(StremioServerPolicy.localFallbackAllowed(address: "http://10.0.0.2:11470", flag: false))
        XCTAssertTrue(StremioServerPolicy.localFallbackAllowed(address: "", flag: true))
        XCTAssertEqual(StremioServerPolicy.unreachableFailureCode(strict: true), "remote-server-unreachable-strict")
        XCTAssertEqual(StremioServerPolicy.unreachableFailureCode(strict: false), "remote-server-unreachable")
    }

    func testConnectionStates() {
        XCTAssertEqual(StremioServerPolicy.connection(address: "", reachable: nil), .notSet)
        XCTAssertEqual(StremioServerPolicy.connection(address: "http://a:1", reachable: nil), .checking)
        XCTAssertEqual(StremioServerPolicy.connection(address: "http://a:1", reachable: true), .connected)
        XCTAssertEqual(StremioServerPolicy.connection(address: "http://a:1", reachable: false), .unreachable)
    }

    // MARK: URLs

    func testStreamURLWithTrackersAndFilename() {
        let url = StremioServerPolicy.streamURL(base: "http://192.168.1.50:11470", infoHash: "ABCDEF0123456789ABCDEF0123456789ABCDEF01",
                                                fileIdx: 3, trackers: ["udp://tracker.example:80/announce"], filename: "Movie 1.mkv")
        XCTAssertEqual(url, "http://192.168.1.50:11470/abcdef0123456789abcdef0123456789abcdef01/3?tr=udp%3A%2F%2Ftracker.example%3A80%2Fannounce&f=Movie+1.mkv")
    }

    func testStreamURLWithoutFileIndexUsesMinusOne() {
        let url = StremioServerPolicy.streamURL(base: "http://h:1", infoHash: "aa", fileIdx: nil, trackers: [], filename: nil)
        XCTAssertEqual(url, "http://h:1/aa/-1")
        XCTAssertEqual(StremioServerPolicy.streamURL(base: "http://h:1", infoHash: "aa", fileIdx: -4, trackers: [], filename: ""), "http://h:1/aa/-1")
    }

    func testTrackersFromSourcesKeepsTrackerEntriesAndSkipsDHT() {
        let sources = ["tracker:udp://a.example:1/x", "dht:abc", "https://t.example/announce", "junk", "wss://w.example"]
        XCTAssertEqual(StremioServerPolicy.trackers(fromSources: sources),
                       ["udp://a.example:1/x", "https://t.example/announce", "wss://w.example"])
    }

    func testTranscodeURLUsesH264AndAACHLS() {
        let url = StremioServerPolicy.transcodeURL(base: "http://h:1", sourceURL: "http://h:1/aa/0?f=x.mkv", id: "0123")
        XCTAssertEqual(url, "http://h:1/hlsv2/0123/master.m3u8?mediaURL=http%3A%2F%2Fh%3A1%2Faa%2F0%3Ff%3Dx.mkv&videoCodecs=h264&audioCodecs=aac&audioChannels=2")
    }

    func testTranscodeIDIsThirtyTwoLowercaseHexCharacters() {
        let id = StremioServerPolicy.newTranscodeID()
        XCTAssertEqual(id.count, 32)
        XCTAssertNotNil(id.range(of: "^[0-9a-f]{32}$", options: .regularExpression))
    }

    // MARK: Create body and response

    func testCreateBodyWithoutEpisodeSendsEmptyGuess() {
        let body = StremioServerPolicy.createBody(infoHash: "ABCD", trackers: ["udp://t.example:1"], season: nil, episode: nil)
        XCTAssertEqual(body["torrent"]["infoHash"].string, "abcd")
        XCTAssertEqual(body["peerSearch"]["sources"].array, [.string("dht:abcd"), .string("udp://t.example:1")])
        XCTAssertEqual(body["peerSearch"]["min"].integer, 40)
        XCTAssertEqual(body["peerSearch"]["max"].integer, 200)
        XCTAssertEqual(body["guessFileIdx"], .object([:]))
    }

    func testCreateBodyWithSeasonAndEpisodeSendsTheGuess() {
        let body = StremioServerPolicy.createBody(infoHash: "abcd", trackers: [], season: 2, episode: 5)
        XCTAssertEqual(body["guessFileIdx"]["season"].integer, 2)
        XCTAssertEqual(body["guessFileIdx"]["episode"].integer, 5)
    }

    func testParseCreatedReadsTopLevelFiles() throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"files":[{"path":"Show/S01E02.mkv","length":123},{"name":"a.txt","size":5}],"guessedFileIdx":0}"#.utf8))
        let parsed = StremioServerPolicy.parseCreated(json)
        XCTAssertEqual(parsed?.files, [
            StremioServerPolicy.CreatedFile(idx: 0, name: "S01E02.mkv", length: 123),
            StremioServerPolicy.CreatedFile(idx: 1, name: "a.txt", length: 5),
        ])
        XCTAssertEqual(parsed?.guessedFileIdx, 0)
    }

    func testParseCreatedReadsNestedTorrentFilesAndMissingGuess() throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"torrent":{"files":[{"idx":7,"name":"m.mp4","length":9}]}}"#.utf8))
        let parsed = StremioServerPolicy.parseCreated(json)
        XCTAssertEqual(parsed?.files, [StremioServerPolicy.CreatedFile(idx: 7, name: "m.mp4", length: 9)])
        XCTAssertNil(parsed?.guessedFileIdx)
    }

    func testParseCreatedWithoutAFileListIsNil() throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"ok":true}"#.utf8))
        XCTAssertNil(StremioServerPolicy.parseCreated(json))
    }

    // MARK: Client

    func testHealthIsReachableOnA200WithAtLeastOneMillisecond() async {
        let health = await client(status: 200, body: "{}").health(base: "http://192.168.1.50:11470")
        guard case .reachable(let milliseconds) = health else { return XCTFail("expected reachable, got \(health)") }
        XCTAssertGreaterThanOrEqual(milliseconds, 1)
    }

    func testHealthReportsTheStatusOfANonSuccessAnswer() async {
        let health = await client(status: 404).health(base: "http://192.168.1.50:11470")
        XCTAssertEqual(health, .badStatus(404))
    }

    func testHealthIsUnreachableWhenTheRequestFails() async {
        let health = await client(failure: true).health(base: "http://192.168.1.50:11470")
        XCTAssertEqual(health, .unreachable)
    }

    func testHealthProbesSettingsWithGET() async {
        let box = RequestBox()
        _ = await client(status: 200, box: box).health(base: "http://192.168.1.50:11470")
        XCTAssertEqual(box.requests.first?.url?.absoluteString, "http://192.168.1.50:11470/settings")
        XCTAssertEqual(box.requests.first?.httpMethod, "GET")
        XCTAssertEqual(box.requests.first?.timeoutInterval, StremioServerPolicy.probeTimeout)
    }

    func testCreateTorrentPostsToTheHashCreateEndpoint() async {
        let box = RequestBox()
        let body = #"{"files":[{"name":"a.mkv","length":10}],"guessedFileIdx":0}"#
        let created = await client(status: 200, body: body, box: box).createTorrent(base: "http://h:1", infoHash: "ABCD", trackers: [])
        XCTAssertEqual(created?.files.count, 1)
        XCTAssertEqual(box.requests.first?.url?.absoluteString, "http://h:1/abcd/create")
        XCTAssertEqual(box.requests.first?.httpMethod, "POST")
        XCTAssertEqual(box.requests.first?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(box.requests.first?.timeoutInterval, StremioServerPolicy.createTimeout)
    }

    func testCreateTorrentIsNilOnAServerError() async {
        let created = await client(status: 500, body: #"{"files":[]}"#).createTorrent(base: "http://h:1", infoHash: "abcd", trackers: [])
        XCTAssertNil(created)
    }

    func testCreateTorrentIsNilWhenTheRequestFails() async {
        let created = await client(failure: true).createTorrent(base: "http://h:1", infoHash: "abcd", trackers: [])
        XCTAssertNil(created)
    }

    // MARK: File choice

    func testEpisodeFileIndexPrefersAVideoNamingTheEpisode() {
        XCTAssertEqual(StremioServerPolicy.episodeFileIndex(names: ["notes.txt", "show 1x02.mkv"], season: 1, episode: 2), 1)
        XCTAssertEqual(StremioServerPolicy.episodeFileIndex(names: ["Show.S01E03.mkv", "Show.S01E02.mp4"], season: 1, episode: 2), 1)
        XCTAssertNil(StremioServerPolicy.episodeFileIndex(names: ["Show.S01E03.mkv"], season: 1, episode: 2))
        XCTAssertNil(StremioServerPolicy.episodeFileIndex(names: ["Show.S01E02.mkv"], season: nil, episode: 2))
    }

    func testChooseFileIndexFallsBackToTheLargestVideo() throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"files":[{"name":"Movie.mkv","length":100},{"name":"Extras.mkv","length":500},{"name":"notes.txt","length":900}]}"#.utf8))
        let files = try XCTUnwrap(StremioServerPolicy.parseCreated(json)).files
        XCTAssertEqual(StremioServerPolicy.chooseFileIndex(files, season: nil, episode: nil), 1)
        XCTAssertEqual(StremioServerPolicy.chooseFileIndex([], season: 1, episode: 1), nil)
    }

    // MARK: Resolver

    private let infoHashText = "ABCDEF0123456789ABCDEF0123456789ABCDEF01"
    private let episodeFiles = #"{"files":[{"name":"Show.S01E02.mkv","length":100},{"name":"Show.S01E03.mkv","length":300}]}"#

    private func stream(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testResolverBuildsTheStreamURLFromTheCreatedFiles() async throws {
        let raw = try stream(#"{"infoHash":"\#(infoHashText)","sources":["tracker:udp://t.example:1/a","dht:\#(infoHashText)"]}"#)
        let resolver = StremioServerResolver(client: client(body: episodeFiles), base: "http://h:1", strict: false)
        let result = await resolver.resolve(raw, season: 1, episode: 2)
        XCTAssertEqual(result, .stream(url: "http://h:1/abcdef0123456789abcdef0123456789abcdef01/0?tr=udp%3A%2F%2Ft.example%3A1%2Fa", fileIdx: 0))
    }

    func testResolverUsesTheRequestedFileIndexAndFilename() async throws {
        let raw = try stream(#"{"infoHash":"aa","fileIdx":4,"behaviorHints":{"filename":"Movie 1.mkv"}}"#)
        let resolver = StremioServerResolver(client: client(body: episodeFiles), base: "http://h:1", strict: false)
        let result = await resolver.resolve(raw, season: nil, episode: nil)
        XCTAssertEqual(result, .stream(url: "http://h:1/aa/4?f=Movie+1.mkv", fileIdx: 4))
    }

    func testResolverReportsTheStrictFailureCodeWhenUnreachable() async throws {
        let raw = try stream(#"{"infoHash":"\#(infoHashText)"}"#)
        let strict = StremioServerResolver(client: client(failure: true), base: "http://h:1", strict: true)
        let strictResult = await strict.resolve(raw, season: nil, episode: nil)
        XCTAssertEqual(strictResult, .failure(code: "remote-server-unreachable-strict"))
        let relaxed = StremioServerResolver(client: client(failure: true), base: "http://h:1", strict: false)
        let relaxedResult = await relaxed.resolve(raw, season: nil, episode: nil)
        XCTAssertEqual(relaxedResult, .failure(code: "remote-server-unreachable"))
    }

    func testResolverReportsNoPeersWhenTheServerListsNoFiles() async throws {
        let raw = try stream(#"{"infoHash":"\#(infoHashText)"}"#)
        let resolver = StremioServerResolver(client: client(body: #"{"files":[]}"#), base: "http://h:1", strict: false)
        let result = await resolver.resolve(raw, season: nil, episode: nil)
        XCTAssertEqual(result, .failure(code: "engine-no-peers"))
    }

    func testResolverNeedsAnInfoHash() async throws {
        let resolver = StremioServerResolver(client: client(body: episodeFiles), base: "http://h:1", strict: false)
        let raw = try stream("{}")
        let result = await resolver.resolve(raw, season: nil, episode: nil)
        XCTAssertEqual(result, .failure(code: "no-source"))
    }

    func testLiveResolverNeedsASavedAddress() {
        XCTAssertNil(StremioServerResolver.live(address: "  ", strict: false))
        XCTAssertEqual(StremioServerResolver.live(address: "http://h:1/", strict: true)?.base, "http://h:1")
    }

    // MARK: Per-profile keys

    func testRemoteServerSettingsAreProfileKeys() {
        let keys = ProfileSettingsStore.keys
        XCTAssertTrue(keys.contains("remoteStreamServerUrl"))
        XCTAssertTrue(keys.contains("remoteStreamServerStrict"))
        XCTAssertTrue(keys.contains("castAlwaysTranscode"))
        XCTAssertTrue(keys.contains("stremioServerTranscode"))
    }
}
