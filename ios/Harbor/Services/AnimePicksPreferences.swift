import Foundation
import Observation

/// The anime picks settings of the active profile: Desktop's `animeFavoriteGenres`, `animeExcludeOrigins` and
/// `animeHideWatchedPicks`. The values are kept in UserDefaults under Desktop's names, so the profile settings mirror
/// saves and restores them. Call `reloadPreferences()` after a profile switch.
@MainActor @Observable final class AnimePicksPreferences {
    static let shared = AnimePicksPreferences()
    enum Key {
        static let favoriteGenres = "animeFavoriteGenres"
        static let excludeOrigins = "animeExcludeOrigins"
        static let hideWatched = "animeHideWatchedPicks"
    }

    private let defaults: UserDefaults
    private(set) var favoriteGenres: [Int] = []
    private(set) var excludeOrigins: [String] = AnimePicksPolicy.Options.desktopDefault.excludeOrigins
    private(set) var hideWatched = AnimePicksPolicy.Options.desktopDefault.hideWatched

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reloadPreferences()
    }

    var options: AnimePicksPolicy.Options {
        AnimePicksPolicy.Options(favoriteGenres: favoriteGenres, excludeOrigins: excludeOrigins, hideWatched: hideWatched)
    }

    func reloadPreferences() {
        favoriteGenres = (defaults.array(forKey: Key.favoriteGenres) ?? []).compactMap { ($0 as? NSNumber)?.intValue ?? ($0 as? Int) }
        excludeOrigins = defaults.object(forKey: Key.excludeOrigins) == nil
            ? AnimePicksPolicy.Options.desktopDefault.excludeOrigins
            : (defaults.stringArray(forKey: Key.excludeOrigins) ?? [])
        hideWatched = defaults.object(forKey: Key.hideWatched) as? Bool ?? AnimePicksPolicy.Options.desktopDefault.hideWatched
    }

    func setFavoriteGenres(_ value: [Int]) {
        favoriteGenres = value
        defaults.set(value, forKey: Key.favoriteGenres)
    }

    func toggleGenre(_ id: Int) {
        var next = favoriteGenres
        if let index = next.firstIndex(of: id) { next.remove(at: index) } else { next.append(id) }
        setFavoriteGenres(next)
    }

    func setExcludeOrigins(_ value: [String]) {
        excludeOrigins = value
        defaults.set(value, forKey: Key.excludeOrigins)
    }

    func toggleOrigin(_ code: String) {
        var next = excludeOrigins
        if let index = next.firstIndex(of: code) { next.remove(at: index) } else { next.append(code) }
        setExcludeOrigins(next)
    }

    func setHideWatched(_ value: Bool) {
        hideWatched = value
        defaults.set(value, forKey: Key.hideWatched)
    }
}
