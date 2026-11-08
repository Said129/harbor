import XCTest
@testable import Harbor

/// The anime picks settings applied to the Top Picks candidates, and the Simkl anime title language rule.
/// Fake titles only: no network, no UI.
@MainActor final class WireAnimeTests: XCTestCase {
    private func title(_ id: String, name: String? = nil, genres: [String]? = nil, country: String? = nil, rating: String? = nil) -> Media {
        var media = Media(id: id, type: "series", name: name ?? "Title " + id)
        media.genres = genres
        media.country = country
        media.imdbRating = rating
        return media
    }

    private func suite() throws -> (UserDefaults, String) {
        let name = "synthetic-wire-anime-" + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    private let allOff = AnimePicksPolicy.Options(favoriteGenres: [], excludeOrigins: [], hideWatched: false)

    // MARK: Settings off or empty keep today's picks

    func testSettingsOffKeepTheCandidatesInTodaysOrder() {
        let library = [title("mal:1", name: "Library Show", genres: ["Action"])]
        let candidates = [title("a", genres: ["Action"], rating: "7.0"), title("b", rating: "9.0"), title("c", genres: ["Action"], rating: "8.0")]
        let picks = AnimeService.rankedPicks(candidates, library: library, options: allOff, watchedIDs: ["a", "b", "c"])
        XCTAssertEqual(picks.map(\.id), ["c", "a", "b"], "genre overlap with the library first, then the rating; watched titles stay while the setting is off")
    }

    func testEmptyCandidatesGiveNoPicks() {
        XCTAssertEqual(AnimeService.rankedPicks([], library: [], options: allOff, watchedIDs: []).map(\.id), [])
        XCTAssertEqual(AnimeService.rankedPicks([], library: [title("mal:1")], options: .desktopDefault, watchedIDs: ["mal:1"]).map(\.id), [])
    }

    func testEmptyFavouritesAddNoGenreSeeds() {
        XCTAssertEqual(AnimeService.favouriteSeedIDs(allOff), [])
    }

    // MARK: Library exclusion stays as before

    func testLibraryTitlesAreRemovedByIDAndByName() {
        let library = [title("mal:1", name: "Naruto")]
        let candidates = [title("mal:1", name: "Other"), title("mal:9", name: "NARUTO"), title("mal:2", name: "Bleach")]
        XCTAssertEqual(AnimeService.rankedPicks(candidates, library: library, options: allOff, watchedIDs: []).map(\.id), ["mal:2"])
    }

    // MARK: Favourite genres seed the Jikan genre lists and do not reorder

    func testFavouriteSeedsAreTheFavouritesUpToThreeWithoutRepeats() {
        func options(_ favorites: [Int]) -> AnimePicksPolicy.Options {
            AnimePicksPolicy.Options(favoriteGenres: favorites, excludeOrigins: [], hideWatched: false)
        }
        XCTAssertEqual(AnimeService.favouriteSeedIDs(options([24, 8, 10, 37])), [24, 8, 10])
        XCTAssertEqual(AnimeService.favouriteSeedIDs(options([19, 19, 1])), [19, 1])
        XCTAssertEqual(AnimeService.favouriteSeedIDs(options([])), [])
    }

    func testFavouriteGenresOnlyAddCandidatesAndDoNotReorderThem() {
        let library = [title("mal:1", name: "Library Show", genres: ["Action"])]
        let candidates = [title("a", genres: ["Action"], rating: "7.0"), title("b", genres: ["Romance"], rating: "9.0")]
        let withFavourites = AnimePicksPolicy.Options(favoriteGenres: [22], excludeOrigins: [], hideWatched: false)
        XCTAssertEqual(AnimeService.rankedPicks(candidates, library: library, options: withFavourites, watchedIDs: []).map(\.id),
                       AnimeService.rankedPicks(candidates, library: library, options: allOff, watchedIDs: []).map(\.id))
    }

    // MARK: Hide watched

    func testWatchedTitlesAreHiddenOnlyWhenTheSettingIsOn() {
        let candidates = [title("w", rating: "9.0"), title("x", rating: "8.0")]
        let on = AnimePicksPolicy.Options(favoriteGenres: [], excludeOrigins: [], hideWatched: true)
        XCTAssertEqual(AnimeService.rankedPicks(candidates, library: [], options: on, watchedIDs: ["w"]).map(\.id), ["x"])
        XCTAssertEqual(AnimeService.rankedPicks(candidates, library: [], options: allOff, watchedIDs: ["w"]).map(\.id), ["w", "x"])
        XCTAssertEqual(AnimeService.rankedPicks(candidates, library: [], options: on, watchedIDs: []).map(\.id), ["w", "x"], "an empty watched set hides nothing")
    }

    // MARK: Excluded origins

    func testExcludedOriginsHideOnlyKnownCountriesOnTheList() {
        let candidates = [title("cn", country: "CN", rating: "9.0"), title("jp", country: "JP", rating: "8.0"), title("unknown", rating: "7.0")]
        let on = AnimePicksPolicy.Options(favoriteGenres: [], excludeOrigins: ["CN"], hideWatched: false)
        XCTAssertEqual(AnimeService.rankedPicks(candidates, library: [], options: on, watchedIDs: []).map(\.id), ["jp", "unknown"])
        XCTAssertEqual(AnimeService.rankedPicks(candidates, library: [], options: allOff, watchedIDs: []).map(\.id), ["cn", "jp", "unknown"])
    }

    // MARK: Saved preferences drive the same filter

    func testSavedPreferencesDriveTheWatchedFilter() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AnimePicksPreferences(defaults: defaults)
        let candidates = [title("w", rating: "9.0"), title("x", rating: "8.0")]
        XCTAssertEqual(AnimeService.rankedPicks(candidates, library: [], options: preferences.options, watchedIDs: ["w"]).map(\.id), ["x"],
                       "the Desktop default hides watched titles")
        preferences.setHideWatched(false)
        preferences.setExcludeOrigins([])
        XCTAssertEqual(AnimeService.rankedPicks(candidates, library: [], options: preferences.options, watchedIDs: ["w"]).map(\.id), ["w", "x"],
                       "turning the setting off keeps them")
    }

    // MARK: Simkl anime title language

    func testStoredTitleLanguageReadsEnglishWhenMissingOrUnknown() {
        XCTAssertEqual(SimklHomeRails.animeTitleLanguage(stored: nil), .english)
        XCTAssertEqual(SimklHomeRails.animeTitleLanguage(stored: "romaji"), .romaji)
        XCTAssertEqual(SimklHomeRails.animeTitleLanguage(stored: "native"), .native)
        XCTAssertEqual(SimklHomeRails.animeTitleLanguage(stored: "klingon"), .english)
    }

    func testPreferredAnimeTitleFollowsDesktopsFallbacks() {
        let titles = ["en": "Attack on Titan", "en_jp": "Shingeki no Kyojin", "ja": "進撃の巨人", "x-jat": "Shingeki no Kyojin"]
        XCTAssertEqual(SimklHomeRails.preferredAnimeTitle(titles, language: .english), "Attack on Titan")
        XCTAssertEqual(SimklHomeRails.preferredAnimeTitle(titles, language: .romaji), "Shingeki no Kyojin")
        XCTAssertEqual(SimklHomeRails.preferredAnimeTitle(titles, language: .native), "進撃の巨人")
    }

    func testPreferredAnimeTitleSkipsEmptyValuesAndIsNilWhenNothingFits() {
        XCTAssertEqual(SimklHomeRails.preferredAnimeTitle(["en": "", "ja": "進撃の巨人"], language: .english), "進撃の巨人")
        XCTAssertNil(SimklHomeRails.preferredAnimeTitle(["en": ""], language: .english))
        XCTAssertNil(SimklHomeRails.preferredAnimeTitle([:], language: .romaji))
    }
}
