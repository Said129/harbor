import CryptoKit
import XCTest
@testable import Harbor

/// Community sync against Desktop 0.9.132 `lib/subtitles/autosync/crowd-db.ts`: the sub-timeline hash, the lookup URL and
/// answers, the 10 and 5 minute cache, the report limits and the settings gates. Every reply is scripted; nothing touches the network.
final class CommunitySyncTests: XCTestCase {
    actor ScriptedTransport: CommunitySyncTransport {
        enum Reply: Sendable { case reply(Int, String), failure }
        private var replies: [Reply]
        private(set) var requests: [URLRequest] = []
        init(_ replies: [Reply]) { self.replies = replies }
        func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
            requests.append(request)
            guard !replies.isEmpty else { throw HarborError(code: "network") }
            switch replies.removeFirst() {
            case .reply(let status, let body): return (status, Data(body.utf8))
            case .failure: throw HarborError(code: "network")
            }
        }
    }

    final class FakeClock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private let hit = #"{"tier":"A","offsetMs":-1500,"ratio":1,"confidence":0.93,"votes":7}"#
    private let server = "https://sync.example.com/"

    /// Cue i starts at 4i + 1.25 s and ends 1.25 s later.
    private func cues(_ count: Int = 10) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        for index in 0..<count {
            let base = Double(index) * 4.0
            result.append((base + 1.25, base + 2.5))
        }
        return result
    }

    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "CommunitySyncTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    // MARK: Hash

    func testHashNeedsEightUsableCues() {
        XCTAssertNil(CommunitySyncRules.subTimelineHash(cues(7)))
        XCTAssertNotNil(CommunitySyncRules.subTimelineHash(cues(8)))
        var withBadCue = cues(8)
        withBadCue[0] = (Double.nan, 2)
        XCTAssertNil(CommunitySyncRules.subTimelineHash(withBadCue))
    }

    func testHashIsSHA256OfSortedTenMillisecondCues() throws {
        // Cues in reverse order, the first one rounded: 1.2349 s -> 1230 ms and 2.5051 s -> 2510 ms.
        var input: [(Double, Double)] = Array(cues(8).reversed())
        input[7] = (1.2349, 2.5051)
        let text = "1230-2510;5250-6500;9250-10500;13250-14500;17250-18500;21250-22500;25250-26500;29250-30500"
        let expected = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", Int($0)) }.joined()
        XCTAssertEqual(CommunitySyncRules.subTimelineHash(input), expected)
    }

    func testHashIgnoresInputOrder() {
        XCTAssertEqual(CommunitySyncRules.subTimelineHash(cues(8)), CommunitySyncRules.subTimelineHash(cues(8).reversed()))
    }

    // MARK: Lookup URL and answers

    func testLookupURLCarriesTheHashAndTheRoundedDuration() throws {
        let hash = try XCTUnwrap(CommunitySyncRules.subTimelineHash(cues()))
        let url = try XCTUnwrap(CommunitySyncRules.lookupURL(server: server, cues: cues(), durationSec: 5400.0004))
        XCTAssertEqual(url.absoluteString, "https://sync.example.com/api/v1/lookup?sub=\(hash)&dur=5400000")
    }

    func testLookupWithoutAPositiveDurationOmitsDur() throws {
        let url = try XCTUnwrap(CommunitySyncRules.lookupURL(server: server, cues: cues(), durationSec: 0))
        XCTAssertFalse(url.absoluteString.contains("dur="))
    }

    func testTierOnlyAAndAffineAnswersAreKept() throws {
        let lookup = try XCTUnwrap(CommunitySyncRules.lookupResult(Data(hit.utf8)))
        XCTAssertEqual(lookup.tier, "A")
        XCTAssertEqual(lookup.offset, -1.5, accuracy: 0.0001)
        XCTAssertEqual(lookup.ratio, 1)
        XCTAssertEqual(lookup.confidence, 0.93, accuracy: 0.0001)
        XCTAssertNil(CommunitySyncRules.lookupResult(Data(#"{"tier":"D","offsetMs":0,"confidence":0.9}"#.utf8)))
        XCTAssertNil(CommunitySyncRules.lookupResult(Data(#"{"offsetMs":0,"confidence":0.9}"#.utf8)))
    }

    func testPiecewiseAnswerIsIgnored() {
        let piecewise = #"{"tier":"A","offsetMs":0,"ratio":1,"confidence":0.9,"anchors":[[0,0],[600000,1500]]}"#
        XCTAssertNil(CommunitySyncRules.lookupResult(Data(piecewise.utf8)))
    }

    func testOnlyTierAIsAppliedWithoutAudio() throws {
        let tierA = try XCTUnwrap(CommunitySyncRules.lookupResult(Data(hit.utf8)))
        XCTAssertNotNil(CommunitySyncRules.autoApplied(tierA))
        let tierB = CommunitySyncRules.Lookup(tier: "B", offset: 1, ratio: 1, confidence: 0.9)
        let tierC = CommunitySyncRules.Lookup(tier: "C", offset: 1, ratio: 1, confidence: 0.9)
        XCTAssertNil(CommunitySyncRules.autoApplied(tierB))
        XCTAssertNil(CommunitySyncRules.autoApplied(tierC))
    }

    func testAutoAppliedKeepsTheReportLimits() {
        let far = CommunitySyncRules.Lookup(tier: "A", offset: 60.5, ratio: 1, confidence: 0.9)
        let skewed = CommunitySyncRules.Lookup(tier: "A", offset: 1, ratio: 1.3, confidence: 0.9)
        XCTAssertNil(CommunitySyncRules.autoApplied(far))
        XCTAssertNil(CommunitySyncRules.autoApplied(skewed))
    }

    func testNotFoundAndFailedRequestsGiveNothing() async {
        let transport = ScriptedTransport([.reply(204, ""), .reply(500, ""), .reply(200, "not json")])
        let client = CommunitySyncClient(transport: transport)
        // Different durations give different cache keys, so each reply is really asked for.
        let noContent = await client.lookup(cues: cues(), durationSec: 1800, server: server)
        XCTAssertNil(noContent)
        let serverError = await client.lookup(cues: cues(), durationSec: 1801, server: server)
        XCTAssertNil(serverError)
        let garbage = await client.lookup(cues: cues(), durationSec: 1802, server: server)
        XCTAssertNil(garbage)
        let count = await transport.requests.count
        XCTAssertEqual(count, 3)
    }

    // MARK: Cache

    func testAHitIsKeptTenMinutesAndAMissFiveMinutes() async {
        let clock = FakeClock()
        let transport = ScriptedTransport([.reply(200, hit), .reply(204, ""), .reply(200, hit)])
        let client = CommunitySyncClient(transport: transport, clock: { clock.now })
        let first = await client.lookup(cues: cues(), durationSec: 1800, server: server)
        XCTAssertNotNil(first)
        _ = await client.lookup(cues: cues(), durationSec: 1800, server: server)
        var count = await transport.requests.count
        XCTAssertEqual(count, 1)

        clock.now = clock.now.addingTimeInterval(9 * 60)
        let stillHit = await client.lookup(cues: cues(), durationSec: 1800, server: server)
        XCTAssertNotNil(stillHit)
        count = await transport.requests.count
        XCTAssertEqual(count, 1)

        clock.now = clock.now.addingTimeInterval(61)
        let miss = await client.lookup(cues: cues(), durationSec: 1800, server: server)
        XCTAssertNil(miss)
        count = await transport.requests.count
        XCTAssertEqual(count, 2)

        clock.now = clock.now.addingTimeInterval(4 * 60)
        let cachedMiss = await client.lookup(cues: cues(), durationSec: 1800, server: server)
        XCTAssertNil(cachedMiss)
        count = await transport.requests.count
        XCTAssertEqual(count, 2)

        clock.now = clock.now.addingTimeInterval(61)
        let again = await client.lookup(cues: cues(), durationSec: 1800, server: server)
        XCTAssertNotNil(again)
        count = await transport.requests.count
        XCTAssertEqual(count, 3)
    }

    func testAFailedRequestIsNotKeptSoTheNextCallAsksAgain() async {
        let transport = ScriptedTransport([.failure, .reply(200, hit)])
        let client = CommunitySyncClient(transport: transport)
        let failed = await client.lookup(cues: cues(), durationSec: 1800, server: server)
        XCTAssertNil(failed)
        let retried = await client.lookup(cues: cues(), durationSec: 1800, server: server)
        XCTAssertNotNil(retried)
        let count = await transport.requests.count
        XCTAssertEqual(count, 2)
    }

    // MARK: Gates

    func testPrivateModeAndTheSettingMakeNoRequestAtAll() async {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = ScriptedTransport([.reply(200, hit), .reply(200, hit)])
        let client = CommunitySyncClient(transport: transport)

        defaults.set(true, forKey: CommunitySync.privateKey)
        let inPrivate = await CommunitySync.communityTiming(cues: cues(), durationSec: 1800, defaults: defaults, client: client)
        XCTAssertNil(inPrivate)
        let reported = await CommunitySync.reportAudioResult(cues: cues(), durationSec: 1800,
                                                             result: SubtitleSyncResult(offset: 1, ratio: 1, confidence: 0.9),
                                                             defaults: defaults, client: client)
        XCTAssertFalse(reported)

        defaults.set(false, forKey: CommunitySync.privateKey)
        defaults.set(false, forKey: CommunitySync.crowdKey)
        let switchedOff = await CommunitySync.communityTiming(cues: cues(), durationSec: 1800, defaults: defaults, client: client)
        XCTAssertNil(switchedOff)
        let count = await transport.requests.count
        XCTAssertEqual(count, 0)
    }

    func testDefaultsAreOnAndHarborsServer() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(CommunitySync.enabled(defaults))
        XCTAssertEqual(CommunitySync.server(defaults), "https://sync.harbor.site")
    }

    func testAnInvalidStoredServerGivesNoRequest() async {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ftp://sync.example.com", forKey: CommunitySync.serverKey)
        let transport = ScriptedTransport([.reply(200, hit)])
        let client = CommunitySyncClient(transport: transport)
        let timing = await CommunitySync.communityTiming(cues: cues(), durationSec: 1800, defaults: defaults, client: client)
        XCTAssertNil(timing)
        let count = await transport.requests.count
        XCTAssertEqual(count, 0)
    }

    // MARK: Report

    func testReportBodyFollowsDesktopLimits() throws {
        let hash = try XCTUnwrap(CommunitySyncRules.subTimelineHash(cues()))
        let body = try XCTUnwrap(CommunitySyncRules.reportBody(cues: cues(), durationSec: 1800,
                                                               result: SubtitleSyncResult(offset: 1.2344, ratio: 1, confidence: 0.9)))
        XCTAssertEqual(body["subTimelineHash"] as? String, hash)
        XCTAssertEqual(body["durationMs"] as? Int, 1_800_000)
        XCTAssertEqual(body["offsetMs"] as? Int, 1234)
        XCTAssertEqual(body["ratio"] as? Double, 1)
        XCTAssertEqual(body["confidence"] as? Double, 0.9)
        XCTAssertEqual(Set(body.keys), ["subTimelineHash", "durationMs", "offsetMs", "ratio", "confidence"])
    }

    func testReportBodyLimitsAreInclusiveAtTheEdges() {
        func body(duration: Double = 1800, offset: Double = 1, ratio: Double = 1, confidence: Double = 0.9) -> [String: Any]? {
            CommunitySyncRules.reportBody(cues: cues(), durationSec: duration,
                                          result: SubtitleSyncResult(offset: offset, ratio: ratio, confidence: confidence))
        }
        XCTAssertNil(body(duration: 59.999))
        XCTAssertNotNil(body(duration: 60))
        XCTAssertNil(body(confidence: 0.84))
        XCTAssertNotNil(body(confidence: 0.85))
        XCTAssertNil(body(offset: 60.001))
        XCTAssertNotNil(body(offset: 60))
        XCTAssertNil(body(ratio: 0.79))
        XCTAssertNotNil(body(ratio: 0.8))
        XCTAssertNil(body(ratio: 1.26))
        XCTAssertNotNil(body(ratio: 1.25))
        XCTAssertEqual(body(confidence: 1)?["confidence"] as? Double, 1)
    }

    func testReportNeedsEightCues() {
        let body = CommunitySyncRules.reportBody(cues: cues(7), durationSec: 1800,
                                                 result: SubtitleSyncResult(offset: 1, ratio: 1, confidence: 0.9))
        XCTAssertNil(body)
    }

    func testReportPostsToTheReportEndpointAndNeedsAcceptance() async {
        let transport = ScriptedTransport([.reply(200, #"{"accepted":true}"#), .reply(200, #"{"accepted":false}"#), .reply(500, "")])
        let client = CommunitySyncClient(transport: transport)
        let result = SubtitleSyncResult(offset: 1, ratio: 1, confidence: 0.9)
        let accepted = await client.report(cues: cues(), durationSec: 1800, result: result, server: server)
        XCTAssertTrue(accepted)
        let refused = await client.report(cues: cues(), durationSec: 1800, result: result, server: server)
        XCTAssertFalse(refused)
        let failed = await client.report(cues: cues(), durationSec: 1800, result: result, server: server)
        XCTAssertFalse(failed)
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://sync.example.com/api/v1/report")
    }

    // MARK: Server address and settings

    func testServerAddressValidation() {
        XCTAssertEqual(CommunitySyncRules.storedServer(""), "")
        XCTAssertEqual(CommunitySyncRules.storedServer("   "), "")
        XCTAssertEqual(CommunitySyncRules.storedServer("https://sync.example.com/"), "https://sync.example.com/")
        XCTAssertEqual(CommunitySyncRules.storedServer("http://localhost:8787"), "http://localhost:8787")
        XCTAssertNil(CommunitySyncRules.storedServer("ftp://sync.example.com"))
        XCTAssertNil(CommunitySyncRules.storedServer("https://"))
        XCTAssertNil(CommunitySyncRules.storedServer("sync.example.com"))
    }

    func testSettingsKeysAreInTheProfileStore() {
        let keys = ProfileSettingsStore.keys
        XCTAssertTrue(keys.isSuperset(of: ["subtitleAutoSync", "subtitleAutoSyncCrowd", "communitySyncUrl", "communitySyncOptOut"]))
    }
}
