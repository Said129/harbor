import XCTest
@testable import Harbor

/// The debrid library in the stream pipeline: the title fields of a release name, the query for the title being
/// opened, the library streams a listing produces, and the flags those streams confirm.
final class F5DebridLibraryTests: XCTestCase {
    func testTitleFieldsOfAMovieName() {
        let title = DebridLibraryMerge.parseTitle("Inception.2010.1080p")
        XCTAssertEqual(title.title, "Inception")
        XCTAssertEqual(title.year, 2010)
        XCTAssertEqual(title.resolution, "1080p")
        XCTAssertNil(title.season)
        XCTAssertNil(title.episode)
    }

    func testTitleFieldsOfAnEpisodeName() {
        let title = DebridLibraryMerge.parseTitle("Show.S02E03.1080p.WEB")
        XCTAssertEqual(title.title, "Show")
        XCTAssertEqual(title.season, 2)
        XCTAssertEqual(title.episode, 3)
    }

    func testTitleFieldsOfACrossEpisodeName() {
        let title = DebridLibraryMerge.parseTitle("Show.1x04.720p")
        XCTAssertEqual(title.title, "Show")
        XCTAssertEqual(title.season, 1)
        XCTAssertEqual(title.episode, 4)
    }

    func testTitleFieldsOfASeasonPack() {
        let title = DebridLibraryMerge.parseTitle("Show.S02.1080p")
        XCTAssertEqual(title.title, "Show")
        XCTAssertEqual(title.season, 2)
        XCTAssertNil(title.episode)
    }

    func testTitleKeepsASpacedNameAndAYearThatStartsTheTitle() {
        XCTAssertEqual(DebridLibraryMerge.parseTitle("The_Show_Name.S01E01").title, "The Show Name")
        let numeric = DebridLibraryMerge.parseTitle("1917.2019.1080p")
        XCTAssertEqual(numeric.title, "1917")
        XCTAssertEqual(numeric.year, 2019)
    }

    func testTitleWithoutMarkersIsTheWholeName() {
        let title = DebridLibraryMerge.parseTitle("Show Complete")
        XCTAssertEqual(title.title, "Show Complete")
        XCTAssertNil(title.year)
        XCTAssertNil(title.season)
    }

    func testQueryIsASeriesWhenAnEpisodeIsSetOrTheTitleIsASeries() {
        let episode = DebridLibraryMerge.query(type: "anime", title: "Show", releaseInfo: nil, season: 2, episode: 3)
        XCTAssertEqual(episode.type, .series)
        XCTAssertEqual(episode.season, 2)
        XCTAssertEqual(episode.episode, 3)
        let series = DebridLibraryMerge.query(type: "series", title: "Show", releaseInfo: nil, season: nil, episode: nil)
        XCTAssertEqual(series.type, .series)
    }

    func testQueryIsAMovieForAnAnimeWithoutAnEpisode() {
        let movie = DebridLibraryMerge.query(type: "anime", title: "Film", releaseInfo: nil, season: nil, episode: nil)
        XCTAssertEqual(movie.type, .movie)
    }

    func testQueryYearIsTheFirstYearOfTheReleaseRange() {
        let query = DebridLibraryMerge.query(type: "movie", title: "Inception", releaseInfo: "2010\u{2013}2015", season: nil, episode: nil)
        XCTAssertEqual(query.year, 2010)
        let plain = DebridLibraryMerge.query(type: "movie", title: "Inception", releaseInfo: "2010", season: nil, episode: nil)
        XCTAssertEqual(plain.year, 2010)
        let missing = DebridLibraryMerge.query(type: "movie", title: "Inception", releaseInfo: nil, season: nil, episode: nil)
        XCTAssertNil(missing.year)
    }

    func testLibraryStreamsMatchOnlyTheListingsThatAnswered() async {
        let list: DebridLibraryMerge.Lister = { provider in
            if provider == .rd {
                return [DebridLibraryMerge.Item(provider: .rd, hash: "AAAA", name: "Inception.2010.1080p")]
            }
            return nil
        }
        let query = DebridLibraryMerge.Query(type: .movie, title: "Inception", year: 2010, season: nil, episode: nil)
        let streams = await DebridLibraryMerge.libraryStreams(providers: [.rd, .tb], query: query, list: list)
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams.first?["infoHash"], JSONValue.string("aaaa"))
        XCTAssertEqual(streams.first?["addonId"], JSONValue.string("rd-library"))
    }

    func testNoAnsweringListingGivesNoLibraryStreams() async {
        let list: DebridLibraryMerge.Lister = { _ in nil }
        let query = DebridLibraryMerge.Query(type: .movie, title: "Inception", year: 2010, season: nil, episode: nil)
        let streams = await DebridLibraryMerge.libraryStreams(providers: [.rd, .ad], query: query, list: list)
        XCTAssertTrue(streams.isEmpty)
    }

    func testLibraryStreamAndAddonStreamWithTheSameHashBecomeOneEntry() async {
        let list: DebridLibraryMerge.Lister = { provider in
            provider == .rd ? [DebridLibraryMerge.Item(provider: .rd, hash: "aaaa", name: "Inception.2010.1080p")] : nil
        }
        let query = DebridLibraryMerge.Query(type: .movie, title: "Inception", year: 2010, season: nil, episode: nil)
        let library = await DebridLibraryMerge.libraryStreams(providers: [.rd], query: query, list: list)
        let addon = JSONValue.object(["infoHash": .string("aaaa"), "addonId": .string("torrentio"), "addonName": .string("Torrentio"), "name": .string("Inception")])
        let merged = DebridLibraryMerge.mergeAndDedupe(library: library, addons: [addon])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?["addonId"], JSONValue.string("rd-library"))
        XCTAssertEqual(merged.first?["contributors"].array.count, 2)
    }

    func testVerificationMarksTheLibraryHashesOfEachProvider() {
        let streams: [JSONValue] = [
            .object(["infoHash": .string("ABCD"), "addonId": .string("rd-library")]),
            .object(["infoHash": .string("abcd"), "addonId": .string("rd-library")]),
            .object(["infoHash": .string("ef01"), "addonId": .string("ad-library")]),
            .object(["infoHash": .string("2345"), "addonId": .string("torrentio")]),
        ]
        let verification = DebridLibraryMerge.verification(of: streams)
        XCTAssertEqual(verification.library["rd"], ["abcd"])
        XCTAssertEqual(verification.library["ad"], ["ef01"])
        XCTAssertNil(verification.library["torrentio"])
        XCTAssertTrue(verification.cached.isEmpty)
    }
}
