import XCTest
@testable import Harbor

/// Desktop's filename rules (`src-tauri/src/local_lib.rs`, `src/lib/local-library.ts`, `src/lib/episode-span.ts`) and the local library store.
@MainActor final class LocalLibraryTests: XCTestCase {
    private func record(_ name: String, size: Int64? = nil, added: TimeInterval = 0) -> LocalLibraryRecord {
        LocalLibraryRecord(id: name, filename: name, bookmark: Data(), size: size, addedAt: Date(timeIntervalSince1970: added), folderID: nil, folderName: nil, relativePath: name)
    }

    private func titles(_ groups: [LocalLibraryGroup]) -> [String] {
        groups.map { $0.title }
    }

    // MARK: - Movie names

    func testMovieNameKeepsTitleYearAndResolution() {
        let parsed = LocalFilenameParser.parse("The.Matrix.1999.1080p.BluRay.x264.mkv")
        XCTAssertEqual(parsed.title, "The Matrix")
        XCTAssertEqual(parsed.year, 1999)
        XCTAssertEqual(parsed.resolution, "1080p")
        XCTAssertFalse(parsed.isShow)
        XCTAssertNil(parsed.season)
    }

    func testReleaseNoiseAfterTheYearIsDropped() {
        let parsed = LocalFilenameParser.parse("Inception.2010.2160p.UHD.BluRay.REMUX.HDR.DV.TrueHD.Atmos.mkv")
        XCTAssertEqual(parsed.title, "Inception")
        XCTAssertEqual(parsed.year, 2010)
        XCTAssertEqual(parsed.resolution, "2160p")
    }

    func testDotInsideTheTitleDoesNotEndIt() {
        let parsed = LocalFilenameParser.parse("Dune.Part.Two.2024.1080p.WEBRip.x265-GROUP.mkv")
        XCTAssertEqual(parsed.title, "Dune Part Two")
        XCTAssertEqual(parsed.year, 2024)
    }

    func testYearFromAFourDigitTitleIsTheYearNotTheTitle() {
        let parsed = LocalFilenameParser.parse("Blade.Runner.2049.mkv")
        XCTAssertEqual(parsed.title, "Blade Runner")
        XCTAssertEqual(parsed.year, 2049)
        XCTAssertFalse(parsed.isShow)
    }

    func testBracketedYearAndResolution() {
        let parsed = LocalFilenameParser.parse("Show Name (2019) [1080p].mkv")
        XCTAssertEqual(parsed.title, "Show Name")
        XCTAssertEqual(parsed.year, 2019)
        XCTAssertEqual(parsed.resolution, "1080p")
    }

    func testUnderscoresBecomeSpaces() {
        let parsed = LocalFilenameParser.parse("Some_Film_Name.mkv")
        XCTAssertEqual(parsed.title, "Some Film Name")
        XCTAssertNil(parsed.year)
    }

    func testSinisterIsNotAnEpisodeMarker() {
        let parsed = LocalFilenameParser.parse("Sinister.2012.mkv")
        XCTAssertEqual(parsed.title, "Sinister")
        XCTAssertEqual(parsed.year, 2012)
        XCTAssertFalse(parsed.isShow)
    }

    func testExtensionIsMatchedWithoutCase() {
        let parsed = LocalFilenameParser.parse("FILM.MKV")
        XCTAssertEqual(parsed.title, "FILM")
        XCTAssertFalse(parsed.isShow)
        XCTAssertEqual(LocalFilenameParser.stem("FILM.MKV"), "FILM")
    }

    func testNonVideoNameIsParsedWhole() {
        XCTAssertEqual(LocalFilenameParser.stem("notes.srt"), "notes.srt")
    }

    func testVideoExtensionsMatchDesktop() {
        XCTAssertTrue(LocalFilenameParser.isVideo("clip.M2TS"))
        XCTAssertTrue(LocalFilenameParser.isVideo("a.ogv"))
        XCTAssertFalse(LocalFilenameParser.isVideo("subs.srt"))
        XCTAssertFalse(LocalFilenameParser.isVideo("notes"))
        XCTAssertFalse(LocalFilenameParser.isVideo("cover.jpg"))
    }

    // MARK: - Episode names

    func testSeasonAndEpisodeWithWebRelease() {
        let parsed = LocalFilenameParser.parse("Breaking.Bad.S01E02.720p.WEB-DL.mkv")
        XCTAssertTrue(parsed.isShow)
        XCTAssertEqual(parsed.title, "Breaking Bad")
        XCTAssertEqual(parsed.season, 1)
        XCTAssertEqual(parsed.episode, 2)
        XCTAssertEqual(parsed.episodeEnd, 2)
        XCTAssertEqual(parsed.resolution, "720p")
        XCTAssertEqual(parsed.episodeLabel, "S01E02")
    }

    func testTwoEpisodesInOneFileAreARange() {
        let parsed = LocalFilenameParser.parse("Show.Name.S02E05E06.mkv")
        XCTAssertEqual(parsed.title, "Show Name")
        XCTAssertEqual(parsed.season, 2)
        XCTAssertEqual(parsed.episode, 5)
        XCTAssertEqual(parsed.episodeEnd, 6)
        XCTAssertEqual(parsed.episodeLabel, "S02E05\u{2013}E06")
    }

    func testXNotationIsAnEpisode() {
        let parsed = LocalFilenameParser.parse("Show.Name.3x04.avi")
        XCTAssertEqual(parsed.title, "Show Name")
        XCTAssertEqual(parsed.season, 3)
        XCTAssertEqual(parsed.episode, 4)
        XCTAssertTrue(parsed.isShow)
    }

    func testSeasonEpisodeWordsAreAnEpisode() {
        let parsed = LocalFilenameParser.parse("Show.Season.2.Episode.5.mkv")
        XCTAssertEqual(parsed.title, "Show")
        XCTAssertEqual(parsed.season, 2)
        XCTAssertEqual(parsed.episode, 5)
    }

    func testSpecialsAreSeasonZero() {
        let parsed = LocalFilenameParser.parse("Show.S01.Extras.mkv")
        XCTAssertTrue(parsed.isShow)
        XCTAssertEqual(parsed.title, "Show")
        XCTAssertEqual(parsed.season, 0)
        XCTAssertEqual(parsed.episode, 1)
    }

    func testEpisodeSpanOnlyForSameSeasonRanges() {
        XCTAssertEqual(LocalFilenameParser.episodeSpan("Show.S01E01-E02"), LocalEpisodeSpan(season: 1, episode: 1, episodeEnd: 2))
        XCTAssertNil(LocalFilenameParser.episodeSpan("Show.S01E01-E03"))
        XCTAssertNil(LocalFilenameParser.episodeSpan("Show.S01E09-S02E01"))
    }

    func testUnrelatedRangeFallsBackToTheSingleEpisode() {
        let parsed = LocalFilenameParser.parse("Show.S01E01-E03.mkv")
        XCTAssertNil(LocalFilenameParser.episodeSpan("Show.S01E01-E03"))
        XCTAssertEqual(parsed.season, 1)
        XCTAssertEqual(parsed.episode, 1)
        XCTAssertEqual(parsed.episodeEnd, 1)
    }

    func testBareNumbersAreNotEpisodes() {
        XCTAssertNil(LocalFilenameParser.episodeSpan("Blade Runner 2049"))
        XCTAssertNil(LocalFilenameParser.episodeSpan("Apollo 13"))
    }

    // MARK: - Normalising and grouping

    func testNormalisedTitlesIgnorePunctuationCaseAndAccents() {
        XCTAssertEqual(LocalLibraryGrouping.normalized("Spider-Man"), "spiderman")
        XCTAssertEqual(LocalLibraryGrouping.normalized("Amélie"), "amelie")
        XCTAssertEqual(LocalLibraryGrouping.normalized("spider man"), "spiderman")
    }

    func testTwoVersionsOfOneMovieCollapseAndTheBestComesFirst() {
        let groups = LocalLibraryGrouping.groups([
            record("The.Matrix.1999.720p.mkv"),
            record("The.Matrix.1999.1080p.mkv"),
        ])
        XCTAssertEqual(groups.count, 1)
        guard case .movie(let movie) = groups[0] else { return XCTFail("expected a movie") }
        XCTAssertEqual(movie.versions.count, 2)
        XCTAssertEqual(movie.versions.first?.filename, "The.Matrix.1999.1080p.mkv")
        XCTAssertEqual(movie.year, 1999)
    }

    func testSameTitleInAnotherYearIsAnotherMovie() {
        let groups = LocalLibraryGrouping.groups([record("Dune.2021.mkv"), record("Dune.1984.mkv")])
        XCTAssertEqual(groups.count, 2)
    }

    func testEpisodesGroupIntoSeasonsInAscendingOrder() {
        let groups = LocalLibraryGrouping.groups([
            record("Breaking.Bad.S02E01.mkv"),
            record("Breaking.Bad.S01E02.mkv"),
            record("Breaking.Bad.S01E01.mkv"),
        ])
        XCTAssertEqual(groups.count, 1)
        guard case .show(let show) = groups[0] else { return XCTFail("expected a show") }
        XCTAssertEqual(show.title, "Breaking Bad")
        XCTAssertEqual(show.seasons.map { $0.number }, [1, 2])
        XCTAssertEqual(show.seasons[0].episodes.map { $0.parsed.episode ?? -1 }, [1, 2])
        XCTAssertEqual(show.seasons[1].episodes.map { $0.parsed.episode ?? -1 }, [1])
    }

    func testEpisodeSortDescendingReversesSeasonsAndEpisodes() {
        let groups = LocalLibraryGrouping.arranged(LocalLibraryGrouping.groups([
            record("Breaking.Bad.S02E01.mkv"),
            record("Breaking.Bad.S01E02.mkv"),
            record("Breaking.Bad.S01E01.mkv"),
        ]), sort: .title, descending: false, episodesDescending: true)
        guard case .show(let show) = groups[0] else { return XCTFail("expected a show") }
        XCTAssertEqual(show.seasons.map { $0.number }, [2, 1])
        XCTAssertEqual(show.seasons[1].episodes.map { $0.parsed.episode ?? -1 }, [2, 1])
    }

    func testSortByTitleYearAndDateAdded() {
        let source = [
            record("Zodiac.2007.mkv", added: 1),
            record("Alien.1979.mkv", added: 2),
            record("Heat.1995.mkv", added: 3),
            record("Home.Video.mkv", added: 4),
        ]
        let groups = LocalLibraryGrouping.groups(source)
        XCTAssertEqual(titles(LocalLibraryGrouping.arranged(groups, sort: .title, descending: false, episodesDescending: false)), ["Alien", "Heat", "Home Video", "Zodiac"])
        XCTAssertEqual(titles(LocalLibraryGrouping.arranged(groups, sort: .year, descending: false, episodesDescending: false)), ["Alien", "Heat", "Zodiac", "Home Video"])
        XCTAssertEqual(titles(LocalLibraryGrouping.arranged(groups, sort: .year, descending: true, episodesDescending: false)), ["Zodiac", "Heat", "Alien", "Home Video"])
        XCTAssertEqual(titles(LocalLibraryGrouping.arranged(groups, sort: .added, descending: true, episodesDescending: false)), ["Home Video", "Heat", "Alien", "Zodiac"])
    }

    func testVersionsRankByResolutionThenSize() {
        let sorted = LocalLibraryGrouping.sortVersions([
            record("Film.2000.480p.mkv", size: 900),
            record("Film.2000.720p.mkv", size: 100),
            record("Film.2000.mkv", size: 5_000),
        ])
        XCTAssertEqual(sorted.map { $0.filename }, ["Film.2000.720p.mkv", "Film.2000.480p.mkv", "Film.2000.mkv"])
    }

    // MARK: - Minimum size

    func testMinimumSizeKeepsLargeFilesAndUnknownSizes() {
        let megabyte: Int64 = 1_048_576
        let kept = LocalLibraryFilter.atLeast([
            record("A.mkv", size: nil),
            record("B.mkv", size: 10 * megabyte),
            record("C.mkv", size: 50 * megabyte),
            record("D.mkv", size: 60 * megabyte),
        ], megabytes: 50)
        XCTAssertEqual(kept.map { $0.filename }, ["A.mkv", "C.mkv", "D.mkv"])
    }

    func testDefaultMinimumMatchesDesktop() {
        XCTAssertEqual(LocalLibraryPreferences.defaultMinimumSizeMB, 50)
        XCTAssertEqual(LocalLibraryPreferences.minimumSizeKey, "localMinFileSizeMb")
        XCTAssertEqual(LocalLibraryPreferences.episodeSortKey, "localEpisodeSortDesc")
    }

    // MARK: - Store

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LocalLibraryTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testStoreAddsPersistsAndRemovesFiles() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("Film.2001.mkv")
        try Data(count: 16).write(to: file)
        let index = directory.appendingPathComponent("library.json")
        let store = LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks())
        XCTAssertTrue(store.ready)
        XCTAssertEqual(try store.addFiles([file]), 1)
        XCTAssertEqual(store.records.first?.filename, "Film.2001.mkv")
        XCTAssertEqual(store.records.first?.size, 16)
        let reopened = LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks())
        XCTAssertEqual(reopened.records.count, 1)
        XCTAssertEqual(try reopened.addFiles([file]), 1, "A valid pick counts even when it is already in the library")
        XCTAssertEqual(reopened.records.count, 1)
        try reopened.remove(ids: Set(reopened.records.map { $0.id }))
        XCTAssertTrue(LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks()).records.isEmpty)
    }

    func testStaleBookmarkIsSavedAgainWhenOpened() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("Film.2001.mkv")
        try Data(count: 16).write(to: file)
        let index = directory.appendingPathComponent("library.json")
        let writer = LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks(prefix: "old:"))
        XCTAssertEqual(try writer.addFiles([file]), 1)
        let reader = LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks(prefix: "new:", stale: true))
        let record = try XCTUnwrap(reader.records.first)
        let access = try reader.openForPlayback(record)
        XCTAssertEqual(access.file.path, file.path)
        access.end()
        let saved = try XCTUnwrap(LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks()).records.first)
        let savedBookmark = try XCTUnwrap(saved.bookmark)
        XCTAssertEqual(String(decoding: savedBookmark, as: UTF8.self), "new:" + file.path)
    }

    func testMissingFileCannotBeOpened() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("Gone.2001.mkv")
        try Data(count: 16).write(to: file)
        let index = directory.appendingPathComponent("library.json")
        let store = LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks())
        XCTAssertEqual(try store.addFiles([file]), 1)
        let record = try XCTUnwrap(store.records.first)
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try store.openForPlayback(record))
    }

    func testDamagedLibraryFileIsKeptAndNotOverwritten() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("Film.2001.mkv")
        try Data(count: 16).write(to: file)
        let index = directory.appendingPathComponent("library.json")
        try Data("not json".utf8).write(to: index)
        let store = LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks())
        XCTAssertFalse(store.ready)
        XCTAssertThrowsError(try store.addFiles([file]))
        XCTAssertEqual(try Data(contentsOf: index), Data("not json".utf8))
    }

    func testFolderImportKeepsLargeVideosWithTheirRelativePath() throws {
        let directory = try makeDirectory()
        let root = directory.appendingPathComponent("Show Folder", isDirectory: true)
        let season = root.appendingPathComponent("Season1", isDirectory: true)
        try FileManager.default.createDirectory(at: season, withIntermediateDirectories: true)
        let megabyte = 1_048_576
        try Data(count: 2 * megabyte).write(to: season.appendingPathComponent("Show.S01E01.mkv"))
        try Data(count: 8).write(to: season.appendingPathComponent("Sample.mkv"))
        try Data(count: 2 * megabyte).write(to: root.appendingPathComponent("notes.txt"))
        let index = directory.appendingPathComponent("library.json")
        let store = LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks())
        XCTAssertEqual(try store.addFolder(root, megabytes: 1), 1)
        let picked = try XCTUnwrap(store.records.first)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertNil(picked.bookmark, "Folder files open through the folder bookmark, not one each")
        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders.first?.name, "Show Folder")
        XCTAssertEqual(picked.folderName, "Show Folder")
        XCTAssertEqual(picked.relativePath, "Season1/Show.S01E01.mkv")
        XCTAssertEqual(picked.parsed.episodeLabel, "S01E01")
        XCTAssertEqual(try store.addFolder(root, megabytes: 1), 0, "Picking the same folder again adds nothing")
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.folders.count, 1)
    }

    func testFolderChildOpensThroughTheFolderBookmark() throws {
        let directory = try makeDirectory()
        let root = directory.appendingPathComponent("Show Folder", isDirectory: true)
        let season = root.appendingPathComponent("Season1", isDirectory: true)
        try FileManager.default.createDirectory(at: season, withIntermediateDirectories: true)
        try Data(count: 2 * 1_048_576).write(to: season.appendingPathComponent("Show.S01E01.mkv"))
        let index = directory.appendingPathComponent("library.json")
        let store = LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks(prefix: "old:"))
        XCTAssertEqual(try store.addFolder(root, megabytes: 1), 1)
        let reopened = LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks(prefix: "new:", stale: true))
        let record = try XCTUnwrap(reopened.records.first)
        let access = try reopened.openForPlayback(record)
        XCTAssertEqual(access.file.path, season.appendingPathComponent("Show.S01E01.mkv").path)
        access.end()
        let saved = try XCTUnwrap(LocalLibraryStore(owner: "tester", fileURL: index, bookmarks: FakeBookmarks()).folders.first)
        XCTAssertEqual(String(decoding: saved.bookmark, as: UTF8.self), "new:" + root.path, "A stale folder bookmark is saved again")
    }
}

/// Bookmarks that keep the path as text, so the store can be tested without the file system grant.
private struct FakeBookmarks: LocalLibraryBookmarks {
    var prefix = "old:"
    var stale = false

    func bookmark(for url: URL) throws -> Data {
        Data((prefix + url.path).utf8)
    }

    func resolve(_ data: Data) throws -> (url: URL, stale: Bool) {
        // Both prefixes used by these tests are four characters long.
        let text = String(decoding: data, as: UTF8.self)
        return (URL(fileURLWithPath: String(text.dropFirst(4))), stale)
    }
}
