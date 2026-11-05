import Foundation

/// Desktop's hidden episodes (`lib/hidden-episodes.ts`): episodes the person hid are left out of the list
/// and skipped by Up Next while "Hide and skip episodes" is on. Keys are `meta|season|episode`.
enum HiddenEpisodes {
    static let storageKey = "episodes.hidden.v1"

    static func key(_ metaID: String, season: Int, episode: Int) -> String { "\(metaID)|\(season)|\(episode)" }

    static func all(_ defaults: UserDefaults = .standard) -> Set<String> {
        guard let data = defaults.data(forKey: storageKey), let saved = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(saved)
    }

    private static func write(_ keys: Set<String>, _ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(keys.sorted()) { defaults.set(data, forKey: storageKey) }
    }

    static func isHidden(_ metaID: String, season: Int, episode: Int, defaults: UserDefaults = .standard) -> Bool {
        all(defaults).contains(key(metaID, season: season, episode: episode))
    }

    static func set(_ hidden: Bool, metaID: String, season: Int, episode: Int, defaults: UserDefaults = .standard) {
        var keys = all(defaults)
        let entry = key(metaID, season: season, episode: episode)
        guard keys.contains(entry) != hidden else { return }
        if hidden { keys.insert(entry) } else { keys.remove(entry) }
        write(keys, defaults)
    }

    /// Desktop's `hiddenKeysFor`: the `season:episode` pairs hidden for one show.
    static func coordinates(for metaID: String, defaults: UserDefaults = .standard) -> Set<String> {
        let prefix = metaID + "|"
        var result = Set<String>()
        for entry in all(defaults) where entry.hasPrefix(prefix) {
            let parts = entry.split(separator: "|", omittingEmptySubsequences: false)
            if parts.count == 3 { result.insert("\(parts[1]):\(parts[2])") }
        }
        return result
    }

    static func clear(metaID: String, defaults: UserDefaults = .standard) {
        let prefix = metaID + "|"
        let keys = all(defaults)
        let kept = keys.filter { !$0.hasPrefix(prefix) }
        if kept.count != keys.count { write(kept, defaults) }
    }
}
