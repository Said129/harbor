import Foundation

/// Desktop's playback speed presets (`transport/speed-menu.tsx`): the usual speeds plus the ones
/// the user adds. A custom speed is 0.1 to 4 with two decimals and never repeats a preset.
enum PlaybackSpeeds {
    /// Desktop's curated speeds, with the 0.5 and 1.75 the iPhone always offered.
    static let presets: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    static let customKey = "customPlaybackSpeeds"

    static func normalized(_ raw: Double) -> Double? {
        guard raw.isFinite else { return nil }
        let value = (raw * 100).rounded() / 100
        return (0.1...4).contains(value) ? value : nil
    }

    static func custom(_ defaults: UserDefaults = .standard) -> [Double] {
        var seen = Set(presets)
        return ((defaults.array(forKey: customKey) as? [Double]) ?? []).compactMap(normalized).filter { seen.insert($0).inserted }.sorted()
    }

    /// Whether `raw` became a new custom speed.
    static func add(_ raw: Double, _ defaults: UserDefaults = .standard) -> Bool {
        guard let value = normalized(raw), !presets.contains(value) else { return false }
        let existing = custom(defaults)
        guard !existing.contains(value) else { return false }
        defaults.set((existing + [value]).sorted(), forKey: customKey)
        return true
    }
    static func remove(_ value: Double, _ defaults: UserDefaults = .standard) {
        defaults.set(custom(defaults).filter { $0 != value }, forKey: customKey)
    }

    /// Every speed the menu lists, in order, and the current one even when it is no longer saved.
    static func choices(current: Double, _ defaults: UserDefaults = .standard) -> [Double] {
        var seen = Set<Double>()
        return (presets + custom(defaults) + (normalized(current).map { [$0] } ?? [])).filter { seen.insert($0).inserted }.sorted()
    }
}
