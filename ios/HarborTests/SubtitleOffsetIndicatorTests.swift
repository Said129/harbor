import SwiftUI
import XCTest
@testable import Harbor

/// Desktop's subtitle sync indicator (`lib/player/subtitle-offset.ts`).
final class SubtitleOffsetIndicatorTests: XCTestCase {
    func testTheDelayIsShownInWholeMillisecondsWithAPlusForPositiveValues() {
        XCTAssertEqual(SubtitleOffset.format(0.5), "+500 ms"); XCTAssertEqual(SubtitleOffset.format(-0.25), "-250 ms")
        XCTAssertEqual(SubtitleOffset.format(0), "0 ms"); XCTAssertEqual(SubtitleOffset.format(0.1 + 0.2), "+300 ms", "Floating point noise is rounded away")
        XCTAssertEqual(SubtitleOffset.format(1.2346), "+1235 ms"); XCTAssertEqual(SubtitleOffset.format(-1.2346), "-1235 ms")
        XCTAssertEqual(SubtitleOffset.format(0.0625), "+63 ms"); XCTAssertEqual(SubtitleOffset.format(-0.0625), "-62 ms", "Halves round up, as JavaScript's Math.round does")
        XCTAssertEqual(SubtitleOffset.format(.nan), "0 ms"); XCTAssertEqual(SubtitleOffset.format(.infinity), "0 ms")
    }

    func testPositionsAndSizesFallBackLikeDesktop() {
        for position in SubtitleOffsetPosition.allCases { XCTAssertEqual(SubtitleOffsetPosition.sanitized(position.rawValue), position) }
        XCTAssertEqual(SubtitleOffsetPosition.sanitized("nonsense"), .bottom); XCTAssertEqual(SubtitleOffsetPosition.sanitized(""), .bottom)
        XCTAssertEqual(SubtitleOffsetPosition.allCases.map(\.rawValue), ["top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right"])
        XCTAssertEqual(SubtitleOffsetPosition.allCases.filter(\.isTop).count, 3); XCTAssertEqual(SubtitleOffsetPosition.allCases.filter(\.isBottom).count, 3)
        XCTAssertEqual(SubtitleOffsetSize.sanitized("small"), .small); XCTAssertEqual(SubtitleOffsetSize.sanitized("large"), .large)
        XCTAssertEqual(SubtitleOffsetSize.sanitized("medium"), .medium); XCTAssertEqual(SubtitleOffsetSize.sanitized("huge"), .medium)
        XCTAssertEqual(SubtitleOffsetSize.allCases.map(\.label), ["Smaller", "Default", "Larger"])
    }

    func testTheIndicatorIsOnAtTheBottomByDefaultAndSavedOptionsStillDecode() throws {
        let options = PlaybackOptions()
        XCTAssertTrue(options.subOffsetIndicator); XCTAssertEqual(options.subOffsetPosition, "bottom"); XCTAssertEqual(options.subOffsetSize, "medium")
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any])
        for key in ["subOffsetIndicator", "subOffsetPosition", "subOffsetSize"] { saved[key] = nil }
        var merged = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaybackOptions())) as? [String: Any])
        merged.merge(saved) { _, kept in kept }
        XCTAssertEqual(try JSONDecoder().decode(PlaybackOptions.self, from: JSONSerialization.data(withJSONObject: merged)).subOffsetPosition, "bottom")
    }

    func testShiftHalvesTheSubtitleDelayStep() {
        XCTAssertEqual(PlayerShortcut.subtitleDelayDownFine.modifiers, .shift); XCTAssertEqual(PlayerShortcut.subtitleDelayUpFine.modifiers, .shift)
        XCTAssertEqual(PlayerShortcut.subtitleDelayDown.modifiers, []); XCTAssertEqual(PlayerShortcut.subtitleDelayDownFine.key, PlayerShortcut.subtitleDelayDown.key)
        XCTAssertEqual(PlayerShortcut.subtitleDelayUpFine.key, PlayerShortcut.subtitleDelayUp.key)
    }
}
