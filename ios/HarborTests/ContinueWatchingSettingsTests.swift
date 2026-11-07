import XCTest
@testable import Harbor

final class ContinueWatchingSettingsTests: XCTestCase {
    private func json(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func superMedia() throws -> Media {
        var source = try XCTUnwrap(Media.parse(json("dbs-source"), kind: "series"))
        let canonical = try XCTUnwrap(Media.parse(json("dbs-canonical"), kind: "series"))
        source.videos = AnimeEpisodeService.applying(try json("dbs-mapping"), canonical: canonical.videos ?? [], to: source.videos ?? [], animeIdentity: false)
        return source
    }
    private func record(offset: Int64 = 323_000) -> LibraryRecord {
        LibraryRecord(raw: .object([
            "_id": .string("tt4644488"), "type": .string("series"), "name": .string("Dragon Ball Super"),
            "removed": .bool(false), "temp": .bool(false), "_mtime": .string("2026-10-17T10:00:00Z"),
            "state": .object(["season": .integer(5), "episode": .integer(23), "video_id": .string("tt4644488:5:23"), "timeOffset": .integer(offset), "duration": .integer(1_400_000)])
        ]))
    }

    func testAdvanceRuleMovesToNextEpisodeOnlyWhenEnabled() {
        XCTAssertTrue(ContinueWatchingAdvance.advances(enabled: true, selectedSeason: 5, selectedEpisode: 24, currentSeason: 5, currentEpisode: 23))
        XCTAssertFalse(ContinueWatchingAdvance.advances(enabled: false, selectedSeason: 5, selectedEpisode: 24, currentSeason: 5, currentEpisode: 23))
    }

    func testAdvanceRuleStaysPutWhenEpisodeMatchesOrCoordinatesAreMissing() {
        XCTAssertFalse(ContinueWatchingAdvance.advances(enabled: true, selectedSeason: 5, selectedEpisode: 23, currentSeason: 5, currentEpisode: 23))
        XCTAssertFalse(ContinueWatchingAdvance.advances(enabled: true, selectedSeason: nil, selectedEpisode: nil, currentSeason: 5, currentEpisode: 23))
        XCTAssertFalse(ContinueWatchingAdvance.advances(enabled: true, selectedSeason: 5, selectedEpisode: 24, currentSeason: nil, currentEpisode: nil))
    }

    func testEnabledCardStillAdvancesFromFinishedEpisode() throws {
        let media = try superMedia()
        let finished = record(offset: 1_390_000)
        let presentation = ContinueWatchingPresentation(record: finished, media: media, watched: [])
        XCTAssertTrue(presentation.upNext)
        XCTAssertEqual(presentation.episode?.id, "tt4644488:5:24")
    }

    func testDisabledCardKeepsFinishedEpisodeAndItsProgress() throws {
        let media = try superMedia()
        let finished = record(offset: 1_390_000)
        let presentation = ContinueWatchingPresentation(record: finished, media: media, watched: [], advanceNext: false)
        XCTAssertFalse(presentation.upNext)
        XCTAssertEqual(presentation.progress, finished.progress)
        XCTAssertEqual(presentation.episode?.id, "tt4644488:5:23")
    }
}
