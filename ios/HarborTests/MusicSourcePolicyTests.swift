import XCTest
@testable import Harbor

@MainActor final class MusicSourcePolicyTests: XCTestCase {
    func testAppleJavaScriptCoreMatchesFortyEightExecutedOriginalSourceIdentityQueueAndVersionStates() throws {
        let fixture = try reference()
        XCTAssertEqual(fixture["actual_original_functions_executed"], .bool(true))
        XCTAssertEqual(fixture["complete_original_headless_resolver_executed_with_owned_transport_and_player"], .bool(true))
        XCTAssertEqual(fixture["real_provider_or_audio_requests_performed"], .bool(false))
        XCTAssertEqual(fixture["original_modules"].objectValue.count, 4); XCTAssertEqual(fixture["cases"].array.count, 48)
        let policy = MusicSourcePolicy()
        for row in fixture["cases"].array {
            let request = try JSONDecoder().decode(MusicSourcePolicyRequest.self, from: JSONEncoder().encode(row["request"]))
            XCTAssertEqual(try policy.evaluate(request), row["expected"], request.operation)
            if request.operation == "choose" {
                XCTAssertEqual(row["original_queue_cancellations"].integer, 1)
                XCTAssertEqual(row["original_play_calls"].integer, row["expected"] == .null ? 0 : 1)
            }
        }
    }
    func testTypedNativeChoicePreservesRequestedCreditsAndSelectedAudioPropertiesAfterAnInvalidCall() throws {
        let fixture = try reference(), policy = MusicSourcePolicy()
        let row = try XCTUnwrap(fixture["cases"].array.first { $0["request"]["operation"].string == "adopt" })
        let request = try JSONDecoder().decode(MusicSourcePolicyRequest.self, from: JSONEncoder().encode(row["request"]))
        let requested = try XCTUnwrap(request.track); var selected = try XCTUnwrap(request.selected)
        selected.quality = .init(codec: "flac", lossless: true, sampleRateHz: 96000, bitDepth: 24, bitrateKbps: nil)
        selected.releaseDate = "2026-10-01"
        let adopted = try policy.adopt(selected, requested: requested)
        XCTAssertEqual(adopted.title, requested.title); XCTAssertEqual(adopted.artist, requested.artist)
        XCTAssertEqual(adopted.id, selected.id); XCTAssertEqual(adopted.durationSeconds, selected.durationSeconds)
        XCTAssertEqual(adopted.quality, selected.quality); XCTAssertEqual(adopted.releaseDate, selected.releaseDate)
        XCTAssertEqual(adopted.collectionOrigin?.id, requested.id)
        let source = MusicSourceCandidate(connectorId: "youtube", connectorName: "YouTube", health: .healthy, track: selected)
        let offline = MusicSourceCandidate(connectorId: "plex", connectorName: "Plex", health: .offline, track: selected)
        let choice = try XCTUnwrap(policy.choose(requested, candidates: [offline,source], preferred: "youtube"))
        XCTAssertEqual(choice.track.collectionOrigin?.id, requested.id); XCTAssertEqual(choice.queue, [choice.track])
        XCTAssertEqual(try policy.selectable([offline,source,source], current: requested), [source])
        XCTAssertEqual(try policy.replace([requested], at: 0, with: selected), [adopted])
        XCTAssertThrowsError(try policy.evaluate(.init(operation: "unavailable-native-operation")))
        XCTAssertEqual(try policy.adopt(selected, requested: requested), adopted)
        XCTAssertNil(try policy.choose(requested, candidates: [offline], preferred: "youtube"))
    }
    private func reference() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "music-source-policy-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
}
