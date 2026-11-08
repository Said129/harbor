import XCTest
@testable import Harbor

/// The subtitle and audio selection settings wired into the player (`SubtitleSelectionWiring`), checked without mpv or the network.
final class WireSubsTests: XCTestCase {
    private typealias Wiring = SubtitleSelectionWiring

    private func embedded(_ id: Int, _ language: String, title: String = "", isDefault: Bool = false) -> SubtitleSelectionCandidate {
        SubtitleSelectionCandidate(id: id, language: language, title: title, isDefault: isDefault)
    }

    private func external(_ id: Int, _ language: String, title: String = "", level: SubtitleMatchLevel = .high) -> SubtitleSelectionCandidate {
        SubtitleSelectionCandidate(id: id, language: language, title: title, external: true, matchLevel: level)
    }

    /// The defaults match the app: block words `["commentary"]`, every other setting off.
    private func context(_ origin: SubtitleSelectionOrigin = .playerDefault, languages: [String] = ["en"], preferEmbedded: Bool = false, autoUpgrade: Bool = false, blockWords: [String] = ["commentary"], suppressed: Bool = false) -> SubtitleAutoSelectionContext {
        SubtitleAutoSelectionContext(origin: origin, languages: languages, preferEmbedded: preferEmbedded, autoUpgrade: autoUpgrade, blockWords: blockWords, suppressed: suppressed)
    }

    // MARK: Adapter

    func testAudioAdapterKeepsOnlyAudioTracks() {
        let tracks = [
            PlayerState.Track(id: 1, type: "video", label: "", selected: true),
            PlayerState.Track(id: 2, type: "audio", label: "", selected: true, language: "en"),
            PlayerState.Track(id: 3, type: "sub", label: "", selected: false, language: "en"),
        ]
        XCTAssertEqual(tracks.audioSelectionCandidates.map { $0.id }, [2])
        XCTAssertEqual(tracks.audioSelectionCandidates.first?.language, "en")
    }

    // MARK: trackBlockWords on subtitles

    func testBlockedSubtitleIsReplacedByAllowedTrack() {
        let candidates = [embedded(1, "en", title: "English Commentary", isDefault: true), embedded(2, "en", title: "English")]
        XCTAssertEqual(Wiring.subtitleChoice(candidates: candidates, previous: candidates, currentID: 1, context: context()), 2)
    }

    func testBlockedSubtitleStaysWhenNoAllowedAlternativeInLanguage() {
        let candidates = [embedded(1, "en", title: "Commentary"), embedded(2, "fr", title: "Francais")]
        XCTAssertNil(Wiring.subtitleChoice(candidates: candidates, previous: candidates, currentID: 1, context: context()))
    }

    func testManualPickOfBlockedSubtitleIsKept() {
        let candidates = [embedded(1, "en", title: "Commentary"), embedded(2, "en", title: "English")]
        XCTAssertNil(Wiring.subtitleChoice(candidates: candidates, previous: candidates, currentID: 1, context: context(.manual)))
    }

    func testEmptyBlockWordsNeverMoveAwayFromATrack() {
        let candidates = [embedded(1, "en", title: "Commentary"), embedded(2, "en", title: "English")]
        XCTAssertNil(Wiring.subtitleChoice(candidates: candidates, previous: candidates, currentID: 1, context: context(blockWords: [])))
    }

    func testSettingsOffKeepsMpvChoiceWhenNothingIsBlocked() {
        let candidates = [embedded(1, "en", title: "Full"), embedded(2, "en", title: "Other", isDefault: true)]
        XCTAssertNil(Wiring.subtitleChoice(candidates: candidates, previous: candidates, currentID: 1, context: context(blockWords: [])))
        XCTAssertNil(Wiring.subtitleChoice(candidates: candidates, previous: candidates, currentID: 1, context: context()))
    }

    func testNothingIsSelectedWhenSubtitlesAreOffOrLanguageIsEmpty() {
        let candidates = [embedded(1, "en", title: "Commentary"), embedded(2, "en", title: "English")]
        XCTAssertNil(Wiring.subtitleChoice(candidates: candidates, previous: candidates, currentID: 1, context: context(suppressed: true)))
        XCTAssertNil(Wiring.subtitleChoice(candidates: candidates, previous: candidates, currentID: 1, context: context(languages: [])))
    }

    // MARK: preferEmbeddedSubs

    func testPreferEmbeddedChoosesEmbeddedOverExternal() {
        let candidates = [external(2, "en", title: "Downloaded"), embedded(1, "en")]
        XCTAssertEqual(Wiring.subtitleChoice(candidates: candidates, previous: candidates, currentID: 2, context: context(preferEmbedded: true, blockWords: [])), 1)
    }

    func testPreferEmbeddedOffKeepsExternalChoice() {
        let candidates = [external(2, "en", title: "Downloaded"), embedded(1, "en")]
        XCTAssertNil(Wiring.subtitleChoice(candidates: candidates, previous: candidates, currentID: 2, context: context(preferEmbedded: false, blockWords: [])))
    }

    // MARK: subtitleAutoUpgrade

    func testAutoUpgradeReplacesAutomaticChoiceOnLateArrival() {
        let previous = [embedded(1, "en", title: "Full")]
        let candidates = previous + [external(2, "en", title: "Downloaded")]
        XCTAssertEqual(Wiring.subtitleChoice(candidates: candidates, previous: previous, currentID: 1, context: context(.automatic, autoUpgrade: true, blockWords: [])), 2)
    }

    func testAutoUpgradeOffKeepsAutomaticChoiceOnLateArrival() {
        let previous = [embedded(1, "en", title: "Full")]
        let candidates = previous + [external(2, "en", title: "Downloaded")]
        XCTAssertNil(Wiring.subtitleChoice(candidates: candidates, previous: previous, currentID: 1, context: context(.automatic, autoUpgrade: false, blockWords: [])))
    }

    func testAutoUpgradeNeverReplacesPlayerDefaultOnLateArrival() {
        let previous = [embedded(1, "en", title: "Full")]
        let candidates = previous + [external(2, "en", title: "Downloaded")]
        XCTAssertNil(Wiring.subtitleChoice(candidates: candidates, previous: previous, currentID: 1, context: context(.playerDefault, autoUpgrade: true, blockWords: [])))
    }

    func testAutoUpgradeNeverReplacesManualChoice() {
        let previous = [embedded(1, "en", title: "Full")]
        let candidates = previous + [external(2, "en", title: "Downloaded")]
        XCTAssertNil(Wiring.subtitleChoice(candidates: candidates, previous: previous, currentID: 1, context: context(.manual, autoUpgrade: true, blockWords: [])))
    }

    // MARK: trackBlockWords on audio

    func testBlockedAudioIsSwitchedToAllowedTrackInLanguage() {
        let tracks = [
            PlayerState.Track(id: 1, type: "audio", label: "", selected: true, language: "en", title: "Commentary", defaultTrack: true),
            PlayerState.Track(id: 2, type: "audio", label: "", selected: false, language: "en", title: "Main"),
        ]
        XCTAssertEqual(Wiring.audioChoice(candidates: tracks.audioSelectionCandidates, currentID: 1, languages: ["en"], blockWords: ["commentary"], userPicked: false), 2)
    }

    func testUserPickedAudioIsNeverChanged() {
        let tracks = [
            PlayerState.Track(id: 1, type: "audio", label: "", selected: true, language: "en", title: "Commentary"),
            PlayerState.Track(id: 2, type: "audio", label: "", selected: false, language: "en", title: "Main"),
        ]
        XCTAssertNil(Wiring.audioChoice(candidates: tracks.audioSelectionCandidates, currentID: 1, languages: ["en"], blockWords: ["commentary"], userPicked: true))
    }

    func testAudioIsUnchangedWhenCurrentTrackIsAllowedOrWordsEmpty() {
        let tracks = [
            PlayerState.Track(id: 1, type: "audio", label: "", selected: true, language: "en", title: "Commentary"),
            PlayerState.Track(id: 2, type: "audio", label: "", selected: false, language: "en", title: "Main"),
        ]
        XCTAssertNil(Wiring.audioChoice(candidates: tracks.audioSelectionCandidates, currentID: 2, languages: ["en"], blockWords: ["commentary"], userPicked: false))
        XCTAssertNil(Wiring.audioChoice(candidates: tracks.audioSelectionCandidates, currentID: 1, languages: ["en"], blockWords: [], userPicked: false))
    }

    func testAudioSkipsOtherLanguages() {
        let tracks = [
            PlayerState.Track(id: 1, type: "audio", label: "", selected: true, language: "en", title: "Commentary"),
            PlayerState.Track(id: 2, type: "audio", label: "", selected: false, language: "fr", title: "Main"),
        ]
        XCTAssertNil(Wiring.audioChoice(candidates: tracks.audioSelectionCandidates, currentID: 1, languages: ["en"], blockWords: ["commentary"], userPicked: false))
    }

    // MARK: subAssNormalizeSize

    private let assText = [
        "[Script Info]", "PlayResY: 720",
        "[V4+ Styles]", "Format: Name, Fontsize", "Style: Default,36",
        "[Events]", "Format: Layer, Start, End, Style, Text", "Dialogue: 0,0:00:01.00,0:00:02.00,Default,Hi",
    ].joined(separator: "\n")

    func testAssScaleAppliesOnlyWithSettingOnAssTrackAndText() {
        XCTAssertEqual(Wiring.assSubScale(normalizeSize: true, assOverride: "scale", selectedIsASS: true, assText: assText, targetFontSize: 32) ?? -1, 32.0 / 36.0, accuracy: 1e-9)
        XCTAssertEqual(Wiring.assSubScale(normalizeSize: true, assOverride: "no", selectedIsASS: true, assText: assText, targetFontSize: 32) ?? -1, 32.0 / 36.0, accuracy: 1e-9)
        XCTAssertNil(Wiring.assSubScale(normalizeSize: false, assOverride: "no", selectedIsASS: true, assText: assText, targetFontSize: 32))
        XCTAssertNil(Wiring.assSubScale(normalizeSize: true, assOverride: "force", selectedIsASS: true, assText: assText, targetFontSize: 32))
        XCTAssertNil(Wiring.assSubScale(normalizeSize: true, assOverride: "no", selectedIsASS: false, assText: assText, targetFontSize: 32))
        XCTAssertNil(Wiring.assSubScale(normalizeSize: true, assOverride: "no", selectedIsASS: true, assText: nil, targetFontSize: 32))
    }

    func testAssTrackDetectionUsesCodecOrFileName() {
        XCTAssertTrue(Wiring.isASSSelection(PlayerState.Track(id: 1, type: "sub", label: "", selected: true, codec: "ass")))
        XCTAssertTrue(Wiring.isASSSelection(PlayerState.Track(id: 2, type: "sub", label: "", selected: false, externalFilename: "/a/Signs.ASS")))
        XCTAssertFalse(Wiring.isASSSelection(PlayerState.Track(id: 3, type: "sub", label: "", selected: false, codec: "subrip", externalFilename: "/a/x.srt")))
    }

    func testLocalFileURLAcceptsPathsAndFileURLsOnly() {
        XCTAssertNil(Wiring.localFileURL(""))
        XCTAssertEqual(Wiring.localFileURL("/tmp/x.ass")?.isFileURL, true)
        XCTAssertEqual(Wiring.localFileURL("file:///tmp/x.ass")?.isFileURL, true)
        XCTAssertNil(Wiring.localFileURL("https://addon.example/subs/en.ass"))
    }

    func testASSOverrideIsScaleOnlyWhileNormalising() {
        XCTAssertEqual(Wiring.assOverride(scaled: true, userOverride: "no"), "scale")
        XCTAssertEqual(Wiring.assOverride(scaled: false, userOverride: "no"), "no")
        XCTAssertEqual(Wiring.assOverride(scaled: false, userOverride: "scale"), "scale")
    }
}
