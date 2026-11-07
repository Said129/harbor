import Foundation
import Observation

/// Desktop's trailer and hero toggles as read from the defaults of the profile on screen. A missing or non-boolean value
/// takes Desktop's default, which is off for all four (`src/lib/settings/defaults.ts`, `heroTrailers`, `heroTrailerAudio`,
/// `detailTrailerAutoplay`, `detailTrailerAudio`).
struct HeroTrailerSettings: Equatable, Sendable {
    var heroTrailers = false
    var heroTrailerAudio = false
    var detailTrailerAutoplay = false
    var detailTrailerAudio = false

    init() {}

    init(defaults: UserDefaults) {
        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? false }
        heroTrailers = flag("heroTrailers")
        heroTrailerAudio = flag("heroTrailerAudio")
        detailTrailerAutoplay = flag("detailTrailerAutoplay")
        detailTrailerAudio = flag("detailTrailerAudio")
    }
}

/// The trailer and hero toggles of the profile on screen. The values live in UserDefaults under Desktop's keys, which
/// `ProfileSettingsStore` saves per profile. Nothing is cached, so a profile switch shows on the next read.
@MainActor @Observable final class HeroTrailerPreferences {
    static let shared = HeroTrailerPreferences()
    /// Advances when a trailer value changes, so Observation-tracked readers refresh on a toggle or a profile switch.
    private(set) var revision = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var last: HeroTrailerSettings
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        last = HeroTrailerSettings(defaults: defaults)
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.noticeChange() }
        }
    }

    var heroTrailers: Bool {
        get { _ = revision; return HeroTrailerSettings(defaults: defaults).heroTrailers }
        set { write(newValue, forKey: "heroTrailers") }
    }

    var heroTrailerAudio: Bool {
        get { _ = revision; return HeroTrailerSettings(defaults: defaults).heroTrailerAudio }
        set { write(newValue, forKey: "heroTrailerAudio") }
    }

    var detailTrailerAutoplay: Bool {
        get { _ = revision; return HeroTrailerSettings(defaults: defaults).detailTrailerAutoplay }
        set { write(newValue, forKey: "detailTrailerAutoplay") }
    }

    var detailTrailerAudio: Bool {
        get { _ = revision; return HeroTrailerSettings(defaults: defaults).detailTrailerAudio }
        set { write(newValue, forKey: "detailTrailerAudio") }
    }

    private func write(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
        revision &+= 1
    }

    private func noticeChange() {
        let current = HeroTrailerSettings(defaults: defaults)
        guard current != last else { return }
        last = current
        revision &+= 1
    }
}
