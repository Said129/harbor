import XCTest
@testable import Harbor

/// Desktop's "Translate overviews" (`translateDescriptions`): `settings/language-panel/app-tab.tsx`, `providers/tmdb/tmdb-details.ts`.
final class OverviewTranslationPolicyTests: XCTestCase {
    func testEmptyAndEnglishLanguagesCountAsEnglish() {
        for language in ["", "  ", "en", "en-US", "EN-gb"] { XCTAssertTrue(OverviewTranslationPolicy.isEnglish(language), language) }
        for language in ["es-ES", "ja", "pt-BR", "zh-CN"] { XCTAssertFalse(OverviewTranslationPolicy.isEnglish(language), language) }
    }

    func testEnglishRecordIsOnlyRequestedWhenTheSettingIsOffAndTheLanguageIsNotEnglish() {
        XCTAssertFalse(OverviewTranslationPolicy.needsEnglish(translate: true, language: "es-ES"))
        XCTAssertTrue(OverviewTranslationPolicy.needsEnglish(translate: false, language: "es-ES"))
        XCTAssertFalse(OverviewTranslationPolicy.needsEnglish(translate: false, language: "en-US"))
        XCTAssertFalse(OverviewTranslationPolicy.needsEnglish(translate: false, language: ""))
    }

    func testLocalizedTextIsKeptWhileTheSettingIsOn() {
        XCTAssertEqual(OverviewTranslationPolicy.text(localized: "Sinopsis", english: "Plot", translate: true), "Sinopsis")
        XCTAssertNil(OverviewTranslationPolicy.text(localized: nil, english: "Plot", translate: true))
    }

    func testEnglishTextWinsWhileTheSettingIsOff() {
        XCTAssertEqual(OverviewTranslationPolicy.text(localized: "Sinopsis", english: "Plot", translate: false), "Plot")
    }

    func testLocalizedTextIsTheFallbackWhenThereIsNoEnglishText() {
        XCTAssertEqual(OverviewTranslationPolicy.text(localized: "Sinopsis", english: nil, translate: false), "Sinopsis")
        XCTAssertEqual(OverviewTranslationPolicy.text(localized: "Sinopsis", english: "", translate: false), "Sinopsis")
        XCTAssertEqual(OverviewTranslationPolicy.text(localized: "Sinopsis", english: " \n ", translate: false), "Sinopsis")
        XCTAssertNil(OverviewTranslationPolicy.text(localized: nil, english: nil, translate: false))
    }

    func testTheSettingDefaultsToOnInTheMetadataConfiguration() {
        XCTAssertTrue(MetadataConfiguration(tmdbKey: "k", region: "US", language: "es-ES", translateTitles: true).translateDescriptions)
    }

    func testTheCachedDetailKeyChangesWithTheSetting() throws {
        let media = Media(id: "tt0111161", type: "movie", name: "The Shawshank Redemption")
        var on = MetadataConfiguration(tmdbKey: "k", region: "US", language: "es-ES", translateTitles: true)
        var off = on
        on.translateDescriptions = true; off.translateDescriptions = false
        let first = try MediaMetadataStore.key(media, owner: "owner", addons: [], configuration: on)
        let second = try MediaMetadataStore.key(media, owner: "owner", addons: [], configuration: off)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, try MediaMetadataStore.key(media, owner: "owner", addons: [], configuration: on))
    }

    func testTheSettingTravelsWithTheProfile() {
        XCTAssertTrue(ProfileSettingsStore.keys.contains("metadata.translateDescriptions"))
    }
}
