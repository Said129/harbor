import Foundation
import Observation

enum TitleArtworkKind: String, CaseIterable, Sendable {
    case logo, poster, backdrop
    var storageKey: String { "harbor:title-" + rawValue + "s" }
    var setLabel: String { "Set as show " + rawValue }
    var resetLabel: String { rawValue.capitalized + " reset to default" }
}

/// Original per-title overrides. The active profile's settings mirror owns these maps.
@MainActor @Observable final class TitleArtworkPreferences {
    static let shared = TitleArtworkPreferences()
    private let defaults: UserDefaults
    private(set) var values: [TitleArtworkKind: [String: String]] = [:]
    init(defaults: UserDefaults = .standard) { self.defaults = defaults; reloadPreferences() }
    func value(_ kind: TitleArtworkKind, id: String) -> String? { values[kind]?[id] }
    @discardableResult func toggle(_ kind: TitleArtworkKind, id: String, url: String) -> Bool {
        guard !id.isEmpty, let image = CardArtworkPolicy.image(url) else { return false }
        var map = values[kind] ?? [:]
        if map[id] == image { map[id] = nil } else { map[id] = image }
        guard let data = try? JSONEncoder().encode(map), data.count <= 1_024 * 1_024 else { return false }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: kind.storageKey)
        values[kind] = map; return true
    }
    func applying(to media: Media) -> Media {
        var result = media
        result.logo = value(.logo, id: media.artworkID) ?? media.logo
        result.poster = value(.poster, id: media.artworkID) ?? media.poster
        result.background = value(.backdrop, id: media.artworkID) ?? media.background
        return result
    }
    func reloadPreferences() {
        var next: [TitleArtworkKind: [String: String]] = [:]
        for kind in TitleArtworkKind.allCases {
            let data = defaults.data(forKey: kind.storageKey) ?? defaults.string(forKey: kind.storageKey).map { Data($0.utf8) }
            let map = data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
                ?? defaults.dictionary(forKey: kind.storageKey) as? [String: String] ?? [:]
            next[kind] = map.compactMapValues { CardArtworkPolicy.image($0) }
        }
        values = next
    }
}
