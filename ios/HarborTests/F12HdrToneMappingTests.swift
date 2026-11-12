import XCTest
@testable import Harbor

final class F12HdrToneMappingTests: XCTestCase {
    func testCurvesListDesktopChoicesInDesktopOrder() {
        XCTAssertEqual(ToneMappingCurve.allCases.map { $0.rawValue }, ["", "bt.2390", "hable", "mobius", "reinhard", "spline"])
        XCTAssertEqual(ToneMappingCurve.allCases.map { $0.title }, [
            "Auto (recommended)", "Reference (bt.2390)", "Filmic (Hable)", "Balanced (Mobius)", "Soft (Reinhard)", "Modern (Spline)"
        ])
    }

    func testAutoAddsNoMpvOption() {
        XCTAssertTrue(PlayerToneMapping.mpvOptions(stored: nil).isEmpty)
        XCTAssertTrue(PlayerToneMapping.mpvOptions(stored: "").isEmpty)
        XCTAssertTrue(PlayerToneMapping.mpvLines(stored: "").isEmpty)
    }

    func testEveryCurveBecomesOneToneMappingOption() {
        for curve in ToneMappingCurve.allCases where curve != .auto {
            let options = PlayerToneMapping.mpvOptions(stored: curve.rawValue)
            XCTAssertEqual(options.count, 1, curve.rawValue)
            XCTAssertEqual(options.first?.0, "tone-mapping")
            XCTAssertEqual(options.first?.1, curve.rawValue)
        }
        XCTAssertEqual(PlayerToneMapping.mpvLines(stored: "hable"), ["tone-mapping=hable"])
    }

    func testUnknownStoredValueFallsBackToAutoInsteadOfReachingMpv() {
        XCTAssertEqual(PlayerToneMapping.curve("bt.2446a"), .auto)
        XCTAssertEqual(PlayerToneMapping.curve("HABLE"), .auto)
        XCTAssertEqual(PlayerToneMapping.curve("  "), .auto)
        XCTAssertTrue(PlayerToneMapping.mpvOptions(stored: "gamma").isEmpty)
    }

    func testChosenCurveOverridesTheHdrToSdrSplineWhenAppliedAfterIt() {
        var applied: [String: String] = [:]
        for (name, value) in UISettingsPolicy.hdrToSdrMpvOptions(true) { applied[name] = value }
        XCTAssertEqual(applied["tone-mapping"], "spline")
        for (name, value) in PlayerToneMapping.mpvOptions(stored: "mobius") { applied[name] = value }
        XCTAssertEqual(applied["tone-mapping"], "mobius")
        var untouched: [String: String] = [:]
        for (name, value) in UISettingsPolicy.hdrToSdrMpvOptions(true) { untouched[name] = value }
        for (name, value) in PlayerToneMapping.mpvOptions(stored: "") { untouched[name] = value }
        XCTAssertEqual(untouched["tone-mapping"], "spline", "Auto keeps the curve the HDR-to-SDR block chose")
    }

    func testPreferenceKeyIsKeptPerProfile() {
        XCTAssertEqual(PlayerToneMapping.curveKey, "mpvToneMapping")
        XCTAssertTrue(ProfileSettingsStore.keys.contains(PlayerToneMapping.curveKey))
    }
}
