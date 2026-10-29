import XCTest
@testable import Harbor

@MainActor final class MusicQueueOrderTests: XCTestCase {
    func testSixHundredTenExecutedDesktopQueueStatesPreserveShuffleHistoryPriorityAndSourceIdentity() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "music-queue-order-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(fixture["actual_complete_original_queue_class_executed"], .bool(true))
        XCTAssertEqual(fixture["cases"].array.count, 10)
        var compared = 0
        for scenario in fixture["cases"].array {
            let controller = MusicQueueOrder()
            for step in scenario["steps"].array {
                let request = try JSONDecoder().decode(MusicQueueOrderRequest.self, from: JSONEncoder().encode(step["input"]))
                let result = try controller.evaluate(request)
                switch request.operation {
                case "key":
                    XCTAssertEqual(result, step["expected"])
                    XCTAssertEqual(MusicQueueOrder.key(try XCTUnwrap(request.track)), step["expected"].string)
                case "reset": XCTAssertEqual(result, .bool(true))
                case "upcoming":
                    XCTAssertEqual(try decoded([MusicTrack].self, result), try decoded([MusicTrack].self, step["expected"]), scenario["name"].string ?? "")
                default:
                    XCTAssertEqual(try decoded(MusicTrack?.self, result), try decoded(MusicTrack?.self, step["expected"]), scenario["name"].string ?? "")
                }
                compared += 1
            }
        }
        XCTAssertEqual(compared, 610)
    }
    func testTypedQueueInterfaceRetainsPreviewUntilAdvanceAndRecoversAfterRejectedInput() throws {
        let controller = MusicQueueOrder()
        let tracks = (0..<5).map { index in MusicTrack(id: "owned-\(index)", connectorId: "subsonic", sourceId: String(index), playbackUrl: nil, title: "Owned", artist: "Artist", album: nil, artwork: "", durationSeconds: 8, durationLabel: "0:08") }
        let upcoming = try controller.upcoming(tracks, index: 0, shuffle: true, repeatMode: .off)
        let repeated = try controller.upcoming(tracks, index: 0, shuffle: true, repeatMode: .off)
        XCTAssertEqual(upcoming, repeated)
        let next = try XCTUnwrap(controller.next(tracks, index: 0, shuffle: true, repeatMode: .off, automatic: false, priority: nil))
        XCTAssertEqual(next, upcoming.first)
        let previous = try controller.previous(tracks, index: try XCTUnwrap(tracks.firstIndex(of: next)), shuffle: true)
        XCTAssertEqual(previous, tracks[0])
        XCTAssertThrowsError(try controller.evaluate(.init(operation: "unknown")))
        XCTAssertThrowsError(try controller.evaluate(.init(operation: "next", queue: Array(repeating: tracks[0], count: 501))))
        try controller.reset()
        XCTAssertEqual(try controller.next(tracks, index: 0, shuffle: false, repeatMode: .one, automatic: true, priority: nil), tracks[0])
        XCTAssertEqual(try controller.next(tracks, index: 0, shuffle: false, repeatMode: .one, automatic: false, priority: nil), tracks[1])
    }
    private func decoded<T: Decodable>(_ type: T.Type, _ value: JSONValue) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(value)) }
}
