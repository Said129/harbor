import Foundation
import Observation

/// Desktop's hero layout settings as read from the defaults of the profile on screen. Missing or unreadable values take
/// Desktop's defaults (see `HeroLayoutPolicy`).
struct HeroLayoutSettings: Equatable, Sendable {
    var shadowPercent = HeroLayoutPolicy.defaultShadowPercent
    var full = HeroLayoutPolicy.defaultFull
    var fullQuality = HeroLayoutPolicy.defaultFullQuality
    var feed = HeroLayoutPolicy.defaultFeed

    init() {}

    init(defaults: UserDefaults) {
        shadowPercent = HeroLayoutPolicy.shadowPercent(stored: defaults.object(forKey: "heroShadow"))
        full = defaults.object(forKey: "heroFull") as? Bool ?? HeroLayoutPolicy.defaultFull
        fullQuality = defaults.object(forKey: "heroFullQuality") as? Bool ?? HeroLayoutPolicy.defaultFullQuality
        feed = HeroLayoutPolicy.HeroFeed(stored: defaults.object(forKey: "heroFeed"))
    }
}

/// The hero layout settings of the profile on screen. The values live in UserDefaults under Desktop's keys, which
/// `ProfileSettingsStore` saves per profile. Nothing is cached, so a profile switch shows on the next read.
@MainActor @Observable final class HeroLayoutPreferences {
    static let shared = HeroLayoutPreferences()
    /// Advances when a hero value changes, so Observation-tracked readers refresh on a change or a profile switch.
    private(set) var revision = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var last: HeroLayoutSettings
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        last = HeroLayoutSettings(defaults: defaults)
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.noticeChange() }
        }
    }

    /// The shadow as a whole percent. The slider writes a Double, which is clamped and rounded before it is stored.
    var shadowPercent: Int {
        get { _ = revision; return HeroLayoutSettings(defaults: defaults).shadowPercent }
    }

    var shadowStrength: Double {
        get { Double(shadowPercent) }
        set { write(Double(HeroLayoutPolicy.shadowPercent(newValue)), forKey: "heroShadow") }
    }

    var full: Bool {
        get { _ = revision; return HeroLayoutSettings(defaults: defaults).full }
        set { write(newValue, forKey: "heroFull") }
    }

    var fullQuality: Bool {
        get { _ = revision; return HeroLayoutSettings(defaults: defaults).fullQuality }
        set { write(newValue, forKey: "heroFullQuality") }
    }

    var feed: HeroLayoutPolicy.HeroFeed {
        get { _ = revision; return HeroLayoutSettings(defaults: defaults).feed }
        set { write(newValue.rawValue, forKey: "heroFeed") }
    }

    private func write(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        revision &+= 1
    }

    private func noticeChange() {
        let current = HeroLayoutSettings(defaults: defaults)
        guard current != last else { return }
        last = current
        revision &+= 1
    }
}
