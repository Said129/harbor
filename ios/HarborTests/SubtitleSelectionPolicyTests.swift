import XCTest
@testable import Harbor

/// Desktop's subtitle selection rules (`track-selection.ts`, `use-track-autoload.ts`, `autoload-run.ts`, `ass-header.ts`), checked against concrete track samples.
final class SubtitleSelectionPolicyTests: XCTestCase {
    private typealias Policy = SubtitleSelectionPolicy

    private func embedded(_ id: Int, _ language: String, title: String = "", isDefault: Bool = false) -> SubtitleSelectionCandidate {
        SubtitleSelectionCandidate(id: id, language: language, title: title, isDefault: isDefault)
    }

    private func external(_ id: Int, _ language: String, title: String = "", level: SubtitleMatchLevel = .low, timing: SubtitleTimingStatus = .notChecked, score: Double = 0) -> SubtitleSelectionCandidate {
        SubtitleSelectionCandidate(id: id, language: language, title: title, external: true, matchScore: score, matchLevel: level, timing: timing)
    }

    private func context(_ origin: SubtitleSelectionOrigin = .none, languages: [String] = ["en"], preferEmbedded: Bool = false, autoUpgrade: Bool = false, blockWords: [String] = [], suppressed: Bool = false) -> SubtitleAutoSelectionContext {
        SubtitleAutoSelectionContext(origin: origin, languages: languages, preferEmbedded: preferEmbedded, autoUpgrade: autoUpgrade, blockWords: blockWords, suppressed: suppressed)
    }

    // MARK: Language score

    func testLanguageScoreRanksExactThenBaseThenMissing() {
        XCTAssertEqual(Policy.languageScore("en", preferred: ["en", "es"]), 4)
        XCTAssertEqual(Policy.languageScore("es", preferred: ["en", "es"]), 2)
        XCTAssertEqual(Policy.languageScore("fr", preferred: ["en", "es"]), -1)
        // Base-language match: "pt" against the preference "pt-br" scores (1 - 0) * 2 - 1.
        XCTAssertEqual(Policy.languageScore("pt-pt", preferred: ["pt-br"]), 1)
    }

    func testLanguageScoreIsNeutralWithoutPreferences() {
        XCTAssertEqual(Policy.languageScore("fr", preferred: []), 0)
    }

    // MARK: Picking

    func testNativeAudioUsesForcedTrackOrOffWithoutOverridingManualChoice() {
        let full = SubtitleSelectionCandidate(id: 1, language: "es", title: "Full")
        let english = SubtitleSelectionCandidate(id: 2, language: "en", forced: true)
        let spanish = SubtitleSelectionCandidate(id: 3, language: "spa", title: "Signs (Forced)")
        let context = SubtitleAutoSelectionContext(origin: .playerDefault, languages: ["es"])
        XCTAssertEqual(SubtitleSelectionWiring.forcedChoice(candidates: [full, english, spanish], audioLanguage: "spa", context: context), .track(3))
        XCTAssertEqual(SubtitleSelectionWiring.forcedChoice(candidates: [full], audioLanguage: "es", context: context), .off)
        XCTAssertNil(SubtitleSelectionWiring.forcedChoice(candidates: [spanish], audioLanguage: "ja", context: context))

        var manual = context
        manual.origin = .manual
        XCTAssertNil(SubtitleSelectionWiring.forcedChoice(candidates: [spanish], audioLanguage: "es", context: manual))
    }

    func testLanguageOrderBeatsEmbeddedPreference() {
        let tracks = [embedded(1, "en"), external(2, "es", level: .low)]
        XCTAssertEqual(Policy.desiredTrack(among: tracks, languages: ["es", "en"], preferEmbedded: false)?.id, 2)
        XCTAssertEqual(Policy.desiredTrack(among: tracks, languages: ["es", "en"], preferEmbedded: true)?.id, 2)
    }

    func testPreferEmbeddedDecidesSameLanguageTie() {
        let tracks = [embedded(1, "en"), external(2, "en", level: .high)]
        XCTAssertEqual(Policy.desiredTrack(among: tracks, languages: ["en"], preferEmbedded: false)?.id, 2)
        XCTAssertEqual(Policy.desiredTrack(among: tracks, languages: ["en"], preferEmbedded: true)?.id, 1)
    }

    func testAlignedTimingBeatsMatchLevel() {
        let tracks = [external(3, "en", level: .high), external(4, "en", level: .medium, timing: .aligned)]
        XCTAssertEqual(Policy.desiredTrack(among: tracks, languages: ["en"], preferEmbedded: false)?.id, 4)
    }

    func testHigherMatchLevelWinsWithoutTiming() {
        let tracks = [external(5, "en", level: .medium), external(6, "en", level: .high)]
        XCTAssertEqual(Policy.desiredTrack(among: tracks, languages: ["en"], preferEmbedded: false)?.id, 6)
    }

    func testMatchScoreBreaksLevelTie() {
        let tracks = [external(7, "en", title: "Other", level: .high, score: 0.4), external(8, "en", title: "Other", level: .high, score: 0.9)]
        XCTAssertEqual(Policy.desiredTrack(among: tracks, languages: ["en"], preferEmbedded: false)?.id, 8)
    }

    func testOpenSubtitlesSourceRanksBelowOtherExternalSources() {
        let tracks = [external(9, "en", title: "Other", level: .high), external(10, "en", title: "OpenSubtitles", level: .high)]
        XCTAssertEqual(Policy.desiredTrack(among: tracks, languages: ["en"], preferEmbedded: false)?.id, 9)
    }

    func testDefaultFlagBreaksFinalTie() {
        let tracks = [embedded(11, "en"), embedded(12, "en", isDefault: true)]
        XCTAssertEqual(Policy.desiredTrack(among: tracks, languages: ["en"], preferEmbedded: false)?.id, 12)
    }

    func testForcedIncompatibleAndOtherLanguageTracksAreNeverPicked() {
        let tracks = [
            SubtitleSelectionCandidate(id: 1, language: "en", forced: true),
            embedded(2, "en", title: "Forced Signs"),
            external(3, "en", level: .incompatible),
            embedded(4, "fr"),
        ]
        XCTAssertNil(Policy.desiredTrack(among: tracks, languages: ["en"], preferEmbedded: false))
    }

    func testUnpreparedExternalAndDifferentCutAreRejected() {
        XCTAssertNil(Policy.desiredTrack(among: [SubtitleSelectionCandidate(id: 5, language: "en", external: true, prepared: false)], languages: ["en"], preferEmbedded: false))
        XCTAssertNil(Policy.desiredTrack(among: [external(6, "en", timing: .differentCut)], languages: ["en"], preferEmbedded: false))
        XCTAssertNil(Policy.desiredTrack(among: [external(6, "en", timing: .invalid)], languages: ["en"], preferEmbedded: false))
        XCTAssertEqual(Policy.desiredTrack(among: [external(6, "en", timing: .fixedOffset)], languages: ["en"], preferEmbedded: false)?.id, 6)
    }

    func testForcedWordDetectionIsWholeWordAndCaseInsensitive() {
        XCTAssertTrue(Policy.hasForcedWord("Forced"))
        XCTAssertTrue(Policy.hasForcedWord("Signs (Forced)"))
        XCTAssertTrue(Policy.hasForcedWord("Forced-Signs"))
        XCTAssertFalse(Policy.hasForcedWord("Unforced"))
        XCTAssertFalse(Policy.hasForcedWord("forcedsigns"))
    }

    func testDesiredIsEmbeddedOnlyWhenEmbeddedPreferredAndWins() {
        let tracks = [embedded(1, "en"), external(2, "en", level: .high)]
        XCTAssertTrue(Policy.desiredIsEmbedded(tracks, languages: ["en"], preferEmbedded: true))
        XCTAssertFalse(Policy.desiredIsEmbedded(tracks, languages: ["en"], preferEmbedded: false))
        XCTAssertFalse(Policy.desiredIsEmbedded([external(2, "en", level: .high)], languages: ["en"], preferEmbedded: true))
    }

    // MARK: Block words

    func testBlockWordsParseLikeDesktopSettings() {
        XCTAssertEqual(Policy.blockWords(fromText: "commentary, Descriptive,, commentary "), ["commentary", "Descriptive"])
        XCTAssertEqual(Policy.normalizedBlockWords(["  Commentary ", ""]), ["commentary"])
    }

    func testBlockWordsSkipTracksByTitleSubstring() {
        let tracks = [embedded(1, "en", title: "Director's Commentary"), embedded(2, "en", title: "Full")]
        XCTAssertEqual(Policy.trackToAutoSelect(among: tracks, context: context(blockWords: ["commentary"]))?.id, 2)
        XCTAssertEqual(Policy.trackToAutoSelect(among: tracks, context: context())?.id, 1)
    }

    func testBlockWordsFallBackToAllTracksWhenEveryTrackIsBlocked() {
        let tracks = [embedded(1, "en", title: "Commentary"), embedded(2, "en", title: "commentary 2")]
        XCTAssertEqual(Policy.allowed(tracks, blockWords: ["commentary"]).map { $0.id }, [1, 2])
        XCTAssertEqual(Policy.trackToAutoSelect(among: tracks, context: context(blockWords: ["commentary"]))?.id, 1)
    }

    // MARK: Auto upgrade and replacement

    func testReplacementRulesForNormalPath() {
        XCTAssertTrue(Policy.replacementAllowed(origin: .none, autoUpgrade: false, lateArrival: false))
        XCTAssertTrue(Policy.replacementAllowed(origin: .playerDefault, autoUpgrade: false, lateArrival: false))
        XCTAssertFalse(Policy.replacementAllowed(origin: .automatic, autoUpgrade: false, lateArrival: false))
        XCTAssertTrue(Policy.replacementAllowed(origin: .automatic, autoUpgrade: true, lateArrival: false))
        XCTAssertFalse(Policy.replacementAllowed(origin: .manual, autoUpgrade: true, lateArrival: false))
    }

    func testReplacementRulesForLateArrivals() {
        XCTAssertTrue(Policy.replacementAllowed(origin: .none, autoUpgrade: false, lateArrival: true))
        XCTAssertFalse(Policy.replacementAllowed(origin: .playerDefault, autoUpgrade: true, lateArrival: true))
        XCTAssertFalse(Policy.replacementAllowed(origin: .automatic, autoUpgrade: false, lateArrival: true))
        XCTAssertTrue(Policy.replacementAllowed(origin: .automatic, autoUpgrade: true, lateArrival: true))
        XCTAssertFalse(Policy.replacementAllowed(origin: .manual, autoUpgrade: true, lateArrival: true))
    }

    func testAutoUpgradeReplacesChosenEmbeddedOnlyWhenEnabled() {
        let tracks = [embedded(1, "en", title: "Full"), external(2, "en", title: "Downloaded", level: .high)]
        XCTAssertNil(Policy.trackToAutoSelect(among: tracks, context: context(.automatic, autoUpgrade: false)))
        XCTAssertEqual(Policy.trackToAutoSelect(among: tracks, context: context(.automatic, autoUpgrade: true))?.id, 2)
        // With the embedded preference on, the embedded track stays the desired one, so the external track does not replace it.
        XCTAssertEqual(Policy.trackToAutoSelect(among: tracks, context: context(.automatic, preferEmbedded: true, autoUpgrade: true))?.id, 1)
    }

    func testManualChoiceIsNeverReplaced() {
        let tracks = [embedded(1, "en"), external(2, "en", level: .high)]
        XCTAssertNil(Policy.trackToAutoSelect(among: tracks, context: context(.manual, autoUpgrade: true)))
    }

    func testExternalArrivalIsVetoedWhenEmbeddedIsPreferred() {
        let existing = [embedded(1, "en")]
        XCTAssertFalse(Policy.allowsExternalArrival(existing: existing, lateArrival: false, context: context(preferEmbedded: true)))
        XCTAssertTrue(Policy.allowsExternalArrival(existing: existing, lateArrival: false, context: context(preferEmbedded: false)))
    }

    func testLateExternalArrivalNeedsNothingOrAutomaticUpgrade() {
        let existing = [embedded(1, "en")]
        XCTAssertTrue(Policy.allowsExternalArrival(existing: existing, lateArrival: true, context: context(.none)))
        XCTAssertFalse(Policy.allowsExternalArrival(existing: existing, lateArrival: true, context: context(.playerDefault, autoUpgrade: true)))
        XCTAssertTrue(Policy.allowsExternalArrival(existing: existing, lateArrival: true, context: context(.automatic, autoUpgrade: true)))
        XCTAssertFalse(Policy.allowsExternalArrival(existing: existing, lateArrival: true, context: context(.automatic, autoUpgrade: false)))
    }

    func testSuppressedBlocksEverySelection() {
        let tracks = [embedded(1, "en"), external(2, "en", level: .high)]
        XCTAssertNil(Policy.trackToAutoSelect(among: tracks, context: context(suppressed: true)))
        XCTAssertFalse(Policy.allowsExternalArrival(existing: tracks, lateArrival: false, context: context(suppressed: true)))
    }

    // MARK: Pre-playback choice

    func testPreselectDefaultsToBestCandidateOrOff() {
        XCTAssertEqual(Policy.preselectDefault(best: nil), .off)
        XCTAssertEqual(Policy.preselectDefault(best: embedded(9, "en")), .track(id: 9))
        XCTAssertTrue(Policy.automaticSelectionSuppressed(by: .off))
        XCTAssertFalse(Policy.automaticSelectionSuppressed(by: nil))
    }

    func testPreselectGateMatchesDesktopConditions() {
        func applies(enabled: Bool = true, isDownload: Bool = false, inSession: Bool = false, autoFired: Bool = false, isLive: Bool = false, metaID: String? = "tt0111161", mediaType: String = "movie") -> Bool {
            Policy.preselectApplies(enabled: enabled, isDownload: isDownload, inSession: inSession, autoFired: autoFired, isLive: isLive, metaID: metaID, mediaType: mediaType)
        }
        XCTAssertTrue(applies())
        XCTAssertTrue(applies(metaID: "kitsu:1", mediaType: "anime"))
        XCTAssertTrue(applies(mediaType: "series"))
        XCTAssertFalse(applies(enabled: false))
        XCTAssertFalse(applies(isDownload: true))
        XCTAssertFalse(applies(inSession: true))
        XCTAssertFalse(applies(autoFired: true))
        XCTAssertFalse(applies(isLive: true))
        XCTAssertFalse(applies(metaID: "iptv:channel"))
        XCTAssertFalse(applies(mediaType: "music"))
    }

    // MARK: Secondary line size

    func testSecondaryScaleDefaultsAndClamps() {
        XCTAssertEqual(Policy.secondaryScale(nil), 0.85, accuracy: 1e-9)
        XCTAssertEqual(Policy.secondaryScale(Double.nan), 0.85, accuracy: 1e-9)
        XCTAssertEqual(Policy.secondaryScale(0.1), 0.4, accuracy: 1e-9)
        XCTAssertEqual(Policy.secondaryScale(2.0), 1.4, accuracy: 1e-9)
        XCTAssertEqual(Policy.secondaryScale(1.0), 1.0, accuracy: 1e-9)
    }

    // MARK: ASS size normalisation

    private let assSample = [
        "[Script Info]",
        "PlayResX: 1280",
        "PlayResY: 720",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour",
        "Style: Default,Arial,36,&H00FFFFFF",
        "Style: Sign,Arial,60,&H00FFFFFF",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
        "Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Hello {\\i1}there{\\i0}",
        "Dialogue: 0,0:00:01.00,0:00:02.00,Sign,,0,0,0,,{\\pos(10,10)}Sign",
        "Dialogue: 0,0:00:03.00,0:00:04.00,Default,,0,0,0,,Second line\\NX",
        "Dialogue: 0,0:00:05.00,0:00:06.00,Sign,,0,0,0,,{\\pos(20,20)}Sign",
    ].joined(separator: "\n")

    func testBaseFactorUsesDominantNonSignStyle() {
        // PlayResY 720 and the Default style at 36: factor = 720 / (720 * 36). Sign lines with \pos are ignored, so Sign (60) does not win.
        let factor = AssSizeNormalization.baseFactor(assText: assSample)
        XCTAssertNotNil(factor)
        XCTAssertEqual(factor ?? -1, 1.0 / 36.0, accuracy: 1e-9)
        XCTAssertEqual(AssSizeNormalization.scale(baseFactor: 1.0 / 36.0, targetFontSize: 32), 32.0 / 36.0, accuracy: 1e-9)
    }

    func testPlayResXOf1280MapsToHeight1024() {
        let text = [
            "[Script Info]", "PlayResX: 1280",
            "[V4+ Styles]", "Format: Name, Fontsize", "Style: Default,32",
            "[Events]", "Format: Layer, Start, End, Style, Text", "Dialogue: 0,0:00:01.00,0:00:02.00,Default,Hi",
        ].joined(separator: "\n")
        // 1024 / (720 * 32) = 2 / 45.
        XCTAssertEqual(AssSizeNormalization.baseFactor(assText: text) ?? -1, 2.0 / 45.0, accuracy: 1e-9)
    }

    func testOtherPlayResXUsesThreeQuartersHeight() {
        let text = [
            "[Script Info]", "PlayResX: 1920",
            "[V4+ Styles]", "Format: Name, Fontsize", "Style: Default,36",
            "[Events]", "Format: Layer, Start, End, Style, Text", "Dialogue: 0,0:00:01.00,0:00:02.00,Default,Hi",
        ].joined(separator: "\n")
        // 1440 / (720 * 36) = 1 / 18.
        XCTAssertEqual(AssSizeNormalization.baseFactor(assText: text) ?? -1, 1.0 / 18.0, accuracy: 1e-9)
    }

    func testMissingPlayResUsesHeight288() {
        let text = [
            "[V4+ Styles]", "Format: Name, Fontsize", "Style: Default,18",
            "[Events]", "Format: Layer, Start, End, Style, Text", "Dialogue: 0,0:00:01.00,0:00:02.00,Default,Hi",
        ].joined(separator: "\n")
        // 288 / (720 * 18) = 1 / 45.
        XCTAssertEqual(AssSizeNormalization.baseFactor(assText: text) ?? -1, 1.0 / 45.0, accuracy: 1e-9)
    }

    func testStyleOutsideDesktopFractionRangeIsNotMeasured() {
        let text = [
            "[Script Info]", "PlayResY: 288",
            "[V4+ Styles]", "Format: Name, Fontsize", "Style: Default,100",
            "[Events]", "Format: Layer, Start, End, Style, Text", "Dialogue: 0,0:00:01.00,0:00:02.00,Default,Hi",
        ].joined(separator: "\n")
        // 100 / 288 is above the 0.22 limit.
        XCTAssertNil(AssSizeNormalization.baseFactor(assText: text))
        XCTAssertNil(AssSizeNormalization.baseFactor(assText: "[Script Info]\nPlayResY: 720"))
    }

    func testScaleIsClampedToDesktopRange() {
        XCTAssertEqual(AssSizeNormalization.scale(baseFactor: 0.01, targetFontSize: 32), 0.32, accuracy: 1e-9)
        XCTAssertEqual(AssSizeNormalization.scale(baseFactor: 1, targetFontSize: 1000), 6, accuracy: 1e-9)
        XCTAssertEqual(AssSizeNormalization.scale(baseFactor: 0.001, targetFontSize: 32), 0.2, accuracy: 1e-9)
    }

    func testNormalisationAppliesOnlyToAssWithKeepOrResizeOverride() {
        XCTAssertTrue(AssSizeNormalization.isActive(normalizeSize: true, assOverride: "no", selectedIsASS: true))
        XCTAssertTrue(AssSizeNormalization.isActive(normalizeSize: true, assOverride: "scale", selectedIsASS: true))
        XCTAssertFalse(AssSizeNormalization.isActive(normalizeSize: true, assOverride: "force", selectedIsASS: true))
        XCTAssertFalse(AssSizeNormalization.isActive(normalizeSize: true, assOverride: "no", selectedIsASS: false))
        XCTAssertFalse(AssSizeNormalization.isActive(normalizeSize: false, assOverride: "no", selectedIsASS: true))
        XCTAssertEqual(AssSizeNormalization.mpvSubScale(active: true, baseFactor: 1.0 / 36.0, targetFontSize: 32) ?? -1, 32.0 / 36.0, accuracy: 1e-9)
        XCTAssertNil(AssSizeNormalization.mpvSubScale(active: false, baseFactor: 1.0 / 36.0, targetFontSize: 32))
    }

    func testAssTrackDetectionUsesCodecOrFileExtension() {
        XCTAssertTrue(AssSizeNormalization.isASSTrack(codec: "ass", title: ""))
        XCTAssertTrue(AssSizeNormalization.isASSTrack(codec: "", title: "Signs.ASS"))
        XCTAssertFalse(AssSizeNormalization.isASSTrack(codec: "subrip", title: "episode.srt"))
        XCTAssertFalse(AssSizeNormalization.isASSTrack(codec: "hdmv_pgs", title: ""))
    }

    // MARK: Player track adapter

    func testPlayerTrackAdapterMapsRuleInputs() {
        let track = PlayerState.Track(id: 3, type: "sub", label: "Commentary en ass", selected: false, language: "en", title: "Commentary", external: true, defaultTrack: true)
        let candidate = track.subtitleSelectionCandidate(externalPrepared: false)
        XCTAssertEqual(candidate.id, 3)
        XCTAssertEqual(candidate.language, "en")
        XCTAssertEqual(candidate.title, "Commentary")
        XCTAssertTrue(candidate.external)
        XCTAssertTrue(candidate.isDefault)
        XCTAssertFalse(candidate.prepared)
        XCTAssertFalse(Policy.isAutoSelectable(candidate))
        XCTAssertTrue(Policy.isAutoSelectable(track.subtitleSelectionCandidate()))
    }

    func testSubtitleCandidatesKeepOnlyTextSubtitleTracks() {
        let audio = PlayerState.Track(id: 1, type: "audio", label: "", selected: false)
        let subtitle = PlayerState.Track(id: 2, type: "sub", label: "", selected: false, language: "en")
        XCTAssertEqual([audio, subtitle].subtitleSelectionCandidates.map { $0.id }, [2])
    }
}
