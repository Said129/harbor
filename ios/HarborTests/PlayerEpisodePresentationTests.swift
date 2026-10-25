import XCTest
@testable import Harbor

final class PlayerEpisodePresentationTests: XCTestCase {
    private func row(_ id: Int, season: Int, episode: Int, absolute: Int) throws -> TVDBOrderEpisode {
        try XCTUnwrap(TVDBOrderEpisode(.object(["id": .integer(Int64(id)), "seasonNumber": .integer(Int64(season)),
            "number": .integer(Int64(episode)), "absoluteNumber": .integer(Int64(absolute))])))
    }
    private func projection(_ source: [Episode], rows: [TVDBOrderEpisode]) throws -> EpisodeOrderProjection {
        let order = try XCTUnwrap(TVDBEpisodeOrder.build(seriesID: 42, kind: .absolute, canonical: rows, alternative: rows, series: .null))
        return try XCTUnwrap(EpisodeOrderProjection.build(order, source: source, animeIdentity: false))
    }
    func testLateAbsoluteOrderUpdatesSuperNinetyNineWithoutReplacingTheRunningSessionMetadata() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dbs-source", withExtension: "json", subdirectory: "Fixtures"))
        let snapshot = try XCTUnwrap(Media.parse(JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)), kind: "series"))
        let source = snapshot.videos ?? []
        let rows = try WatchedCodec.ordered(source.filter { ($0.season ?? 0) > 0 }).enumerated().map { index, episode in
            try row(index + 1, season: episode.season ?? 1, episode: episode.episode ?? 1, absolute: index + 1)
        }
        let order = try projection(source, rows: rows)
        let current = ResumeTarget(id: snapshot.id, season: 5, episode: 23, videoId: "tt4644488:5:23")
        XCTAssertEqual(EpisodePresentation.coordinates(in: snapshot, target: current)?.caption, "T5 · E23")
        XCTAssertEqual(EpisodePresentation.coordinates(in: snapshot, target: current, presentation: order)?.caption, "T1 · E99")
        let next = try XCTUnwrap(EpisodeSequence.adjacent(order.videos, current: current, presentation: order).next)
        let nextTarget = ResumeTarget(id: snapshot.id, season: next.season, episode: next.episode, videoId: next.id)
        XCTAssertEqual(EpisodePresentation.coordinates(in: snapshot, target: nextTarget, presentation: order)?.caption, "T1 · E100")
        XCTAssertEqual(EpisodePresentation.episode(in: snapshot, target: current)?.watchedKey, "5:23")
        XCTAssertEqual(next.id, "tt4644488:5:24")
        XCTAssertEqual(snapshot.videos?.map(\.watchedKey), source.map(\.watchedKey))
    }
    func testFranchiseEntriesWithTheSameVideoIDCannotBorrowAnotherSourcesDisplayCoordinates() throws {
        var first = Episode(id: "shared-id", season: 1, episode: 1)
        first.sourceMetaID = "kitsu:first"; first.imdbSeason = 1; first.imdbEpisode = 1
        var second = first; second.sourceMetaID = "kitsu:second"; second.imdbSeason = 2; second.imdbEpisode = 1
        let order = try projection([first, second], rows: [row(1, season: 1, episode: 1, absolute: 1), row(2, season: 2, episode: 1, absolute: 2)])
        var media = Media(id: "kitsu:second", type: "anime", name: "Second entry"); media.videos = [second]
        let target = ResumeTarget(id: media.id, season: 1, episode: 1, videoId: "shared-id")
        XCTAssertEqual(EpisodePresentation.coordinates(in: media, target: target, presentation: order)?.caption, "T1 · E2")
        media.id = "kitsu:first"; media.videos = [first]
        XCTAssertEqual(EpisodePresentation.coordinates(in: media, target: ResumeTarget(id: media.id, season: 1, episode: 1, videoId: "shared-id"), presentation: order)?.caption, "T1 · E1")
    }
    func testAnUnrelatedProjectionAndMissingVideoKeepTheCanonicalFallback() throws {
        let episode = Episode(id: "other:5:23", season: 5, episode: 23)
        let order = try projection([episode], rows: [row(1, season: 5, episode: 23, absolute: 1)])
        var media = Media(id: "current", type: "series", name: "Current"); media.videos = [Episode(id: "current:5:23", season: 5, episode: 23)]
        let target = ResumeTarget(id: media.id, season: 5, episode: 23, videoId: "current:5:23")
        XCTAssertEqual(EpisodePresentation.coordinates(in: media, target: target, presentation: order)?.caption, "T5 · E23")
        XCTAssertEqual(EpisodePresentation.coordinates(in: media, target: ResumeTarget(id: media.id, season: 5, episode: 23), presentation: order)?.caption, "T5 · E23")
    }
}
