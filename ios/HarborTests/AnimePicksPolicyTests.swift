import XCTest
@testable import Harbor

/// Desktop's anime picks rules (`lib/anime-filter.ts`, `lib/anime-top-picks-utils.ts`, `components/anime-genre-picker.tsx`)
/// and the saved picks settings.
@MainActor final class AnimePicksPolicyTests: XCTestCase {
    private func title(_ id: String, country: String? = nil) -> Media {
        var media = Media(id: id, type: "series", name: "Title " + id)
        media.country = country
        return media
    }

    private func suite() throws -> (UserDefaults, String) {
        let name = "synthetic-anime-picks-" + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    func testDesktopDefaultsHideChineseDonghuaAndWatchedTitlesWithNoFavouriteGenres() {
        XCTAssertEqual(AnimePicksPolicy.Options.desktopDefault,
                       AnimePicksPolicy.Options(favoriteGenres: [], excludeOrigins: ["CN"], hideWatched: true))
    }

    func testOriginRuleNeedsAKnownCountryOnTheExcludedList() {
        XCTAssertTrue(AnimePicksPolicy.originExcluded(title("mal:1", country: "CN"), excludeOrigins: ["CN"]))
        XCTAssertFalse(AnimePicksPolicy.originExcluded(title("mal:2", country: "JP"), excludeOrigins: ["CN"]))
        XCTAssertFalse(AnimePicksPolicy.originExcluded(title("mal:3"), excludeOrigins: ["CN"]), "an unknown country is never hidden")
        XCTAssertFalse(AnimePicksPolicy.originExcluded(title("mal:1", country: "CN"), excludeOrigins: []), "no excluded origins hides nothing")
    }

    func testFilteredKeepsTheOriginalOrderAndAppliesBothRules() {
        let items = [title("a", country: "CN"), title("b", country: "JP"), title("c"), title("d", country: "KR")]
        let watched: (String) -> Bool = { $0 == "c" }
        XCTAssertEqual(AnimePicksPolicy.filtered(items, options: .desktopDefault, isWatched: watched).map(\.id), ["b", "d"])
        let keepWatched = AnimePicksPolicy.Options(favoriteGenres: [], excludeOrigins: ["CN"], hideWatched: false)
        XCTAssertEqual(AnimePicksPolicy.filtered(items, options: keepWatched, isWatched: watched).map(\.id), ["b", "c", "d"])
    }

    func testHeroFrontDropsWatchedTitlesOnlyWhileUnwatchedOnesRemain() {
        let items = [title("a"), title("b"), title("c")]
        XCTAssertEqual(AnimePicksPolicy.heroFront(items, options: .desktopDefault, isWatched: { $0 != "b" }).map(\.id), ["b"])
        let everythingWatched: (String) -> Bool = { _ in true }
        XCTAssertEqual(AnimePicksPolicy.heroFront(items, options: .desktopDefault, isWatched: everythingWatched).map(\.id), ["a", "b", "c"],
                       "when every title is watched the hero keeps them all")
        let keepWatched = AnimePicksPolicy.Options(favoriteGenres: [], excludeOrigins: ["CN"], hideWatched: false)
        XCTAssertEqual(AnimePicksPolicy.heroFront(items, options: keepWatched, isWatched: { $0 != "b" }).map(\.id), ["a", "b", "c"])
    }

    func testGenreIdsAndLabelsMatchDesktopsPicker() {
        XCTAssertEqual(AnimePicksPolicy.genres.count, 16)
        XCTAssertEqual(Set(AnimePicksPolicy.genres.map(\.id)).count, 16, "every genre has its own Jikan id")
        XCTAssertEqual(AnimePicksPolicy.genreID(named: "Sci-Fi"), 24)
        XCTAssertEqual(AnimePicksPolicy.genreID(named: "Slice of Life"), 36)
        XCTAssertEqual(AnimePicksPolicy.genreID(named: "Music"), 19)
        XCTAssertNil(AnimePicksPolicy.genreID(named: "Unknown"))
        XCTAssertEqual(AnimePicksPolicy.origins.map(\.code), ["CN", "KR", "TW"])
    }

    func testSeedGenresPutTasteFirstThenFavouritesAndStopAtThree() {
        XCTAssertEqual(AnimePicksPolicy.seedGenreIDs(favorites: [10, 8, 2], tasteGenres: ["Drama", "Romance", "Drama", "Unknown", "Action"]),
                       [8, 22, 1])
        XCTAssertEqual(AnimePicksPolicy.seedGenreIDs(favorites: [8, 10, 37, 2], tasteGenres: ["Drama"]), [8, 10, 37])
        XCTAssertEqual(AnimePicksPolicy.seedGenreIDs(favorites: [19, 19, 1], tasteGenres: []), [19, 1])
        XCTAssertEqual(AnimePicksPolicy.seedGenreIDs(favorites: [], tasteGenres: []), [])
    }

    func testPreferencesReadDesktopDefaultsWhenNothingIsSaved() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AnimePicksPreferences(defaults: defaults)
        XCTAssertEqual(preferences.options, .desktopDefault)
    }

    func testPreferencesSaveUnderDesktopKeysAndSurviveARestart() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AnimePicksPreferences(defaults: defaults)
        preferences.toggleGenre(24)
        preferences.toggleGenre(8)
        preferences.toggleGenre(8)
        preferences.toggleOrigin("CN")
        preferences.toggleOrigin("KR")
        preferences.setHideWatched(false)
        XCTAssertEqual(defaults.stringArray(forKey: "animeExcludeOrigins"), ["KR"])
        XCTAssertEqual(defaults.object(forKey: "animeHideWatchedPicks") as? Bool, false)
        let restarted = AnimePicksPreferences(defaults: defaults)
        XCTAssertEqual(restarted.options, AnimePicksPolicy.Options(favoriteGenres: [24], excludeOrigins: ["KR"], hideWatched: false))
    }

    func testReloadFollowsAProfileSwitchThatWritesTheDefaults() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AnimePicksPreferences(defaults: defaults)
        XCTAssertTrue(preferences.hideWatched)
        defaults.set(false, forKey: "animeHideWatchedPicks")
        preferences.reloadPreferences()
        XCTAssertFalse(preferences.hideWatched)
    }
}
