import Foundation
import Observation

/// Desktop's "Auto-skip stalled streams", "How long to wait first" and "Stay on one source for a season"
/// (`autoNextStreamOnStall`, `autoNextStreamOnStallSec`, `seasonSourceLock`). ProfileSettingsStore keeps them per profile.
@MainActor @Observable
final class StreamAutoSwitchPreferences {
    static let shared = StreamAutoSwitchPreferences()
    /// Desktop default: off.
    var autoNextOnStall = UserDefaults.standard.object(forKey: "autoNextStreamOnStall") as? Bool ?? false {
        didSet { persist(autoNextOnStall, forKey: "autoNextStreamOnStall") }
    }
    /// Desktop default: 10 seconds.
    var stallWaitSeconds = StreamStallPolicy.waitSeconds(UserDefaults.standard.object(forKey: "autoNextStreamOnStallSec") as? Int) {
        didSet { persist(stallWaitSeconds, forKey: "autoNextStreamOnStallSec") }
    }
    /// Desktop default: off.
    var seasonSourceLock = UserDefaults.standard.object(forKey: "seasonSourceLock") as? Bool ?? false {
        didSet { persist(seasonSourceLock, forKey: "seasonSourceLock") }
    }
    private var reloading = false
    private func persist(_ value: Any?, forKey key: String) {
        if !reloading { UserDefaults.standard.set(value, forKey: key) }
    }
    func reloadPreferences() {
        reloading = true; defer { reloading = false }
        autoNextOnStall = UserDefaults.standard.object(forKey: "autoNextStreamOnStall") as? Bool ?? false
        stallWaitSeconds = StreamStallPolicy.waitSeconds(UserDefaults.standard.object(forKey: "autoNextStreamOnStallSec") as? Int)
        seasonSourceLock = UserDefaults.standard.object(forKey: "seasonSourceLock") as? Bool ?? false
    }
}
