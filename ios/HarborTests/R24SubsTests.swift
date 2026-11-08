import XCTest
@testable import Harbor

/// Subtitle look presets and the custom subtitle font rules, against Desktop 0.9.132: pure rules and a private UserDefaults suite, no network and no UI.
final class R24SubsTests: XCTestCase {
    private var suite = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suite = "R24SubsTests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite) ?? .standard
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testSnapshotOfDefaultOptionsMatchesDesktopDefaults() {
        XCTAssertEqual(SubtitleLookPresets.snapshot(PlaybackOptions()), SubtitleLookValues(
            subStyle: "shadow", subFontFamily: "inter", subFontSize: 32, subFontColor: "#FFFFFF", subBorderColor: "#000000",
            subBorderSize: 2, subMarginY: 12, subAlignX: "center", subAssOverride: "no", subBoxOpacity: 0.6,
            subBoxColor: "#000000", subOpacity: 1, subLineSpacing: 0))
    }

    func testSnapshotHasExactlyDesktopsThirteenFields() throws {
        let data = try JSONEncoder().encode(SubtitleLookPresets.snapshot(PlaybackOptions()))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), [
            "subStyle", "subFontFamily", "subFontSize", "subFontColor", "subBorderColor", "subBorderSize", "subMarginY",
            "subAlignX", "subAssOverride", "subBoxOpacity", "subBoxColor", "subOpacity", "subLineSpacing",
        ])
    }

    func testSnapshotIgnoresBoldAndLanguages() {
        var options = PlaybackOptions()
        let baseline = SubtitleLookPresets.snapshot(options)
        options.subtitleBold = true
        options.subtitleLanguage = "spa"
        XCTAssertEqual(SubtitleLookPresets.snapshot(options), baseline)
    }

    func testSeedsAreDesktopsThreeLooksInOrder() {
        XCTAssertEqual(SubtitleLookPresets.seeds.map(\.id), ["english", "foreign", "arabic"])
        XCTAssertEqual(SubtitleLookPresets.seeds.map(\.name), ["English", "Foreign", "Arabic"])
        XCTAssertEqual(SubtitleLookPresets.seeds[2].values.subFontFamily, "arabic")
        XCTAssertEqual(SubtitleLookPresets.seeds[2].values.subAssOverride, "force")
        XCTAssertEqual(SubtitleLookPresets.seeds[1].values.subMarginY, 14)
    }

    func testApplyWritesTheLookAndLeavesOtherOptionsAlone() {
        var options = PlaybackOptions()
        options.subtitleLanguage = "spa"
        options.subtitleBold = true
        SubtitleLookPresets.apply(SubtitleLookPresets.seeds[2].values, to: &options)
        XCTAssertEqual(options.subtitleFont, "arabic")
        XCTAssertEqual(options.subtitleStyle, "outline")
        XCTAssertEqual(options.subtitleASS, "force")
        XCTAssertEqual(options.borderSize, 2)
        XCTAssertEqual(options.subtitlePosition, 86)
        XCTAssertEqual(options.subtitleLanguage, "spa")
        XCTAssertTrue(options.subtitleBold)
        XCTAssertTrue(SubtitleLookPresets.matches(options, SubtitleLookPresets.seeds[2]))
        XCTAssertFalse(SubtitleLookPresets.matches(options, SubtitleLookPresets.seeds[0]))
    }

    func testNamesAreTrimmedAndBlankNamesAreRejected() {
        XCTAssertEqual(SubtitleLookPresets.normalizedName("  Night  "), "Night")
        XCTAssertNil(SubtitleLookPresets.normalizedName("   "))
        XCTAssertNil(SubtitleLookPresets.normalizedName(""))
        XCTAssertNil(SubtitleLookPresets.adding(name: "  ", values: SubtitleLookPresets.seeds[0].values, to: SubtitleLookPresets.seeds))
    }

    func testIdentifiersFollowDesktopSlugAndCountRule() {
        XCTAssertEqual(SubtitleLookPresets.identifier(for: "My Night Look", existingCount: 3), "my-night-look-3")
        XCTAssertEqual(SubtitleLookPresets.identifier(for: "a  b", existingCount: 0), "a-b-0")
        XCTAssertEqual(SubtitleLookPresets.identifier(for: "abcdefghijklmnopqrstuvwxyz0123", existingCount: 1), "abcdefghijklmnopqrstuvwx-1")
        let added = SubtitleLookPresets.adding(name: "English", values: SubtitleLookPresets.seeds[0].values, to: SubtitleLookPresets.seeds)
        XCTAssertEqual(added?.last?.id, "english-3")
        XCTAssertEqual(added?.last?.name, "English")
    }

    func testSavedLooksLoadBackForTheSameProfileDefaults() {
        let store = SubtitleLookPresetStore(defaults: defaults)
        XCTAssertEqual(store.presets(), SubtitleLookPresets.seeds)
        let added = SubtitleLookPresets.adding(name: "Late night", values: SubtitleLookPresets.seeds[0].values, to: SubtitleLookPresets.seeds) ?? []
        XCTAssertTrue(store.save(added))
        XCTAssertEqual(SubtitleLookPresetStore(defaults: defaults).presets(), added)
        XCTAssertTrue(ProfileSettingsStore.keys.contains(SubtitleLookPresetStore.key))
    }

    func testMissingOrCorruptDataFallsBackToSeeds() {
        XCTAssertEqual(SubtitleLookPresetStore(defaults: defaults).presets(), SubtitleLookPresets.seeds)
        defaults.set(Data("not json".utf8), forKey: SubtitleLookPresetStore.key)
        XCTAssertEqual(SubtitleLookPresetStore(defaults: defaults).presets(), SubtitleLookPresets.seeds)
    }

    func testStoredEmptyListStaysEmpty() {
        let store = SubtitleLookPresetStore(defaults: defaults)
        XCTAssertTrue(store.save([]))
        XCTAssertEqual(store.presets(), [])
    }

    func testSavingKeepsOnlyTwelveLooks() {
        var list = SubtitleLookPresets.seeds
        while list.count < 15 {
            list = SubtitleLookPresets.adding(name: "Look \(list.count)", values: SubtitleLookPresets.seeds[0].values, to: list) ?? list
        }
        XCTAssertEqual(list.count, 15)
        XCTAssertEqual(SubtitleLookPresets.maximumCount, 12)
        let store = SubtitleLookPresetStore(defaults: defaults)
        XCTAssertTrue(store.save(list))
        XCTAssertEqual(store.presets().map(\.id), Array(list.prefix(12)).map(\.id))
    }

    func testDeleteRemovesOnlyTheChosenLook() {
        let removed = SubtitleLookPresets.removing(id: "foreign", from: SubtitleLookPresets.seeds)
        XCTAssertEqual(removed.map(\.id), ["english", "arabic"])
    }

    func testOverwriteReplacesValuesAndKeepsTheName() {
        var changed = PlaybackOptions()
        changed.subtitleSize = 50
        let overwritten = SubtitleLookPresets.overriding(id: "english", values: SubtitleLookPresets.snapshot(changed), in: SubtitleLookPresets.seeds)
        XCTAssertEqual(overwritten.count, 3)
        XCTAssertEqual(overwritten[0].name, "English")
        XCTAssertEqual(overwritten[0].values.subFontSize, 50)
        XCTAssertEqual(overwritten[1], SubtitleLookPresets.seeds[1])
    }

    func testCustomFontFormatsAreTheFourDesktopAccepts() {
        XCTAssertEqual(SubtitleCustomFontRules.format(forFileName: "Movie-Sans.TTF"), "truetype")
        XCTAssertEqual(SubtitleCustomFontRules.format(forFileName: "display.otf"), "opentype")
        XCTAssertEqual(SubtitleCustomFontRules.format(forFileName: "web.woff"), "woff")
        XCTAssertEqual(SubtitleCustomFontRules.format(forFileName: "web.WOFF2"), "woff2")
        XCTAssertNil(SubtitleCustomFontRules.format(forFileName: "collection.ttc"))
        XCTAssertNil(SubtitleCustomFontRules.format(forFileName: "font"))
        XCTAssertNil(SubtitleCustomFontRules.format(forFileName: "name."))
    }

    func testCustomFontSizeLimitIsThirtyTwoMegabytesInclusive() {
        XCTAssertTrue(SubtitleCustomFontRules.accepts(byteCount: 32 * 1024 * 1024))
        XCTAssertFalse(SubtitleCustomFontRules.accepts(byteCount: 32 * 1024 * 1024 + 1))
    }

    func testCustomFontDisplayNameFollowsDesktopPrettyName() {
        XCTAssertEqual(SubtitleCustomFontRules.displayName(forFileName: "my_cool-font  name.ttf"), "my cool font name")
        XCTAssertEqual(SubtitleCustomFontRules.displayName(forFileName: "plain"), "plain")
        XCTAssertEqual(SubtitleCustomFontRules.displayName(forFileName: "---.otf"), "Custom font")
        XCTAssertEqual(SubtitleCustomFontRules.displayName(forFileName: ".ttf"), "Custom font")
        XCTAssertEqual(SubtitleCustomFontRules.displayName(forFileName: String(repeating: "a", count: 40) + ".ttf"), String(repeating: "a", count: 36))
    }
}
