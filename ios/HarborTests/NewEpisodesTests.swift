import XCTest
@testable import Harbor

final class NewEpisodesTests: XCTestCase {
    private func json(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateParser.shared.date(text))
    }
    private func media(_ videos: [Episode]) throws -> Media {
        var media = try XCTUnwrap(Media.parse(json("dbs-source"), kind: "series"))
        media.videos = videos
        return media
    }
    private func episode(_ season: Int, _ number: Int, released: String?) -> Episode {
        Episode(id: "v:\(season):\(number)", season: season, episode: number, released: released)
    }
    private func record(id: String, type: String = "series", lastWatched: String?) -> LibraryRecord {
        var state: [String: JSONValue] = ["timeOffset": .integer(1_000)]
        if let lastWatched { state["lastWatched"] = .string(lastWatched) }
        return LibraryRecord(raw: .object([
            "_id": .string(id), "type": .string(type), "name": .string("Show"), "removed": .bool(false), "temp": .bool(false),
            "_mtime": .string("2026-10-01T00:00:00Z"), "state": .object(state)
        ]))
    }
    private func newEpisode(_ key: String, released: Date = Date(timeIntervalSince1970: 0)) -> NewEpisode {
        NewEpisode(key: key, seriesID: "tt1", seriesName: "Show", season: 1, episode: 1, title: "", still: nil, poster: nil, released: released)
    }
    /// 2026-11-07, the day the rules are checked against.
    private var now: Date { Date(timeIntervalSince1970: 1_794_052_800) }

    func testCandidatesAreSeriesWithImdbIDsUpToForty() {
        var records = (0..<45).map { record(id: "tt\($0)", lastWatched: nil) }
        records.append(record(id: "kitsu:1", lastWatched: nil))
        records.append(record(id: "tt999", type: "movie", lastWatched: nil))
        let picked = NewEpisodeRule.candidates(records)
        XCTAssertEqual(picked.count, 40)
        XCTAssertTrue(picked.allSatisfy { (record: LibraryRecord) -> Bool in record.id.hasPrefix("tt") && record.media?.type == "series" })
    }

    func testLastWatchedReadsTheWatchTimeThenTheModifiedTime() throws {
        let watched = try date("2026-10-20T00:00:00Z")
        XCTAssertEqual(NewEpisodeRule.lastWatched(record(id: "tt1", lastWatched: "2026-10-20T00:00:00Z")), watched)
        let modified = try date("2026-10-01T00:00:00Z")
        XCTAssertEqual(NewEpisodeRule.lastWatched(record(id: "tt1", lastWatched: nil)), modified)
    }

    func testNewEpisodesAreReleasedAfterTheLastWatchAndNotInTheFuture() throws {
        let lastWatched = try date("2026-10-20T00:00:00Z")
        let videos = [
            episode(5, 1, released: "2026-11-01T00:00:00Z"),
            episode(5, 2, released: "2026-10-10T00:00:00Z"),
            episode(5, 3, released: "2026-11-20T00:00:00Z"),
            episode(0, 0, released: "2026-11-02T00:00:00Z"),
            episode(5, 4, released: nil),
            episode(5, 5, released: "2026-09-01T00:00:00Z")
        ]
        let found = try NewEpisodeRule.episodes(in: media(videos), seriesID: "tt1", seriesName: "Show", poster: nil, lastWatched: lastWatched, now: now)
        XCTAssertEqual(found.map(\.key), ["tt1:5:1"])
        XCTAssertEqual(found.first?.seriesName, "Show")
    }

    func testEpisodesOlderThanFortyFiveDaysAreNotNew() throws {
        let videos = [episode(2, 1, released: "2026-09-01T00:00:00Z"), episode(2, 2, released: "2026-10-10T00:00:00Z")]
        let found = try NewEpisodeRule.episodes(in: media(videos), seriesID: "tt1", seriesName: "Show", poster: nil, lastWatched: date("2026-08-01T00:00:00Z"), now: now)
        XCTAssertEqual(found.map(\.key), ["tt1:2:2"])
    }

    func testMergedKeepsNewestSixtyWithoutDuplicates() throws {
        let base = try date("2026-11-01T00:00:00Z")
        let list = (1...70).map { (number: Int) -> NewEpisode in
            NewEpisode(key: "tt1:1:\(number)", seriesID: "tt1", seriesName: "Show", season: 1, episode: number, title: "", still: nil, poster: nil,
                released: base.addingTimeInterval(TimeInterval(number) * 60))
        }
        let merged = NewEpisodeRule.merged([list, list])
        XCTAssertEqual(merged.count, 60)
        XCTAssertEqual(merged.first?.episode, 70)
        XCTAssertEqual(Set(merged.map(\.key)).count, 60)
    }

    func testDismissedEpisodesAreHiddenAndStorageKeepsTheNewest600() {
        let found = [newEpisode("a"), newEpisode("b")]
        XCTAssertEqual(NewEpisodeRule.visible(found, dismissed: ["a"]).map(\.key), ["b"])
        XCTAssertEqual(NewEpisodeDismissals.adding(["c", "a"], to: ["a", "b"]), ["a", "b", "c"])
        let stored = NewEpisodeDismissals.adding((0..<650).map { "k\($0)" }, to: [])
        XCTAssertEqual(stored.count, 600)
        XCTAssertEqual(stored.first, "k50")
        XCTAssertEqual(stored.last, "k649")
    }
}
