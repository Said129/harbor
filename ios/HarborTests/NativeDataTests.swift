import XCTest
@testable import Harbor

final class NativeDataTests: XCTestCase {
    func testCloudResumeMatchesTheEpisodeAndRecognizesCompletedMovies() throws {
        let raw: JSONValue = .object(["_id": .string("show"), "type": .string("series"), "name": .string("Show"), "_mtime": .string("2026-10-05T18:00:00.123Z"), "state": .object(["video_id": .string("show:0:1"), "timeOffset": .integer(120_000), "duration": .integer(3_600_000)])])
        let record = LibraryRecord(raw: raw)
        let matching = record.resume(for: ResumeTarget(id: "show", season: 0, episode: 1, videoId: "show:0:1"))
        XCTAssertEqual(matching?.entry.ms, 120_000)
        XCTAssertEqual(matching?.durationMs, 3_600_000)
        XCTAssertNil(record.resume(for: ResumeTarget(id: "show", season: 1, episode: 1, videoId: "show:1:1")))
        XCTAssertNil(record.resume(for: ResumeTarget(id: "other", videoId: "show:0:1")))
        let movie = LibraryRecord(raw: .object(["_id": .string("movie"), "type": .string("movie"), "name": .string("Movie"), "_mtime": .string("2026-10-05T18:00:00Z"), "state": .object(["timeOffset": .integer(120_000), "flaggedWatched": .integer(1)])]))
        XCTAssertEqual(movie.resume(for: ResumeTarget(id: "movie"))?.entry.ms, 0)
    }
    func testDesktopWatchedBitfieldUsesCanonicalEpisodeOrderAndAnchor() throws {
        let episodes = [Episode(id: "show:1:3", season: 1, episode: 3), Episode(id: "show:1:1", season: 1, episode: 1), Episode(id: "show:1:2", season: 1, episode: 2)]
        // Independent RFC1950 fixture: zlib-compressed byte 0b00000101.
        let field = "show:1:3:3:eJxjBQAABgAG"
        XCTAssertEqual(try WatchedCodec.decode(field, videos: episodes), ["1:1", "1:3"])
        XCTAssertEqual(try WatchedCodec.encode(["1:1", "1:3"], videos: episodes), field)
        let expanded = episodes + [Episode(id: "show:0:1", season: 0, episode: 1)]
        XCTAssertEqual(try WatchedCodec.decode(field, videos: expanded), ["1:1", "1:3"])
        XCTAssertThrowsError(try WatchedCodec.decode("show:1:3:3:broken", videos: episodes))
    }
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
