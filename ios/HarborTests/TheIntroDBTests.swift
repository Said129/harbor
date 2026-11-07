import XCTest
@testable import Harbor

/// TheIntroDB against Desktop 0.9.132 `lib/skip-intro/theintrodb.ts`: the query rules, the key sent as `X-API-Key`,
/// the answer cache, the 404 miss and the ten-minute failure cooldown. Every reply is scripted; nothing touches the network.
final class TheIntroDBTests: XCTestCase {
    /// Replies in order. Each call is recorded with the URL and the key it was sent with.
    actor ScriptedTransport: TheIntroDBTransport {
        enum Reply: Sendable { case json(JSONValue), failure(String) }
        private var replies: [Reply]
        private(set) var calls: [(url: String, key: String)] = []
        init(_ replies: [Reply]) { self.replies = replies }
        func json(_ url: URL, apiKey: String) async throws -> JSONValue {
            calls.append((url.absoluteString, apiKey))
            guard !replies.isEmpty else { throw HarborError(code: "network") }
            switch replies.removeFirst() {
            case .json(let value): return value
            case .failure(let code): throw HarborError(code: code)
            }
        }
    }

    /// A clock the test moves by hand.
    final class FakeClock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private var introAndCredits: String {
        #"{"intro":[{"start_ms":10000,"end_ms":100000}],"credits":[{"start_ms":1380000,"end_ms":null}]}"#
    }

    func testQueryUsesTheIMDbOrTMDBIdAndTheEpisode() {
        XCTAssertEqual(TheIntroDBRules.query(metaID: "tt0903747", season: 2, episode: 5), "imdb_id=tt0903747&season=2&episode=5")
        XCTAssertEqual(TheIntroDBRules.query(metaID: "tmdb:tv:1396", season: nil, episode: nil), "tmdb_id=1396")
        XCTAssertEqual(TheIntroDBRules.query(metaID: "tmdb:movie:603", season: nil, episode: nil), "tmdb_id=603")
        XCTAssertNil(TheIntroDBRules.query(metaID: "kitsu:9962", season: 1, episode: 7))
        XCTAssertNil(TheIntroDBRules.query(metaID: "tmdb:tv:0", season: nil, episode: nil))
    }

    func testParsedSpansBecomeIntroAndOutroSegmentsFromTheSameSource() throws {
        let segments = SkipIntroService.parseIntroDB(try parse(introAndCredits), duration: 1420)
        XCTAssertEqual(segments.map(\.kind), [.intro, .outro])
        XCTAssertEqual(segments.map(\.source), ["introdb", "introdb"])
        XCTAssertEqual(segments.last?.end ?? 0, 1420, accuracy: 0.001)
    }

    func testTheKeyRidesOnTheRequestAndAnAnswerIsReusedForTheSameKey() async throws {
        let transport = ScriptedTransport([.json(try parse(introAndCredits))])
        let client = TheIntroDBClient(transport: transport)
        let first = await client.segments(metaID: "tt1", season: 1, episode: 2, duration: 1420, apiKey: "abc")
        let second = await client.segments(metaID: "tt1", season: 1, episode: 2, duration: 1420, apiKey: "abc")
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(second, first)
        let calls = await transport.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.url, "https://api.theintrodb.org/v2/media?imdb_id=tt1&season=1&episode=2")
        XCTAssertEqual(calls.first?.key, "abc")
    }

    func testANewKeyForgetsTheAnswerGivenForTheOldOne() async throws {
        let transport = ScriptedTransport([.json(try parse(introAndCredits)), .json(try parse(introAndCredits))])
        let client = TheIntroDBClient(transport: transport)
        _ = await client.segments(metaID: "tt1", season: nil, episode: nil, duration: 1420, apiKey: "abc")
        _ = await client.segments(metaID: "tt1", season: nil, episode: nil, duration: 1420, apiKey: "xyz")
        let calls = await transport.calls
        XCTAssertEqual(calls.map { $0.key }, ["abc", "xyz"])
    }

    func testANotFoundAnswerIsKeptAsAMissAndNotAskedAgain() async {
        let transport = ScriptedTransport([.failure("http-404")])
        let client = TheIntroDBClient(transport: transport)
        let none = await client.segments(metaID: "tt2", season: nil, episode: nil, duration: 1420, apiKey: "")
        let again = await client.segments(metaID: "tt2", season: nil, episode: nil, duration: 1420, apiKey: "")
        XCTAssertEqual(none, [])
        XCTAssertEqual(again, [])
        let count = await transport.calls.count
        XCTAssertEqual(count, 1)
    }

    func testAServerFailureStopsEveryRequestForTenMinutes() async throws {
        let clock = FakeClock()
        let transport = ScriptedTransport([.failure("http-500"), .json(try parse(introAndCredits))])
        let client = TheIntroDBClient(transport: transport, clock: { clock.now })
        let failed = await client.segments(metaID: "tt3", season: nil, episode: nil, duration: 1420, apiKey: "")
        XCTAssertEqual(failed, [])
        let skipped = await client.segments(metaID: "tt4", season: nil, episode: nil, duration: 1420, apiKey: "")
        XCTAssertEqual(skipped, [])
        var count = await transport.calls.count
        XCTAssertEqual(count, 1)

        clock.now = clock.now.addingTimeInterval(9 * 60)
        _ = await client.segments(metaID: "tt4", season: nil, episode: nil, duration: 1420, apiKey: "")
        count = await transport.calls.count
        XCTAssertEqual(count, 1)

        clock.now = clock.now.addingTimeInterval(61)
        let recovered = await client.segments(metaID: "tt4", season: nil, episode: nil, duration: 1420, apiKey: "")
        count = await transport.calls.count
        XCTAssertEqual(count, 2)
        XCTAssertEqual(recovered.map(\.kind), [.intro, .outro])
    }

    func testANetworkErrorIsNotKeptSoTheNextCallAsksAgain() async throws {
        let transport = ScriptedTransport([.failure("network"), .json(try parse(introAndCredits))])
        let client = TheIntroDBClient(transport: transport)
        let first = await client.segments(metaID: "tt5", season: nil, episode: nil, duration: 1420, apiKey: "")
        XCTAssertEqual(first, [])
        let second = await client.segments(metaID: "tt5", season: nil, episode: nil, duration: 1420, apiKey: "")
        XCTAssertEqual(second.count, 2)
        let count = await transport.calls.count
        XCTAssertEqual(count, 2)
    }

    func testAnIdThatIsNeitherTMDBNorIMDbAsksNothing() async {
        let transport = ScriptedTransport([])
        let client = TheIntroDBClient(transport: transport)
        let segments = await client.segments(metaID: "kitsu:9962", season: 1, episode: 7, duration: 1420, apiKey: "abc")
        XCTAssertEqual(segments, [])
        let count = await transport.calls.count
        XCTAssertEqual(count, 0)
    }
}
