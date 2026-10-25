import XCTest
@testable import Harbor

final class DesktopWatchedByTests: XCTestCase {
    func testNormalizationTimestampMergeAndRecencyCapMatchExecutedDesktopVectors() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "watched-by-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture["cases"].array.count, 5)
        for item in fixture["cases"].array {
            let merged = DesktopWatchedBy(item["local"]).merging(DesktopWatchedBy(item["incoming"]))
            XCTAssertEqual(merged, DesktopWatchedBy(item["expected"]))
            XCTAssertLessThanOrEqual(merged.entries.count, 300)
        }
    }
    func testRecordingTheSamePersonDoesNotAdvanceTheClockButAnotherWatcherDoes() throws {
        let once = try DesktopWatchedBy(.null).recording(mediaID: "film", profileID: "first", at: 100)
        XCTAssertEqual(try once.recording(mediaID: "film", profileID: "first", at: 200), once)
        let changed = try once.recording(mediaID: "film", profileID: "second", at: 300)
        XCTAssertEqual(changed.entries["film"]?.profile, "second"); XCTAssertEqual(changed.entries["film"]?.timestamp, 300)
        XCTAssertThrowsError(try once.recording(mediaID: "", profileID: "first", at: 100))
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "watched-by-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        var originalSequence = try DesktopWatchedBy(.null).recording(mediaID: "movie", profileID: "first", at: 1_000)
        originalSequence = try originalSequence.recording(mediaID: "movie", profileID: "first", at: 1_000)
        originalSequence = try originalSequence.recording(mediaID: "anime", profileID: "second", at: 1_000)
        XCTAssertEqual(originalSequence, DesktopWatchedBy(fixture["recorded"]))
    }
    func testOnlyAnotherKnownNormalProfileGetsABadgeAndAliasesCanRecoverTheWatcher() throws {
        let first = DeviceHouseholdProfile(id: "local-one", desktop: try DesktopHouseholdProfile(.object(["syncId": .string("remote-one"), "name": .string("One")])))
        let second = DeviceHouseholdProfile(id: "local-two", desktop: try DesktopHouseholdProfile(.object(["syncId": .string("remote-two"), "name": .string("Two")])))
        let value = DesktopWatchedBy(.object(["kitsu:one": .string(first.id), "unknown": .string("different-device-id")]))
        XCTAssertEqual(value.watcher(mediaID: "tt1", fallbackID: "kitsu:one", activeID: second.id, profiles: [first, second]), first)
        XCTAssertNil(value.watcher(mediaID: "kitsu:one", activeID: first.id, profiles: [first, second]))
        XCTAssertNil(value.watcher(mediaID: "unknown", activeID: second.id, profiles: [first, second]))
    }
}
