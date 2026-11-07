import XCTest
@testable import Harbor

/// Desktop's stream quality rules (`components/format-badge.tsx`, `lib/player/resolution-label.ts`, `quality-badge.tsx`),
/// through the pure policy in `Services/QualityBadgePolicy.swift`. No network.
final class QualityBadgePolicyTests: XCTestCase {
    func testStyleDefaultsToBarAndOnlyExactChipsReadsAsChips() {
        XCTAssertEqual(QualityBadgeStyle.restored(nil), .bar)
        XCTAssertEqual(QualityBadgeStyle.restored("chips"), .chips)
        XCTAssertEqual(QualityBadgeStyle.restored("Chips"), .bar)
        XCTAssertEqual(QualityBadgeStyle.restored("bogus"), .bar)
    }

    func testPickerChipsNeedTheSettingAndAKind() {
        XCTAssertFalse(QualityBadgePolicy.showsPickerChips(false, kinds: ["1080p"]))
        XCTAssertFalse(QualityBadgePolicy.showsPickerChips(true, kinds: []))
        XCTAssertTrue(QualityBadgePolicy.showsPickerChips(true, kinds: ["1080p"]))
    }

    func testResolutionLabelFollowsDesktopTiers() {
        XCTAssertNil(QualityBadgePolicy.resolutionLabel(width: 0, height: 0))
        XCTAssertEqual(QualityBadgePolicy.resolutionLabel(width: 3840, height: 1600), "4K")
        XCTAssertEqual(QualityBadgePolicy.resolutionLabel(width: 2560, height: 1080), "1440p")
        XCTAssertEqual(QualityBadgePolicy.resolutionLabel(width: 1920, height: 800), "1080p")
        XCTAssertEqual(QualityBadgePolicy.resolutionLabel(width: 1280, height: 534), "720p")
        XCTAssertEqual(QualityBadgePolicy.resolutionLabel(width: 854, height: 360), "480p")
        XCTAssertEqual(QualityBadgePolicy.resolutionLabel(width: 640, height: 360), "SD")
        XCTAssertEqual(QualityBadgePolicy.resolutionLabel(width: -1, height: 1080), "1080p")
    }

    func testHDRLabelFromGamma() {
        XCTAssertEqual(QualityBadgePolicy.hdrLabel(gamma: "pq"), "HDR")
        XCTAssertEqual(QualityBadgePolicy.hdrLabel(gamma: "hlg"), "HDR")
        XCTAssertEqual(QualityBadgePolicy.hdrLabel(gamma: "pq", formats: ["Dolby Vision"]), "DV")
        XCTAssertEqual(QualityBadgePolicy.hdrLabel(gamma: "pq", formats: ["HDR10+"]), "HDR10+")
        XCTAssertNil(QualityBadgePolicy.hdrLabel(gamma: "bt.1886", formats: ["DV"]))
    }

    func testHDRLabelFromFormatNamesWhenGammaIsUnknown() {
        XCTAssertEqual(QualityBadgePolicy.hdrLabel(gamma: nil, formats: ["Dolby Vision"]), "DV")
        XCTAssertEqual(QualityBadgePolicy.hdrLabel(gamma: "", formats: ["HDR10"]), "HDR")
        XCTAssertEqual(QualityBadgePolicy.hdrLabel(gamma: nil, formats: ["Movie.DOVI.x265"]), "DV")
        XCTAssertNil(QualityBadgePolicy.hdrLabel(gamma: nil, formats: [nil, ""]))
        XCTAssertNil(QualityBadgePolicy.hdrLabel(gamma: nil, formats: ["WEB-DL 1080p"]))
    }

    func testInfoLabelsKeepResolutionThenHDR() {
        XCTAssertEqual(QualityBadgePolicy.infoLabels(width: 1920, height: 1080, gamma: "pq"), ["1080p", "HDR"])
        XCTAssertEqual(QualityBadgePolicy.infoLabels(width: 3840, height: 2160, gamma: "bt.1886"), ["4K"])
        XCTAssertEqual(QualityBadgePolicy.infoLabels(width: 0, height: 0, gamma: nil), [])
    }

    func testHighlightedLabelsAreTheGoldSet() {
        XCTAssertTrue(QualityBadgePolicy.isHighlighted("HDR"))
        XCTAssertTrue(QualityBadgePolicy.isHighlighted("DV"))
        XCTAssertFalse(QualityBadgePolicy.isHighlighted("1080p"))
    }

    func testQualityTextNeedsTheSettingAndAQualityString() {
        XCTAssertTrue(QualityBadgePolicy.showsQualityText(showQualityInfo: true, quality: "1080p WEB-DL"))
        XCTAssertFalse(QualityBadgePolicy.showsQualityText(showQualityInfo: false, quality: "1080p WEB-DL"))
        XCTAssertFalse(QualityBadgePolicy.showsQualityText(showQualityInfo: true, quality: nil))
        XCTAssertFalse(QualityBadgePolicy.showsQualityText(showQualityInfo: true, quality: ""))
    }
}
