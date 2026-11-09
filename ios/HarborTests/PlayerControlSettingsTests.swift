import XCTest
@testable import Harbor

/// Desktop's short seek steps, "Ask before leaving" and maximum volume boost (`seek-step.ts`, `request-player-close.ts`,
/// `audio-tab.tsx`).
final class PlayerControlSettingsTests: XCTestCase {
    func testPlayerEpisodePanelHonorsInstantPlayWhileTransportKeepsPlaying() {
        XCTAssertFalse(PlayerEpisodeSelection.panel.playsImmediately(instantPlay: false))
        XCTAssertTrue(PlayerEpisodeSelection.panel.playsImmediately(instantPlay: true))
        XCTAssertTrue(PlayerEpisodeSelection.transport.playsImmediately(instantPlay: false))
        XCTAssertTrue(PlayerEpisodeSelection.transport.playsImmediately(instantPlay: true))
    }

    @MainActor func testEpisodePickerWaitsForTheRequestedProviderEpisode() {
        let media = Media(id: "tt4644488", type: "series", name: "Owned fixture")
        let model = DetailModel(media, service: HarborService())
        let playing = Episode(id: "tt4644488:5:23", season: 5, episode: 23)
        let next = Episode(id: "tt4644488:5:24", season: 5, episode: 24)
        XCTAssertFalse(model.offersBelong(to: playing))
        model.selectedEpisode = playing
        XCTAssertFalse(model.offersBelong(to: next))
        model.selectedEpisode = next
        XCTAssertTrue(model.offersBelong(to: next))
    }

    func testShortSeekKeysUseTheirOwnStepsAndLeaveTheOthersAlone() {
        XCTAssertEqual(PlayerShortcut.seekBackShort.seekSeconds(back: 15, forward: 20, shortBack: 1, shortForward: 90), -1)
        XCTAssertEqual(PlayerShortcut.seekForwardShort.seekSeconds(back: 15, forward: 20, shortBack: 1, shortForward: 90), 90)
        XCTAssertEqual(PlayerShortcut.seekBack.seekSeconds(back: 15, forward: 20, shortBack: 1, shortForward: 90), -15)
        XCTAssertEqual(PlayerShortcut.seekForward.seekSeconds(back: 15, forward: 20, shortBack: 1, shortForward: 90), 20)
        XCTAssertEqual(PlayerShortcut.seekBack30.seekSeconds(back: 15, forward: 20, shortBack: 1, shortForward: 90), -30)
        XCTAssertNil(PlayerShortcut.playPause.seekSeconds(back: 15, forward: 20, shortBack: 1, shortForward: 90))
        XCTAssertEqual(PlayerShortcut.seekBackShort.modifiers, .shift); XCTAssertEqual(PlayerShortcut.seekForwardShort.modifiers, .shift)
    }

    func testSeekStepsAreDesktopsEightChoices() {
        XCTAssertEqual(SeekSteps.options, [1, 3, 5, 10, 15, 30, 60, 90])
        XCTAssertEqual(SeekSteps.sanitized(3, fallback: 10), 3); XCTAssertEqual(SeekSteps.sanitized(7, fallback: 10), 10, "A value outside the list falls back")
        XCTAssertEqual(SeekSteps.choices(including: 10), SeekSteps.options)
        XCTAssertEqual(SeekSteps.choices(including: 7), [1, 3, 5, 7, 10, 15, 30, 60, 90], "A saved value outside the list stays visible")
    }

    func testTheNewOptionsStartAtDesktopsDefaultsAndOldSavedOptionsStillDecode() throws {
        let options = PlaybackOptions()
        XCTAssertEqual(options.seekBackShortSeconds, 3); XCTAssertEqual(options.seekForwardShortSeconds, 3)
        XCTAssertTrue(options.confirmLeave); XCTAssertEqual(options.volumeBoostMax, 2)
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any])
        for key in ["seekBackShortSeconds", "seekForwardShortSeconds", "confirmLeave", "volumeBoostMax"] { saved[key] = nil }
        var merged = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaybackOptions())) as? [String: Any])
        merged.merge(saved) { _, kept in kept }
        let decoded = try JSONDecoder().decode(PlaybackOptions.self, from: JSONSerialization.data(withJSONObject: merged))
        XCTAssertEqual(decoded.seekBackShortSeconds, 3); XCTAssertTrue(decoded.confirmLeave); XCTAssertEqual(decoded.volumeBoostMax, 2)
    }

    func testTheVolumeCeilingFollowsTheBoostChoicesAndReachesMpv() {
        func value(_ name: String, _ options: PlaybackOptions) -> String? { options.mpvOptions.first { $0.0 == name }?.1 }
        var options = PlaybackOptions()
        XCTAssertEqual(PlaybackOptions.volumeBoostChoices, [1, 1.5, 2, 3, 4, 6])
        XCTAssertEqual(options.volumeCeiling, 200); XCTAssertEqual(value("volume-max", options), "200")
        options.volumeBoostMax = 1.5; XCTAssertEqual(value("volume-max", options), "150")
        options.volumeBoostMax = 6; XCTAssertEqual(value("volume-max", options), "600")
        options.volumeBoostMax = 5; XCTAssertEqual(options.volumeBoostLimit, 2, "A boost Desktop does not offer falls back to 200 percent"); XCTAssertEqual(value("volume-max", options), "200")
        options.volumeBoostMax = 1; options.volume = 180
        XCTAssertEqual(value("volume", options), "100.0", "The volume never starts above the ceiling"); XCTAssertEqual(value("volume-max", options), "100")
        options.volumeBoostMax = 3; options.volume = 180; XCTAssertEqual(value("volume", options), "180.0")
        XCTAssertEqual(options.mpvOptions.first?.0, "volume-max", "The ceiling is set before the volume")
    }
}
