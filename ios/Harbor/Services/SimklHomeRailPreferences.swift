import Foundation
import Observation

extension SimklHomeRails.Settings {
    /// Reads Desktop's keys from the defaults of the profile on screen. A missing or invalid value takes Desktop's default.
    init(defaults: UserDefaults) {
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        var value = SimklHomeRails.Settings()
        value.homeRails = flag(SimklHomeRails.Keys.homeRails, false)
        value.upNext = flag(SimklHomeRails.Keys.upNext, false)
        value.trending = flag(SimklHomeRails.Keys.trending, false)
        value.moviesPlanToWatch = flag(SimklHomeRails.Keys.moviesPlanToWatch, true)
        value.showsWatching = flag(SimklHomeRails.Keys.showsWatching, true)
        value.showsPlanToWatch = flag(SimklHomeRails.Keys.showsPlanToWatch, true)
        let language = defaults.string(forKey: SimklHomeRails.Keys.animeTitleLanguage) ?? ""
        value.animeTitleLanguage = SimklHomeRails.AnimeTitleLanguage(rawValue: language) ?? .english
        self = value
    }
}

/// The Simkl home-rail preferences of the profile on screen. The values live in UserDefaults under Desktop's keys, which
/// `ProfileSettingsStore` saves per profile. Nothing is cached here, so a profile switch is visible on the next read.
@MainActor @Observable final class SimklHomeRailPreferences {
    static let shared = SimklHomeRailPreferences()
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var settings: SimklHomeRails.Settings { SimklHomeRails.Settings(defaults: defaults) }

    /// Desktop's disconnect resets these to their defaults (`simkl-panel.tsx`), which removing the keys also does.
    func reset() {
        for key in SimklHomeRails.Keys.all { defaults.removeObject(forKey: key) }
    }
}
