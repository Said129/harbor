import Foundation
import Observation

/// Desktop's content advisory settings (`lib/settings/defaults.ts`: the toast is off, monochrome, and the ignore button is on).
/// The keys are Desktop's, and ProfileSettingsStore keeps them per profile. Call `reloadPreferences()` after a profile switch.
@MainActor @Observable
final class ContentAdvisoryPreferences {
    static let shared = ContentAdvisoryPreferences()
    /// Desktop's onboarding nudge flag. It lives in Desktop's localStorage, so it stays on this device and is not in the profile.
    static let nudgeKey = "harbor.onboarding.contentAdvisoryNudge"

    /// Desktop's `contentAdvisoryToast`: show the card when a title starts.
    var showToast = UserDefaults.standard.object(forKey: "contentAdvisoryToast") as? Bool ?? false {
        didSet {
            persist(showToast, forKey: "contentAdvisoryToast")
            // Desktop's settings toggle dismisses the invitation whichever way it is switched.
            if !reloading { markNudgeSeen() }
        }
    }
    /// Desktop's `contentAdvisoryTheme`.
    var theme = ContentAdvisoryTheme(stored: UserDefaults.standard.string(forKey: "contentAdvisoryTheme")) {
        didSet { persist(theme.rawValue, forKey: "contentAdvisoryTheme") }
    }
    /// Desktop's `contentAdvisoryShowIgnore`: the "Ignore this title" button on the card.
    var showIgnoreButton = UserDefaults.standard.object(forKey: "contentAdvisoryShowIgnore") as? Bool ?? true {
        didSet { persist(showIgnoreButton, forKey: "contentAdvisoryShowIgnore") }
    }

    /// Whether the invitation was already seen on this device.
    var nudgeSeen: Bool { UserDefaults.standard.bool(forKey: Self.nudgeKey) }

    func markNudgeSeen() {
        UserDefaults.standard.set(true, forKey: Self.nudgeKey)
    }

    private var reloading = false
    private func persist(_ value: Any, forKey key: String) {
        if !reloading { UserDefaults.standard.set(value, forKey: key) }
    }

    func reloadPreferences() {
        reloading = true; defer { reloading = false }
        showToast = UserDefaults.standard.object(forKey: "contentAdvisoryToast") as? Bool ?? false
        theme = ContentAdvisoryTheme(stored: UserDefaults.standard.string(forKey: "contentAdvisoryTheme"))
        showIgnoreButton = UserDefaults.standard.object(forKey: "contentAdvisoryShowIgnore") as? Bool ?? true
    }
}

/// Titles whose advisory card is never shown again (Desktop's `harbor.advisory.ignored.v1` list in localStorage). It is kept on
/// this device and is not part of a profile, as in Desktop.
@MainActor @Observable
final class ContentAdvisoryIgnores {
    static let shared = ContentAdvisoryIgnores()
    static let key = "harbor.advisory.ignored.v1"

    private let defaults: UserDefaults
    private(set) var titles: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        titles = Set((defaults.array(forKey: Self.key) as? [String] ?? []).filter { !$0.isEmpty })
    }

    var count: Int { titles.count }

    func isIgnored(_ imdbID: String?) -> Bool {
        guard let imdbID, !imdbID.isEmpty else { return false }
        return titles.contains(imdbID)
    }

    func ignore(_ imdbID: String) {
        guard !imdbID.isEmpty, !titles.contains(imdbID) else { return }
        titles.insert(imdbID)
        save()
    }

    func clear() {
        guard !titles.isEmpty else { return }
        titles.removeAll()
        save()
    }

    private func save() {
        defaults.set(titles.sorted(), forKey: Self.key)
    }
}
