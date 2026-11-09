import XCTest
@testable import Harbor

/// Desktop's keyless and user-keyed subtitle providers (`providers/wyzie.ts`, `providers/opensubtitles-v3.ts`,
/// `autosync/sub-source-subdl.ts`, `autosync/sub-source-subsource.ts`). Canned JSON only, so no network is used.
/// The keys below are placeholders.
private struct SubtitleProviderCannedTransport: SubtitleProviderTransport {
    let handle: @Sendable (URLRequest) -> SubtitleProviderReply

    func send(_ request: URLRequest) async throws -> SubtitleProviderReply {
        handle(request)
    }
}

private struct SubtitleProviderSlowTransport: SubtitleProviderTransport {
    let fastReply: Data

    func send(_ request: URLRequest) async throws -> SubtitleProviderReply {
        if request.url?.host == "sub.wyzie.io" {
            try await Task.sleep(for: .seconds(30))
            return SubtitleProviderReply(status: 200, data: Data("[]".utf8))
        }
        return SubtitleProviderReply(status: 200, data: fastReply)
    }
}

final class SubtitleProvidersTests: XCTestCase {
    private static let wyzieBody = """
    [
      {"id": 31, "url": "https://sub.wyzie.io/files/31.srt", "display": "English", "language": "en", "format": "SRT", "release": "Show.S01E02.1080p.WEB", "downloads": 3}
    ]
    """

    private static let subdlBody = """
    {"status": true, "results": [{"imdb_id": "tt0944947", "tmdb_id": 1399}], "subtitles": [
      {"n_id": 555, "name": "Show.S01E02.1080p", "language": "EN", "release_name": "Show.S01E02.1080p.WEB", "hi": 1, "url": "/subtitle/555-1.zip", "format": "zip", "season": 1, "episode": 2, "downloads": 900, "unpack_files": [
        {"file_n_id": 9001, "name": "Show.S01E02.srt", "season": 1, "episode": 2, "language": "EN", "url": "/subtitle/9001.srt", "format": "srt"},
        {"file_n_id": 9002, "name": "Show.S01E03.srt", "season": 1, "episode": 3, "language": "EN", "url": "/subtitle/9002.srt", "format": "srt"}
      ]},
      {"n_id": 556, "language": "PT", "url": "https://dl.subdl.com/subtitle/556.zip", "format": "zip", "full_season": true, "season": 1}
    ]}
    """

    private func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func queryValue(_ url: URL?, _ name: String) -> String? {
        guard let url = url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    private func candidate(_ provider: SubtitleProviderID, _ id: String, _ url: String, _ language: String,
                           title: String? = nil, searchTitle: String? = nil, format: String? = nil,
                           downloads: Int = 0, confidence: String? = nil, requiresKey: Bool = false) -> SubtitleProviderCandidate {
        var result = SubtitleProviderCandidate(
            subtitle: PlaybackSource.Subtitle(url: url, lang: language, id: id, title: title), provider: provider,
            format: format, requiresKey: requiresKey, downloads: downloads, matchConfidence: confidence
        )
        result.searchTitle = searchTitle
        return result
    }

    func testImdbIdsArePrefixedAndPadded() {
        XCTAssertEqual(SubtitleProviderIDs.imdb("133093"), "tt0133093")
        XCTAssertEqual(SubtitleProviderIDs.imdb("tt0133093"), "tt0133093")
        XCTAssertNil(SubtitleProviderIDs.imdb(nil))
    }

    func testWyzieRequestUsesImdbIdSourceAndNormalizedLanguages() {
        let url = WyzieProvider.request(SubtitleProviderQuery(imdbID: "0133093", languages: ["en", "es"]))
        XCTAssertEqual(queryValue(url, "id"), "tt0133093")
        XCTAssertEqual(queryValue(url, "source"), "all")
        XCTAssertEqual(queryValue(url, "language"), "en,es")
        XCTAssertNil(queryValue(url, "query"))
    }

    func testWyzieParsesHearingFlagReleaseAndSkipsRowsWithoutAUrl() {
        let body = """
        [
          {"id": 11, "url": "https://sub.wyzie.io/files/11.srt", "display": "English", "language": "en", "format": "SRT", "release": "Movie.2010.1080p.BluRay", "isHearingImpaired": true, "downloads": 42, "author": "alice"},
          {"id": 12, "url": "https://sub.wyzie.io/files/12.vtt", "display": "Spanish", "language": "es", "format": "vtt", "hi": false, "release": "Movie.2010.720p"},
          {"id": 13, "display": "English", "language": "en"}
        ]
        """
        let found = WyzieProvider.parse(Data(body.utf8))
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0].subtitle.id, "wyzie:11")
        XCTAssertEqual(found[0].subtitle.lang, "en")
        XCTAssertTrue(found[0].hearingImpaired)
        XCTAssertEqual(found[0].format, "srt")
        XCTAssertEqual(found[0].release, "Movie.2010.1080p.BluRay")
        XCTAssertEqual(found[0].downloads, 42)
        XCTAssertEqual(found[0].author, "alice")
        XCTAssertNil(found[0].matchConfidence)
        XCTAssertFalse(found[1].hearingImpaired)
        XCTAssertFalse(found[1].archive)
        XCTAssertEqual(found[1].subtitle.lang, "es")
    }

    func testOpenSubtitlesV3EpisodeRequestIsScoped() {
        let requests = OpenSubtitlesV3Provider.requests(SubtitleProviderQuery(imdbID: "tt0944947", season: 1, episode: 2))
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.absoluteString, "https://opensubtitles-v3.strem.io/subtitles/series/tt0944947:1:2.json")
    }

    func testOpenSubtitlesV3DedupesAndClassifies() {
        let body = """
        {"subtitles": [
          {"id": "a1", "url": "https://dl.example.org/a1.srt", "lang": "en", "m": "Show.S01E02.WEB-DL", "SubFormat": "SRT", "fps": 23.976, "hearing_impaired": "yes"},
          {"id": "a2", "url": "https://dl.example.org/a2.srt", "lang": "en", "m": "Show.S01E02.HDTV"},
          {"id": "a1", "url": "https://dl.example.org/a1.srt", "lang": "en", "m": "duplicate"},
          {"id": "a3", "url": "https://dl.example.org/a3.srt", "lang": "es", "m": "Show.S01E02 forced", "foreign_parts": 1}
        ]}
        """
        let found = OpenSubtitlesV3Provider.parse(Data(body.utf8))
        XCTAssertEqual(found.count, 3)
        XCTAssertEqual(found[0].subtitle.lang, "en")
        XCTAssertTrue(found[0].hearingImpaired)
        XCTAssertEqual(found[0].format, "srt")
        XCTAssertEqual(found[0].fps, 23.976)
        XCTAssertFalse(found[1].hearingImpaired)
        XCTAssertEqual(found[2].subtitle.lang, "es")
        XCTAssertTrue(found[2].forced)
        XCTAssertTrue(found[2].foreignOnly)
    }

    func testOpenSubtitlesPreservesDistinctRowsWithTheSameURLAndNormalizedLanguage() {
        let body = #"{"subtitles": [
          {"id": "same", "url": "https://dl.example.org/same.srt", "lang": "en", "m": "Show.WEB", "SubFormat": "SRT"},
          {"id": "same", "url": "https://dl.example.org/same.srt", "lang": "eng", "m": "Show.WEB", "SubFormat": "SRT"}
        ]}"#
        let found = OpenSubtitlesV3Provider.parse(Data(body.utf8))
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found.map(\.searchTitle), ["OpenSubtitles V3 #1", "OpenSubtitles V3 #2"])
        XCTAssertEqual(found.map(\.subtitle.lang), ["en", "en"])
        XCTAssertNotEqual(SubtitleSearchRanking.listIdentity(for: found[0]), SubtitleSearchRanking.listIdentity(for: found[1]))
    }

    func testSearchDeduplicatesByDesktopCompositeKeyAndKeepsDistinctSameURLRows() {
        let url = "https://subs.example.org/shared.srt"
        let weaker = candidate(.wyzie, "wyzie:weak", url, "en", title: "Wyzie · WEB", searchTitle: "WEB",
                               downloads: 5, confidence: "low")
        let stronger = candidate(.subsource, "subsource:strong", url, "eng", title: "Subsource · WEB", searchTitle: "WEB",
                                 downloads: 1, confidence: "high", requiresKey: true)
        let alternateTitle = candidate(.wyzie, "wyzie:alt", url, "en", title: "Wyzie · BluRay", searchTitle: "BluRay")
        let alternateFormat = candidate(.wyzie, "wyzie:ass", url, "en", title: "Wyzie · WEB", searchTitle: "WEB", format: "ass")
        let alternateLanguage = candidate(.wyzie, "wyzie:es", url, "es", title: "Wyzie · WEB", searchTitle: "WEB")

        let ranked = SubtitleSearchRanking.deduplicateAndRank(
            [weaker, stronger, alternateTitle, alternateFormat, alternateLanguage], preferredLanguages: ["en"]
        )
        XCTAssertEqual(ranked.count, 4)
        XCTAssertTrue(ranked.contains { $0.subtitle.id == "subsource:strong" }, "The higher confidence keyed duplicate wins")
        XCTAssertTrue(ranked.contains { $0.subtitle.id == "wyzie:alt" }, "A different title remains a separate row")
        XCTAssertTrue(ranked.contains { $0.subtitle.id == "wyzie:ass" }, "A different format remains a separate row")
        XCTAssertTrue(ranked.contains { $0.subtitle.id == "wyzie:es" }, "A different language remains a separate row")
        XCTAssertNotEqual(SubtitleSearchRanking.listIdentity(for: alternateTitle), SubtitleSearchRanking.listIdentity(for: alternateFormat))
    }

    func testDuplicateMergeDoesNotTransferAnInMemoryProviderDownloadGrant() {
        let url = "https://subs.example.org/shared.zip"
        var fallback = candidate(.wyzie, "addon-row", url, "en", title: "Addon · WEB", searchTitle: "WEB")
        fallback.subtitle.providerDownload = SubtitleProviderDownload(owner: "profile-a", provider: nil, requiresKey: false,
                                                                       season: nil, episode: nil, release: nil, filename: nil)
        let keyed = candidate(.subsource, "subsource-row", url, "en", title: "Subsource · WEB", searchTitle: "WEB",
                              confidence: "high", requiresKey: true)

        let ranked = SubtitleSearchRanking.deduplicateAndRank([fallback, keyed], preferredLanguages: [])
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked[0].subtitle.id, "subsource-row")
        XCTAssertNil(ranked[0].subtitle.providerDownload, "A duplicate URL cannot inherit another provider's ephemeral grant")
    }

    func testDuplicateTieUsesHigherDesktopDownloadCountAndRetainsTheGroupingKey() {
        let url = "https://subs.example.org/packed.zip"
        let popular = candidate(.wyzie, "popular", url, "en", searchTitle: "Release", format: nil, downloads: 30)
        let alternate = candidate(.subsource, "alternate", url, "en", searchTitle: "Release", format: "zip", downloads: 3)
        let ranked = SubtitleSearchRanking.deduplicateAndRank([alternate, popular], preferredLanguages: ["en"])
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.subtitle.id, "popular")
        XCTAssertEqual(ranked.first.map(SubtitleSearchRanking.listIdentity(for:)), SubtitleSearchRanking.listIdentity(for: popular))
    }

    func testNativeSubtitleRowsAndDownloadsKeepSameURLLanguagesAndCredentialScopesSeparate() throws {
        let url = "https://subs.example.org/episode.zip"
        let response: JSONValue = .object(["subtitles": .array([
            .object(["url": .string(url), "lang": .string("en"), "label": .string("Release")]),
            .object(["url": .string(url), "lang": .string("spa"), "label": .string("Release")])
        ])])
        let rows = SubtitleAddonService.parse(response, provider: "Community Subtitles")
        XCTAssertEqual(Set(rows.map(\.selectionIdentity)).count, 2)
        let original = try XCTUnwrap(rows.first)
        var direct = original
        direct.providerDownload = SubtitleProviderDownload(owner: "profile-a", provider: .subsource, requiresKey: true,
                                                           season: 1, episode: 2, release: "Release", filename: "episode.mkv")
        XCTAssertNotEqual(direct.downloadIdentity, original.downloadIdentity)

        let merged = SubtitleSearchRanking.mergeResults(rows, [direct], preferredLanguages: ["es"])
        XCTAssertEqual(merged.map(\.lang), ["spa", "en"])
        XCTAssertNil(merged[0].providerDownload)
        XCTAssertEqual(merged[1].providerDownload?.provider, .subsource)
        let persisted = try JSONDecoder().decode(PlaybackSource.Subtitle.self, from: JSONEncoder().encode(direct))
        XCTAssertNil(persisted.providerDownload)
        XCTAssertEqual(persisted.selectionIdentity, url)
    }

    func testSearchInterleavesProvidersAfterPuttingTheBestPreferredLanguageFirst() {
        let url = "https://subs.example.org/"
        let opensubtitlesEnglish = candidate(.opensubtitles, "os-en", url + "os-en.srt", "en", searchTitle: "OS #1", downloads: 5)
        let opensubtitlesFrench = candidate(.opensubtitles, "os-fr", url + "os-fr.srt", "fr", searchTitle: "OS #1", downloads: 100)
        let wyzieEnglish = candidate(.wyzie, "wy-en", url + "wy-en.srt", "en", searchTitle: "WEB", downloads: 50)
        let wyzieFrench = candidate(.wyzie, "wy-fr", url + "wy-fr.srt", "fr", searchTitle: "BluRay", downloads: 2)

        let ranked = SubtitleSearchRanking.deduplicateAndRank(
            [opensubtitlesEnglish, opensubtitlesFrench, wyzieEnglish, wyzieFrench], preferredLanguages: ["en"]
        )
        XCTAssertEqual(ranked.map(\.subtitle.id), ["wy-en", "os-en", "os-fr", "wy-fr"])
    }

    func testSubDLRequestCarriesKeyAndLanguageCodes() {
        let query = SubtitleProviderQuery(imdbID: "tt0944947", series: true, season: 1, episode: 2, languages: ["en", "pt-br"])
        let url = SubDLProvider.request(query, apiKey: "test-subdl-key")
        XCTAssertEqual(queryValue(url, "api_key"), "test-subdl-key")
        XCTAssertEqual(queryValue(url, "languages"), "EN,BR")
        XCTAssertEqual(queryValue(url, "type"), "tv")
        XCTAssertEqual(queryValue(url, "imdb_id"), "tt0944947")
        XCTAssertEqual(queryValue(url, "season_number"), "1")
        XCTAssertEqual(queryValue(url, "episode_number"), "2")
    }

    func testSubDLPicksTheRequestedEpisodeFileAndFlagsZipPacks() {
        let query = SubtitleProviderQuery(imdbID: "tt0944947", series: true, season: 1, episode: 2)
        let found = SubDLProvider.parse(Data(Self.subdlBody.utf8), query: query)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0].subtitle.url, "https://dl.subdl.com/subtitle/9001.srt")
        XCTAssertEqual(found[0].subtitle.id, "subdl:9001")
        XCTAssertEqual(found[0].subtitle.lang, "en")
        XCTAssertTrue(found[0].hearingImpaired)
        XCTAssertFalse(found[0].archive)
        XCTAssertTrue(found[0].episodeConfirmed)
        XCTAssertEqual(found[0].matchConfidence, "high")
        XCTAssertEqual(found[1].subtitle.url, "https://dl.subdl.com/subtitle/556.zip")
        XCTAssertEqual(found[1].subtitle.lang, "pt")
        XCTAssertTrue(found[1].archive)
        XCTAssertEqual(found[1].matchConfidence, "medium")
    }

    func testSubSourceChoosesTheMovieByImdbAndAcceptsNumericIDs() throws {
        let envelope = try parse("""
        {"success": true, "data": [
          {"movieId": 77, "title": "Other Show", "type": "series", "imdbId": "tt9999999", "tmdbId": 5, "season": 1},
          {"movieId": 123, "title": "Show", "type": "series", "imdbId": "tt0944947", "tmdbId": 1399, "season": 1}
        ]}
        """)
        let query = SubtitleProviderQuery(imdbID: "tt0944947", series: true, season: 1, episode: 2)
        let movie = try XCTUnwrap(SubSourceProvider.chosenMovie(envelope, query: query))
        XCTAssertEqual(SubtitleProviderJSON.text(movie["movieId"]), "123")
    }

    func testSubSourceListsExactReleaseThenAllForEachLanguage() {
        let query = SubtitleProviderQuery(imdbID: "tt0944947", series: true, season: 1, episode: 2, languages: ["en", "pt-br"], filename: "/media/Show.S01E02.1080p.WEB.mkv")
        let requests = SubSourceProvider.listRequests(movieID: "123", query: query)
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(queryValue(requests[0].url, "movieId"), "123")
        XCTAssertEqual(queryValue(requests[0].url, "language"), "english")
        XCTAssertEqual(queryValue(requests[0].url, "releaseInfo"), "Show.S01E02.1080p.WEB")
        XCTAssertTrue(requests[0].exactRelease)
        XCTAssertEqual(queryValue(requests[2].url, "language"), "brazilian_portuguese")
        XCTAssertFalse(requests[3].exactRelease)
        XCTAssertNil(queryValue(requests[3].url, "releaseInfo"))
    }

    func testSubSourceParsesZipRowsThatNeedTheKey() throws {
        let envelope = try parse("""
        {"success": true, "data": [
          {"subtitleId": 9001, "movieId": 123, "language": "en", "releaseInfo": ["Show.S01E02.1080p.WEB", "x264"], "hearingImpaired": true, "productionType": "retail", "downloads": 500, "rating": {"good": 9, "bad": 1, "total": 10}, "contributors": [{"id": 1, "displayname": "Ann"}]},
          {"subtitleId": 9002, "language": "en", "productionType": "machine", "releaseInfo": "Show.E02"}
        ]}
        """)
        let movie = try parse(#"{"movieId": 123, "season": 1, "imdbId": "tt0944947"}"#)
        let query = SubtitleProviderQuery(imdbID: "tt0944947", series: true, season: 1, episode: 2)
        let found = SubSourceProvider.parseSubtitles(envelope, movie: movie, query: query, exactRelease: true)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0].subtitle.url, "https://api.subsource.net/api/v1/subtitles/9001/download")
        XCTAssertEqual(found[0].subtitle.lang, "en")
        XCTAssertTrue(found[0].archive)
        XCTAssertTrue(found[0].requiresKey)
        XCTAssertTrue(found[0].hearingImpaired)
        XCTAssertTrue(found[0].fromTrusted)
        XCTAssertEqual(found[0].release, "Show.S01E02.1080p.WEB x264")
        XCTAssertEqual(found[0].author, "Ann")
        let score = try XCTUnwrap(found[0].ratingScore)
        XCTAssertEqual(score, 0.9, accuracy: 0.0001)
        XCTAssertEqual(found[0].matchConfidence, "high")
        XCTAssertTrue(found[1].machineTranslated)
    }

    func testLanguageCodesMatchEachProviderFormat() {
        XCTAssertEqual(SubDLProvider.languageCode("pt-br"), "BR")
        XCTAssertEqual(SubDLProvider.languageCode("en"), "EN")
        XCTAssertEqual(SubSourceProvider.languageName("pt-br"), "brazilian_portuguese")
        XCTAssertEqual(SubSourceProvider.languageName("fa"), "farsi_persian")
        XCTAssertEqual(SubSourceProvider.languageName("en"), "english")
    }

    func testProviderFlagsWinOverReleaseLabels() throws {
        let explicit = SubtitleProviderClassification.classify(try parse(#"{"hearingImpaired": false}"#), labels: ["Movie.SDH.x264"])
        XCTAssertFalse(explicit.hearingImpaired)
        let labelled = SubtitleProviderClassification.classify(try parse("{}"), labels: ["Movie.SDH.x264"])
        XCTAssertTrue(labelled.hearingImpaired)
        let machine = SubtitleProviderClassification.classify(try parse(#"{"machine_translated": "1"}"#), labels: [])
        XCTAssertTrue(machine.machineTranslated)
    }

    func testUnsafeSubtitleURLsAreDropped() {
        let body = """
        [
          {"url": "ftp://sub.wyzie.io/a.srt", "language": "en"},
          {"url": "https://user:secret@sub.wyzie.io/b.srt", "language": "en"},
          {"url": "https://sub.wyzie.io/c\\u0007.srt", "language": "en"}
        ]
        """
        XCTAssertEqual(WyzieProvider.parse(Data(body.utf8)).count, 0)
    }

    func testFormatIsReadFromTheHintOrTheExtension() {
        XCTAssertEqual(SubtitleProviderFormat.detect("https://sub.wyzie.io/a.zip", hint: nil), "zip")
        XCTAssertEqual(SubtitleProviderFormat.detect("https://sub.wyzie.io/a", hint: "WebVTT"), "vtt")
        XCTAssertNil(SubtitleProviderFormat.detect("https://sub.wyzie.io/a", hint: nil))
    }

    func testServiceSkipsKeyedProvidersWithoutAKey() async {
        let wyzie = Self.wyzieBody
        let subdl = Self.subdlBody
        let service = SubtitleProviderService(transport: SubtitleProviderCannedTransport(handle: { request in
            let host = request.url?.host ?? ""
            switch host {
            case "sub.wyzie.io": return SubtitleProviderReply(status: 200, data: Data(wyzie.utf8))
            case "api.subdl.com": return SubtitleProviderReply(status: 200, data: Data(subdl.utf8))
            default: return SubtitleProviderReply(status: 404, data: Data())
            }
        }))
        let query = SubtitleProviderQuery(imdbID: "tt0944947", series: true, season: 1, episode: 2)
        let results = await service.search(query, enabled: [.wyzie, .subdl], keys: SubtitleProviderKeys())
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.allSatisfy { $0.provider == .wyzie })
    }

    func testServiceUsesTheSavedSubDLKey() async {
        let subdl = Self.subdlBody
        let service = SubtitleProviderService(transport: SubtitleProviderCannedTransport(handle: { request in
            guard request.url?.host == "api.subdl.com" else { return SubtitleProviderReply(status: 404, data: Data()) }
            return SubtitleProviderReply(status: 200, data: Data(subdl.utf8))
        }))
        let query = SubtitleProviderQuery(imdbID: "tt0944947", series: true, season: 1, episode: 2)
        let results = await service.search(query, enabled: [.subdl], keys: SubtitleProviderKeys(subdl: "test-subdl-key"))
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.provider == .subdl })
    }

    func testSlowProviderDoesNotDelayAnotherProviderPastItsOwnDeadline() async {
        let body = #"{"subtitles": [{"id": "fast", "url": "https://dl.example.org/fast.srt", "lang": "en"}]}"#
        let service = SubtitleProviderService(transport: SubtitleProviderSlowTransport(fastReply: Data(body.utf8)),
                                              providerTimeout: .milliseconds(40))
        let started = ContinuousClock.now
        let results = await service.search(SubtitleProviderQuery(imdbID: "tt0944947"), enabled: [.opensubtitles, .wyzie], keys: SubtitleProviderKeys())
        let elapsed = started.duration(to: .now)
        XCTAssertLessThan(elapsed, .seconds(1))
        XCTAssertEqual(results.map(\.subtitle.id), ["os3:fast"])
    }

    func testProviderTogglesFallBackToDesktopDefaults() {
        let suite = "subtitle-providers-tests"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(SubtitleProviderPreferences.isEnabled(.opensubtitles, defaults: defaults))
        XCTAssertFalse(SubtitleProviderPreferences.isEnabled(.wyzie, defaults: defaults))
        XCTAssertFalse(SubtitleProviderPreferences.isEnabled(.subdl, defaults: defaults))
        XCTAssertFalse(SubtitleProviderPreferences.isEnabled(.subsource, defaults: defaults))
        defaults.set(true, forKey: SubtitleProviderPreferences.storageKey(.wyzie))
        XCTAssertEqual(SubtitleProviderPreferences.enabledProviders(defaults: defaults), [.opensubtitles, .wyzie])
    }
}
