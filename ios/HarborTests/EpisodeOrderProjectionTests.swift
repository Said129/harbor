import XCTest
@testable import Harbor

final class EpisodeOrderProjectionTests: XCTestCase {
    private func row(_ id: Int, _ season: Int, _ episode: Int, absolute: Int? = nil) throws -> TVDBOrderEpisode {
        var value: [String: JSONValue] = ["id": .integer(Int64(id)), "seasonNumber": .integer(Int64(season)), "number": .integer(Int64(episode))]
        if let absolute { value["absoluteNumber"] = .integer(Int64(absolute)) }
        return try XCTUnwrap(TVDBOrderEpisode(.object(value)))
    }
    private func order(_ kind: TVDBEpisodeOrderKind, _ canonical: [TVDBOrderEpisode], _ alternative: [TVDBOrderEpisode]? = nil) throws -> TVDBEpisodeOrder {
        try XCTUnwrap(TVDBEpisodeOrder.build(seriesID: 42, kind: kind, canonical: canonical, alternative: alternative ?? canonical, series: .null))
    }

    func testDVDPlayerSequenceCanIncludeSpecialsWithoutChangingStremioIdentityOrDefaultNavigation() throws {
        let source = [Episode(id: "show:1:1", season: 1, episode: 1), Episode(id: "show:1:2", season: 1, episode: 2), Episode(id: "show:0:1", season: 0, episode: 1)]
        let canonical = try [row(101, 1, 1), row(102, 1, 2), row(190, 0, 1)]
        let dvd = try [row(102, 1, 1), row(190, 1, 2), row(101, 1, 3)]
        let projected = try XCTUnwrap(EpisodeOrderProjection.build(order(.dvd, canonical, dvd), source: source, animeIdentity: false))
        XCTAssertEqual(projected.videos.map(\.id), source.map(\.id))
        XCTAssertEqual(projected.videos.map(\.watchedKey), ["1:1", "1:2", "0:1"])
        XCTAssertEqual(WatchedCodec.ordered(projected.videos).map(\.id), WatchedCodec.ordered(source).map(\.id))
        XCTAssertEqual(projected.sections.count, 1)
        XCTAssertEqual(projected.sections[0].episodes.map(\.id), ["show:1:2", "show:0:1", "show:1:1"])
        let playing = ResumeTarget(id: "show", season: 1, episode: 2, videoId: "show:1:2")
        XCTAssertNil(EpisodeSequence.adjacent(source, current: playing).next)
        XCTAssertEqual(EpisodeSequence.adjacent(projected.videos, current: playing, presentation: projected).next?.id, "show:0:1")
        let special = ResumeTarget(id: "show", season: 0, episode: 1, videoId: "show:0:1")
        let adjacent = EpisodeSequence.adjacent(projected.videos, current: special, presentation: projected)
        XCTAssertEqual(adjacent.previous?.id, "show:1:2"); XCTAssertEqual(adjacent.next?.id, "show:1:1")
        XCTAssertEqual(EpisodeSequence.startingEpisode(source, record: nil, watched: [], presentation: projected)?.id, "show:1:2")
        var different = source; different.append(Episode(id: "other:2:1", season: 2, episode: 1))
        XCTAssertFalse(projected.applies(to: different))
        XCTAssertEqual(EpisodeSequence.ordered(different, presentation: projected).map(\.id), WatchedCodec.ordered(different).map(\.id))
        let unknown = Episode(id: "unknown:1", episode: 1)
        let record = LibraryRecord(raw: .object(["_id": .string("show"), "type": .string("series"),
            "state": .object(["video_id": .string(unknown.id), "flaggedWatched": .integer(1)])]))
        XCTAssertEqual(EpisodeSequence.startingEpisode([unknown, source[0]], record: record, watched: [])?.id, unknown.id,
            "A missing provider season must retain the original resume behavior")
    }

    func testAbsoluteSuperNinetyNineCaptionNextAndSourceIDsStayAligned() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "dbs-source", withExtension: "json", subdirectory: "Fixtures"))
        let media = try XCTUnwrap(Media.parse(JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)), kind: "series"))
        let source = media.videos ?? [], regular = WatchedCodec.ordered(source.filter { ($0.season ?? 0) > 0 })
        let rows = try regular.enumerated().map { index, episode in try row(index + 1, episode.season ?? 1, episode.episode ?? 1, absolute: index + 1) }
        let projected = try XCTUnwrap(EpisodeOrderProjection.build(order(.absolute, rows), source: source, animeIdentity: false))
        let target = ResumeTarget(id: media.id, season: 5, episode: 23, videoId: "tt4644488:5:23")
        var visible = media; visible.videos = projected.videos
        XCTAssertEqual(EpisodePresentation.coordinates(in: visible, target: target)?.caption, "T1 · E99")
        let ninetyNine = try XCTUnwrap(EpisodePresentation.episode(in: visible, target: target))
        XCTAssertEqual(ninetyNine.watchedKey, "5:23")
        XCTAssertEqual(StreamRequestPolicy.ids(visible, videoID: ninetyNine.id, season: ninetyNine.season, episode: ninetyNine.episode).first, "tt4644488:5:23")
        XCTAssertEqual(EpisodeSequence.adjacent(visible.videos ?? [], current: target, presentation: projected).next?.id, "tt4644488:5:24")
        XCTAssertEqual(projected.videos.map(\.id), source.map(\.id))
        XCTAssertEqual(projected.videos.map(\.watchedKey), source.map(\.watchedKey))
        XCTAssertEqual(projected.sections.first?.episodes.count, 131)
        XCTAssertEqual(projected.sections.last?.id, "extras")
    }

    func testPartialAnimeCourNeverBorrowsFranchiseAbsoluteNumbersButVerifiedPairsRemainPlayable() throws {
        let rows = try (1...24).map { number in try row(number, number <= 12 ? 1 : 2, (number - 1) % 12 + 1, absolute: number) }
        let source = (1...12).map { (number: Int) in Episode(id: "kitsu:123:\(number)", season: 1, episode: number) }
        let provider = try order(.aired, rows)
        XCTAssertNil(EpisodeOrderProjection.build(provider, source: source, animeIdentity: true), "Local cour numbers cannot identify another cour's slots")
        let verified = source.map { episode in
            var value = episode; value.imdbSeason = 2; value.imdbEpisode = episode.episode; return value
        }
        let projected = try XCTUnwrap(EpisodeOrderProjection.build(provider, source: verified, animeIdentity: true))
        XCTAssertEqual(projected.sections.map(\.id), ["2"])
        XCTAssertEqual(projected.sections[0].episodes.map(\.id), source.map(\.id))
        XCTAssertEqual(projected.videos.map(\.watchedKey), source.map(\.watchedKey))
        XCTAssertEqual(projected.unmatchedProviderIDs, Array(1...12), "Unresolved franchise episodes are recorded, never fabricated or counted as full parity")
        let whole = (1...24).map { (number: Int) in Episode(id: "kitsu:321:\(number)", season: 1, episode: number) }
        let complete = try XCTUnwrap(EpisodeOrderProjection.build(provider, source: whole, animeIdentity: true))
        XCTAssertEqual(complete.sections.map(\.id), ["1", "2"])
        XCTAssertTrue(complete.unmatchedProviderIDs.isEmpty)
    }

    func testAmbiguousPairsAndUnmatchedSourceExtrasNeverDisappearOrStealAnotherEpisode() throws {
        let source = [Episode(id: "a", season: 1, episode: 1), Episode(id: "b", season: 1, episode: 1),
                      Episode(id: "c", season: 1, episode: 2), Episode(id: "special", season: 0, episode: 1)]
        let provider = try order(.aired, [row(1, 1, 1), row(2, 1, 2)])
        let projected = try XCTUnwrap(EpisodeOrderProjection.build(provider, source: source, animeIdentity: false))
        XCTAssertEqual(projected.sections[0].episodes.map(\.id), ["c"])
        XCTAssertEqual(Set(projected.sections.last?.episodes.map(\.id) ?? []), ["a", "b", "special"])
        XCTAssertEqual(projected.unmatchedProviderIDs, [1])
        XCTAssertEqual(projected.videos, source.map { episode in
            var value = episode
            if value.id == "c" { value.displaySeason = 1; value.displayEpisode = 2 }
            return value
        })
        let ids = EpisodeSequence.ordered(projected.videos, presentation: projected).map(\.id)
        XCTAssertEqual(Set(ids), Set(source.map(\.id))); XCTAssertEqual(ids.count, source.count)
    }
}
