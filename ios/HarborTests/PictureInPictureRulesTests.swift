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

    func testSubtitlesStayOnInPictureInPictureByDefaultAndSavedOptionsStillDecode() throws {
        XCTAssertTrue(PlaybackOptions().subShowInPip)
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaybackOptions())) as? [String: Any])
        saved["subShowInPip"] = nil
        var merged = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaybackOptions())) as? [String: Any])
        merged.merge(saved) { _, kept in kept }
        XCTAssertTrue(try JSONDecoder().decode(PlaybackOptions.self, from: JSONSerialization.data(withJSONObject: merged)).subShowInPip)
    }
}
