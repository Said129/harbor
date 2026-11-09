import XCTest
@testable import Harbor

/// Desktop's `subShowInPip` on iOS: subtitles are hidden only in the floating Picture in Picture window.
final class PictureInPictureRulesTests: XCTestCase {
    func testSubtitlesAreHiddenOnlyInTheFloatingWindowWhenTheSettingIsOff() {
        XCTAssertEqual(PictureInPictureRules.subtitleVisibility(inPictureInPicture: true, showSubtitlesInPip: false), "no")
        XCTAssertEqual(PictureInPictureRules.subtitleVisibility(inPictureInPicture: true, showSubtitlesInPip: true), "yes")
        XCTAssertEqual(PictureInPictureRules.subtitleVisibility(inPictureInPicture: false, showSubtitlesInPip: false), "yes")
        XCTAssertEqual(PictureInPictureRules.subtitleVisibility(inPictureInPicture: false, showSubtitlesInPip: true), "yes")
    }

    @MainActor func testSecondarySubtitleSizeAndPictureInPictureFallback() {
        XCTAssertEqual(SecondarySubtitleOverlay.scale(0.15), 0.4)
        XCTAssertEqual(SecondarySubtitleOverlay.scale(1.2), 1.2)
        XCTAssertEqual(SecondarySubtitleOverlay.scale(1.8), 1.4)
        XCTAssertEqual(SecondarySubtitleOverlay.scale(.nan), 0.85)
        XCTAssertEqual(PictureInPictureRules.subtitleVisibility(inPictureInPicture: false, showSubtitlesInPip: true, hasInlineOverlay: true), "no")
        XCTAssertEqual(PictureInPictureRules.subtitleVisibility(inPictureInPicture: true, showSubtitlesInPip: true, hasInlineOverlay: true), "yes")
        XCTAssertEqual(PictureInPictureRules.subtitleVisibility(inPictureInPicture: true, showSubtitlesInPip: false, hasInlineOverlay: true), "no")
    }

    func testSubtitlesStayOnInPictureInPictureByDefaultAndSavedOptionsStillDecode() throws {
        XCTAssertTrue(PlaybackOptions().subShowInPip)
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaybackOptions())) as? [String: Any])
        saved["subShowInPip"] = nil
        var merged = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaybackOptions())) as? [String: Any])
        merged.merge(saved) { _, kept in kept }
        XCTAssertTrue(try JSONDecoder().decode(PlaybackOptions.self, from: JSONSerialization.data(withJSONObject: merged)).subShowInPip)
    }
}
