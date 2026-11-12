import XCTest
@testable import Harbor

/// F11 B201: Desktop's stream-hint ranking (`release-match.ts`, `stream-hints.ts`, `candidate-ranking.ts`) and the automatic provider choice.
final class F11SubtitleRankingTests: XCTestCase {
    private typealias Match = SubtitleReleaseMatch

    private func candidate(_ release: String?, url: String = "https://example.test/a.srt", language: String = "en", downloads: Int = 0,
                           season: Int? = nil, episode: Int? = nil, confirmed: Bool = false) -> SubtitleProviderCandidate {
        var value = SubtitleProviderCandidate(subtitle: PlaybackSource.Subtitle(url: url, lang: language), provider: .wyzie)
        value.release = release
        value.downloads = downloads
        value.season = season
        value.episode = episode
        value.episodeConfirmed = confirmed
        return value
    }

    // MARK: Release parsing

    func testAReleaseNameGivesGroupSourceAndResolution() {
        let tags = Match.parse("Movie.Name.2020.1080p.BluRay.x264-SPARKS")
        XCTAssertEqual(tags.group, "SPARKS")
        XCTAssertEqual(tags.source, .bluray)
        XCTAssertEqual(tags.resolution, "1080p")
        XCTAssertTrue(tags.hdr.isEmpty)
    }

    func testWebDLEpisodeAndGroup() {
        let tags = Match.parse("Show.S02E05.720p.WEB-DL.DDP5.1.H.264-NTb")
        XCTAssertEqual(tags.source, .webdl)
        XCTAssertEqual(tags.season, 2)
        XCTAssertEqual(tags.episode, 5)
        XCTAssertEqual(tags.group, "NTB")
    }

    func testFourKHdrEditionAndRepack() {
        let tags = Match.parse("Movie 4K UHD BluRay HDR Extended REPACK PROPER")
        XCTAssertEqual(tags.resolution, "2160p")
        XCTAssertEqual(tags.hdr, ["hdr"])
        XCTAssertEqual(tags.edition, ["extended"])
        XCTAssertTrue(tags.repack)
        XCTAssertTrue(tags.proper)
        XCTAssertEqual(Match.parse("Movie.2160p.4K.WEB").resolution, "2160p")
    }

    func testEpisodeRanges() throws {
        let range = try XCTUnwrap(Match.parseEpisodeRange("Show S01E02-E04"))
        XCTAssertEqual(range.season, 1)
        XCTAssertEqual(range.episode, 2)
        XCTAssertEqual(range.episodeEnd, 4)
        let alternate = try XCTUnwrap(Match.parseEpisodeRange("Show 3x07"))
        XCTAssertEqual(alternate.season, 3)
        XCTAssertEqual(alternate.episode, 7)
        XCTAssertEqual(alternate.episodeEnd, 7)
        XCTAssertNil(Match.parseEpisodeRange("Show"))
    }

    func testTheLastWordIsTheGroupUnlessItIsAFormat() {
        XCTAssertEqual(Match.detectGroup("Some.Movie.2019-ZZGRP"), "ZZGRP")
        XCTAssertNil(Match.detectGroup("movie-x264"))
        XCTAssertNil(Match.detectGroup(nil))
        XCTAssertNil(Match.detectGroup(""))
    }

    func testSourceAffinityTable() {
        XCTAssertEqual(Match.sourceAffinity(want: .bluray, got: .bluray), 1)
        XCTAssertEqual(Match.sourceAffinity(want: .remux, got: .bluray), 0.85, accuracy: 1e-9)
        XCTAssertEqual(Match.sourceAffinity(want: .webdl, got: .webrip), 0.75, accuracy: 1e-9)
        XCTAssertEqual(Match.sourceAffinity(want: .bluray, got: .webdl), 0.25, accuracy: 1e-9)
        XCTAssertEqual(Match.sourceAffinity(want: .hdtv, got: .cam), 0)
        XCTAssertEqual(Match.sourceAffinity(want: nil, got: .cam), 0)
    }

    // MARK: Affinity

    func testTheSameReleaseIsAHighConfidenceMatch() {
        let stream = Match.parse("Movie.2020.1080p.BluRay.x264-SPARKS")
        let affinity = Match.affinity(stream: stream, subtitleText: "Movie.2020.1080p.BluRay.x264-SPARKS.srt")
        XCTAssertEqual(affinity.score, 173)
        XCTAssertEqual(affinity.level, .high)
        XCTAssertEqual(affinity.sourceRank, 3)
    }

    func testAnotherEpisodeOrAnotherSourceIsIncompatible() {
        let stream = Match.parse("Show.S01E05.1080p.BluRay-GRP")
        XCTAssertEqual(Match.affinity(stream: stream, subtitleText: "Show.S01E06.1080p.BluRay-GRP").level, .incompatible)
        XCTAssertEqual(Match.affinity(stream: stream, subtitleText: "Show.S01E05.1080p.WEB-DL-OTHER").level, .incompatible)
        XCTAssertNotEqual(Match.affinity(stream: stream, subtitleText: "Show.S01E05.720p.BluRay-OTHER").level, .incompatible)
    }

    func testACloseSourceFamilyIsMediumAndAnUnknownOneIsLow() {
        let stream = Match.parse("Movie.2020.1080p.WEB-DL")
        XCTAssertEqual(Match.affinity(stream: stream, subtitleText: "Movie.2020.WEBRip").level, .medium)
        XCTAssertEqual(Match.affinity(stream: stream, subtitleText: "Movie.2020").level, .low)
    }

    // MARK: Hints

    func testHintsKeepTheReleaseSourceOverTheBadgeAndTheStatedResolution() {
        var hints = SubtitleStreamHints()
        hints.release = "Movie.2020.720p.WEB-DL"
        hints.source = "BluRay"
        hints.resolution = "4K"
        XCTAssertEqual(hints.tags().source, .webdl)
        XCTAssertEqual(hints.tags().resolution, "2160p")
        hints.release = "Movie.2020"
        XCTAssertEqual(hints.tags().source, .bluray)
        hints.season = 2
        hints.episode = 9
        XCTAssertEqual(hints.tags().season, 2)
        XCTAssertEqual(hints.tags().episodeEnd, 9)
    }

    func testResolutionNormalisation() {
        XCTAssertEqual(SubtitleStreamHints.normalizeResolution("UHD"), "2160p")
        XCTAssertEqual(SubtitleStreamHints.normalizeResolution("1080p HDR"), "1080p")
        XCTAssertEqual(SubtitleStreamHints.normalizeResolution("SD 480"), "480p")
        XCTAssertNil(SubtitleStreamHints.normalizeResolution("HD"))
        XCTAssertNil(SubtitleStreamHints.normalizeResolution(nil))
    }

    // MARK: Ranking

    func testHintsPutTheMatchingReleaseFirstWhileNoHintsKeepDownloadsFirst() {
        let popular = candidate("Movie.2020", url: "https://example.test/popular.srt", downloads: 500)
        let matching = candidate("Movie.2020.1080p.BluRay.x264-SPARKS", url: "https://example.test/match.srt", downloads: 3)
        var hints = SubtitleStreamHints()
        hints.release = "Movie.2020.1080p.BluRay.x264-SPARKS.mkv"
        let withHints = SubtitleCandidateRanking.rank([popular, matching], preferredLanguages: ["en"], hints: hints)
        XCTAssertEqual(withHints.map { $0.subtitle.url }, ["https://example.test/match.srt", "https://example.test/popular.srt"])
        let without = SubtitleCandidateRanking.rank([matching, popular], preferredLanguages: ["en"])
        XCTAssertEqual(without.map { $0.subtitle.url }, ["https://example.test/popular.srt", "https://example.test/match.srt"])
    }

    func testIncompatibleAndOtherEpisodeCandidatesAreNotPicked() {
        var hints = SubtitleStreamHints()
        hints.release = "Show.S01E04.1080p.BluRay-GRP"
        hints.season = 1
        hints.episode = 4
        let other = candidate("Show.S01E04.1080p.WEB-DL-X", url: "https://example.test/web.srt")
        let wrongEpisode = candidate("Show", url: "https://example.test/e3.srt", season: 1, episode: 3)
        let fine = candidate("Show.S01E04.1080p.BluRay-GRP", url: "https://example.test/fine.srt", season: 1, episode: 4)
        let ranked = SubtitleCandidateRanking.rank([other, wrongEpisode, fine], preferredLanguages: ["en"], hints: hints)
        XCTAssertEqual(ranked.map { $0.subtitle.url }, ["https://example.test/fine.srt"])
    }

    func testAConfirmedEpisodeOutranksAnUnconfirmedOne() {
        var hints = SubtitleStreamHints()
        hints.season = 1
        hints.episode = 4
        let plain = candidate(nil, url: "https://example.test/plain.srt", downloads: 900, season: 1, episode: 4)
        let confirmed = candidate(nil, url: "https://example.test/confirmed.srt", downloads: 1, season: 1, episode: 4, confirmed: true)
        let ranked = SubtitleCandidateRanking.rank([plain, confirmed], preferredLanguages: ["en"], hints: hints)
        XCTAssertEqual(ranked.first?.subtitle.url, "https://example.test/confirmed.srt")
    }

    func testTheLanguageStillComesBeforeTheReleaseMatch() {
        var hints = SubtitleStreamHints()
        hints.release = "Movie.2020.1080p.BluRay-SPARKS"
        let exactRelease = candidate("Movie.2020.1080p.BluRay-SPARKS", url: "https://example.test/de.srt", language: "de")
        let rightLanguage = candidate("Movie.2020", url: "https://example.test/en.srt", language: "en")
        let ranked = SubtitleCandidateRanking.rank([exactRelease, rightLanguage], preferredLanguages: ["en"], hints: hints)
        XCTAssertEqual(ranked.map { $0.subtitle.url }, ["https://example.test/en.srt"])
    }

    // MARK: Evidence and the automatic choice

    private func result(_ index: Int, release: String?, provider: Bool = true) -> PlaybackSource.Subtitle {
        let url = "https://example.test/\(index).srt"
        var subtitle = PlaybackSource.Subtitle(url: url, lang: "en")
        guard provider else { return subtitle }
        var value = candidate(release, url: url, downloads: index)
        value.provider = .opensubtitles
        subtitle.providerDownload = SubtitleProviderDownload(owner: "o", provider: .opensubtitles, requiresKey: false, season: nil, episode: nil,
                                                             release: release, filename: nil)
        subtitle.evidence = SubtitleCandidateEvidence(value)
        return subtitle
    }

    func testEvidenceRebuildsTheCandidate() throws {
        var original = candidate("Movie.2020.1080p", url: "https://example.test/x.srt", downloads: 12, season: 1, episode: 2, confirmed: true)
        original.hearingImpaired = true
        original.matchConfidence = "high"
        original.matchScore = 0.8
        original.ratingScore = 4.5
        original.ratingTotal = 9
        original.fromTrusted = true
        let subtitle = PlaybackSource.Subtitle(url: "https://example.test/x.srt", lang: "en")
        let rebuilt = try XCTUnwrap(SubtitleCandidateEvidence(original).candidate(for: subtitle))
        XCTAssertEqual(rebuilt.release, "Movie.2020.1080p")
        XCTAssertEqual(rebuilt.downloads, 12)
        XCTAssertEqual(rebuilt.season, 1)
        XCTAssertEqual(rebuilt.episode, 2)
        XCTAssertTrue(rebuilt.episodeConfirmed)
        XCTAssertTrue(rebuilt.hearingImpaired)
        XCTAssertTrue(rebuilt.fromTrusted)
        XCTAssertEqual(rebuilt.matchConfidence, "high")
        XCTAssertEqual(rebuilt.ratingTotal, 9)
        XCTAssertEqual(rebuilt.provider, .wyzie)
    }

    func testProviderResultsComeFirstThenAddonResultsInTheirOwnOrder() {
        var subtitles = (1...3).map { result($0, release: "Movie.2020") }
        subtitles.append(result(98, release: nil, provider: false))
        subtitles.append(PlaybackSource.Subtitle(url: "https://example.test/de.srt", lang: "de"))
        subtitles.append(result(99, release: nil, provider: false))
        let picks = SubtitleAutoProviderChoice.picks(subtitles, preferredLanguages: ["en"], hints: nil)
        XCTAssertEqual(picks.map { $0.url }, ["https://example.test/3.srt", "https://example.test/2.srt", "https://example.test/1.srt",
                                              "https://example.test/98.srt", "https://example.test/99.srt"])
    }

    func testTheListIsCappedAtFiveAttempts() {
        let subtitles = (1...7).map { result($0, release: "Movie.2020") }
        let picks = SubtitleAutoProviderChoice.picks(subtitles, preferredLanguages: ["en"], hints: nil)
        XCTAssertEqual(picks.count, SubtitleAutoProviderChoice.attempts)
        XCTAssertEqual(picks.first?.url, "https://example.test/7.srt")
    }

    func testAddonResultsAreIgnoredWhenNoLanguageIsPreferred() {
        let picks = SubtitleAutoProviderChoice.picks([result(5, release: nil, provider: false)], preferredLanguages: [], hints: nil)
        XCTAssertTrue(picks.isEmpty)
    }

    func testThePlayerNeedsAProviderSubtitleOnlyWhenTheFileHasNoneInTheLanguage() {
        let english = SubtitleSelectionCandidate(id: 1, language: "en")
        let spanish = SubtitleSelectionCandidate(id: 2, language: "es")
        let forcedEnglish = SubtitleSelectionCandidate(id: 3, language: "en", forced: true)
        XCTAssertTrue(SubtitleAutoProviderChoice.playerNeedsOne(tracks: [], languages: ["en"]))
        XCTAssertTrue(SubtitleAutoProviderChoice.playerNeedsOne(tracks: [spanish, forcedEnglish], languages: ["en"]))
        XCTAssertFalse(SubtitleAutoProviderChoice.playerNeedsOne(tracks: [spanish, english], languages: ["en"]))
        XCTAssertFalse(SubtitleAutoProviderChoice.playerNeedsOne(tracks: [], languages: []))
    }
}
