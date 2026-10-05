import XCTest
@testable import Harbor

final class NativeDataTests: XCTestCase {
    func testOptionalAddonFieldsDoNotDiscardTheCatalog() throws {
        let row: JSONValue = .object(["id": .string("tt0816692"), "type": .null, "name": .string("Interstellar"), "imdbRating": .number(8.7), "genres": .null, "videos": .array([.object(["id": .string("episode:1"), "season": .null, "episode": .integer(1), "name": .null])])])
        let media = try XCTUnwrap(Media.parse(row, kind: "movie"))
        XCTAssertEqual(media.type, "movie")
        XCTAssertEqual(media.imdbRating, "8.7")
        XCTAssertEqual(media.videos?.first?.id, "episode:1")
        XCTAssertNil(Media.parse(.object(["id": .null, "name": .string("Invalid")]), kind: "movie"))
    }
    @MainActor func testOldSavedOptionsSurviveAddingAspectControls() throws {
        let name = "harbor-migration-\(UUID().uuidString)"
        let storage = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { storage.removePersistentDomain(forName: name) }
        storage.set(try JSONSerialization.data(withJSONObject: ["speed": 1.5, "subtitleSize": 48, "fit": "classic"]), forKey: "iphone.player-options.v1")
        let preferences = PlaybackPreferences(storage: storage)
        XCTAssertEqual(preferences.options.speed, 1.5)
        XCTAssertEqual(preferences.options.subtitleSize, 48)
        XCTAssertEqual(preferences.options.fit, .classic)
        XCTAssertEqual(preferences.options.zoom, 0)
    }
}
