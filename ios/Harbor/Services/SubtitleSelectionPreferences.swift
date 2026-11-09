import Foundation
import Observation

/// Desktop's subtitle selection settings (`src/lib/settings/defaults.ts`): `preferEmbeddedSubs`, `subtitlePreselect`, `subtitleAutoUpgrade`, `trackBlockWords`, `subAssNormalizeSize` and `subSecondaryScale`. ProfileSettingsStore keeps each key per profile.
@MainActor @Observable
final class SubtitleSelectionPreferences {
    static let shared = SubtitleSelectionPreferences()

    /// Desktop default: off.
    var preferEmbeddedSubs = UserDefaults.standard.object(forKey: "preferEmbeddedSubs") as? Bool ?? false {
        didSet { persist(preferEmbeddedSubs, forKey: "preferEmbeddedSubs") }
    }
    var forcedSubsWhenNativeAudio = UserDefaults.standard.object(forKey: "forcedSubsWhenNativeAudio") as? Bool ?? false {
        didSet { persist(forcedSubsWhenNativeAudio, forKey: "forcedSubsWhenNativeAudio") }
    }

    /// Desktop default: off.
    var subtitlePreselect = UserDefaults.standard.object(forKey: "subtitlePreselect") as? Bool ?? false {
        didSet { persist(subtitlePreselect, forKey: "subtitlePreselect") }
    }
    /// Desktop default: off.
    var subtitleAutoUpgrade = UserDefaults.standard.object(forKey: "subtitleAutoUpgrade") as? Bool ?? false {
        didSet { persist(subtitleAutoUpgrade, forKey: "subtitleAutoUpgrade") }
    }
    /// Desktop default: `["commentary"]`.
    var trackBlockWords = UserDefaults.standard.stringArray(forKey: "trackBlockWords") ?? ["commentary"] {
        didSet { persist(trackBlockWords, forKey: "trackBlockWords") }
    }
    /// Desktop default: off.
    var subAssNormalizeSize = UserDefaults.standard.object(forKey: "subAssNormalizeSize") as? Bool ?? false {
        didSet { persist(subAssNormalizeSize, forKey: "subAssNormalizeSize") }
    }
    /// Desktop default: 0.85, clamped to 0.4...1.4 when used.
    var subSecondaryScale = UserDefaults.standard.object(forKey: "subSecondaryScale") as? Double ?? 0.85 {
        didSet { persist(subSecondaryScale, forKey: "subSecondaryScale") }
    }

    private var reloading = false

    private func persist(_ value: Any?, forKey key: String) {
        if !reloading { UserDefaults.standard.set(value, forKey: key) }
    }

    /// Called after ProfileSettingsStore switches profile and rewrites the defaults keys.
    func reloadPreferences() {
        reloading = true
        defer { reloading = false }
        preferEmbeddedSubs = UserDefaults.standard.object(forKey: "preferEmbeddedSubs") as? Bool ?? false
        forcedSubsWhenNativeAudio = UserDefaults.standard.object(forKey: "forcedSubsWhenNativeAudio") as? Bool ?? false
        subtitlePreselect = UserDefaults.standard.object(forKey: "subtitlePreselect") as? Bool ?? false
        subtitleAutoUpgrade = UserDefaults.standard.object(forKey: "subtitleAutoUpgrade") as? Bool ?? false
        trackBlockWords = UserDefaults.standard.stringArray(forKey: "trackBlockWords") ?? ["commentary"]
        subAssNormalizeSize = UserDefaults.standard.object(forKey: "subAssNormalizeSize") as? Bool ?? false
        subSecondaryScale = UserDefaults.standard.object(forKey: "subSecondaryScale") as? Double ?? 0.85
    }
}
