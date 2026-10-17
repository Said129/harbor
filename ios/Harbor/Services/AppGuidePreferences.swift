import Foundation
import Observation

enum AppHint: String, CaseIterable { case imageCache }

@MainActor @Observable
final class AppGuidePreferences {
    static let shared = AppGuidePreferences()
    private let defaults: UserDefaults
    private static let initializedKey = "nativeGuide.initialized.v1"
    private static let completedKey = "nativeGuide.completed.v1"
    private static let hintsKey = "nativeGuide.dismissedHints.v1"
    private(set) var completed: Bool
    private(set) var dismissedHints: Set<String>
    var presentationRequested = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completed = defaults.bool(forKey: Self.completedKey)
        dismissedHints = Set(defaults.stringArray(forKey: Self.hintsKey) ?? [])
        presentationRequested = defaults.object(forKey: Self.initializedKey) != nil && !completed
    }

    func prepare(hasSavedConfiguration: Bool) {
        guard defaults.object(forKey: Self.initializedKey) == nil else { return }
        // Existing installations keep their setup and do not receive a new
        // welcome screen on upgrade. Call only after successful storage reads.
        completed = hasSavedConfiguration
        defaults.set(completed, forKey: Self.completedKey)
        defaults.set(true, forKey: Self.initializedKey)
        presentationRequested = !completed
    }

    func replay() {
        restoreHints()
        defaults.set(true, forKey: Self.initializedKey)
        completed = false; defaults.set(false, forKey: Self.completedKey)
        presentationRequested = true
    }

    func finish() {
        defaults.set(true, forKey: Self.initializedKey)
        completed = true; defaults.set(true, forKey: Self.completedKey)
        presentationRequested = false
    }

    func isVisible(_ hint: AppHint) -> Bool { !dismissedHints.contains(hint.rawValue) }
    func dismiss(_ hint: AppHint) {
        dismissedHints.insert(hint.rawValue)
        defaults.set(dismissedHints.sorted(), forKey: Self.hintsKey)
    }
    func restoreHints() {
        dismissedHints.removeAll(); defaults.removeObject(forKey: Self.hintsKey)
    }
}
