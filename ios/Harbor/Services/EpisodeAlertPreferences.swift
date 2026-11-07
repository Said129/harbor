import Foundation
import Observation

/// The episode and movie alert choices. Each key is listed in `ProfileSettingsStore.keys`, so every profile keeps its own.
@MainActor @Observable
final class EpisodeAlertPreferences {
    static let shared = EpisodeAlertPreferences()
    enum Key {
        static let enabled = "episodeAlerts.enabled"
        static let leadMinutes = "episodeAlerts.leadMinutes"
        static let movies = "episodeAlerts.movies"
        static let series = "episodeAlerts.series"
        static let anime = "episodeAlerts.anime"
        static let library = "episodeAlerts.library"
    }

    /// Off until the person turns it on and the system grants notifications.
    var enabled = false { didSet { persist(enabled, forKey: Key.enabled) } }
    var leadMinutes = EpisodeAlertPlanner.defaultLeadMinutes { didSet { persist(leadMinutes, forKey: Key.leadMinutes) } }
    var movies = true { didSet { persist(movies, forKey: Key.movies) } }
    var series = true { didSet { persist(series, forKey: Key.series) } }
    var anime = true { didSet { persist(anime, forKey: Key.anime) } }
    var library = true { didSet { persist(library, forKey: Key.library) } }

    private let defaults: UserDefaults
    private var reloading = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reloadPreferences()
    }

    var settings: EpisodeAlertSettings {
        EpisodeAlertSettings(enabled: enabled, leadMinutes: leadMinutes, movies: movies, series: series, anime: anime, library: library)
    }

    /// Reads the saved values again, for a profile switch.
    func reloadPreferences() {
        reloading = true; defer { reloading = false }
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? false
        let lead = defaults.object(forKey: Key.leadMinutes) as? Int ?? EpisodeAlertPlanner.defaultLeadMinutes
        leadMinutes = EpisodeAlertPlanner.leadOptions.contains(lead) ? lead : EpisodeAlertPlanner.defaultLeadMinutes
        movies = defaults.object(forKey: Key.movies) as? Bool ?? true
        series = defaults.object(forKey: Key.series) as? Bool ?? true
        anime = defaults.object(forKey: Key.anime) as? Bool ?? true
        library = defaults.object(forKey: Key.library) as? Bool ?? true
    }

    private func persist(_ value: Any, forKey key: String) {
        if !reloading { defaults.set(value, forKey: key) }
    }
}
