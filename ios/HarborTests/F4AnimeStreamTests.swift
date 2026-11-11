import XCTest
@testable import Harbor

@MainActor final class F4AnimeStreamTests: XCTestCase {
    func testAbsoluteEpisodeComesOnlyFromKitsuAndMalScopedIDs() {
        XCTAssertEqual(AnimeStreamEnrichment.absoluteEpisode("kitsu:1234:12"), 12)
        XCTAssertEqual(AnimeStreamEnrichment.absoluteEpisode("mal:5:007"), 7)
        XCTAssertNil(AnimeStreamEnrichment.absoluteEpisode("kitsu:1234"))
        XCTAssertNil(AnimeStreamEnrichment.absoluteEpisode("anilist:1234:12"))
        XCTAssertNil(AnimeStreamEnrichment.absoluteEpisode("tt0137523:1:2"))
        XCTAssertNil(AnimeStreamEnrichment.absoluteEpisode("kitsu:12a:3"))
    }

    func testFilenameFieldsCarryTheRecognisedValuesOnly() {
        let fields = AnimeStreamEnrichment.parse("[SubsPlease] Show Name - 07 (1080p) [ABCD1234].mkv")
        let json = AnimeStreamEnrichment.fieldsJSON(fields)
        XCTAssertEqual(json["episodeNumber"].integer, 7)
        XCTAssertEqual(json["releaseGroup"].string, "SubsPlease")
        XCTAssertEqual(json["resolution"].string, "1080p")
        XCTAssertEqual(json["fileChecksum"].string, "ABCD1234")
        XCTAssertEqual(json["isBatch"], .bool(false))
        XCTAssertEqual(json["season"], .null)
    }

    func testWithFieldsAddsTheKeyOnlyWhenThereIsAFilename() {
        let stream: JSONValue = .object(["addonId": .string("a"), "title": .string("[Group] Show - 03 [720p].mkv")])
        let enriched = AnimeStreamEnrichment.withFields(stream)
        XCTAssertEqual(enriched[AnimeStreamEnrichment.fieldsKey]["episodeNumber"].integer, 3)
        let empty: JSONValue = .object(["addonId": .string("a")])
        XCTAssertEqual(AnimeStreamEnrichment.withFields(empty), empty)
    }
}
