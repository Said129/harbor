import Foundation

/// Desktop's `snapshotSub` fields (`lib/player/sub-presets.ts`), under Desktop's names and units, so the stored JSON has the shape of Desktop's `harbor.sub.presets.v1`.
struct SubtitleLookValues: Codable, Equatable, Sendable {
    var subStyle: String
    var subFontFamily: String
    var subFontSize: Double
    var subFontColor: String
    var subBorderColor: String
    var subBorderSize: Double
    var subMarginY: Double
    var subAlignX: String
    var subAssOverride: String
    var subBoxOpacity: Double
    var subBoxColor: String
    var subOpacity: Double
    var subLineSpacing: Double
}

struct SubtitleLookPreset: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var values: SubtitleLookValues
}

/// Desktop's saved subtitle looks: seeds, names, ids, the twelve-look cap, and how a look maps onto the iOS playback options.
enum SubtitleLookPresets {
    static let maximumCount = 12

    static let seeds: [SubtitleLookPreset] = [
        SubtitleLookPreset(id: "english", name: "English", values: SubtitleLookValues(subStyle: "shadow", subFontFamily: "inter", subFontSize: 28, subFontColor: "#FFFFFF", subBorderColor: "#000000", subBorderSize: 0, subMarginY: 10, subAlignX: "center", subAssOverride: "scale", subBoxOpacity: 0.6, subBoxColor: "#000000", subOpacity: 1, subLineSpacing: 0)),
        SubtitleLookPreset(id: "foreign", name: "Foreign", values: SubtitleLookValues(subStyle: "outline", subFontFamily: "inter", subFontSize: 40, subFontColor: "#FFFFFF", subBorderColor: "#000000", subBorderSize: 2, subMarginY: 14, subAlignX: "center", subAssOverride: "scale", subBoxOpacity: 0.6, subBoxColor: "#000000", subOpacity: 1, subLineSpacing: 0)),
        SubtitleLookPreset(id: "arabic", name: "Arabic", values: SubtitleLookValues(subStyle: "outline", subFontFamily: "arabic", subFontSize: 40, subFontColor: "#FFFFFF", subBorderColor: "#000000", subBorderSize: 2, subMarginY: 14, subAlignX: "center", subAssOverride: "force", subBoxOpacity: 0.6, subBoxColor: "#000000", subOpacity: 1, subLineSpacing: 0)),
    ]

    /// Desktop's `snapshotSub`. Bold and the subtitle languages are not part of a look, as in Desktop.
    static func snapshot(_ options: PlaybackOptions) -> SubtitleLookValues {
        SubtitleLookValues(
            subStyle: options.subtitleStyle, subFontFamily: options.subtitleFont, subFontSize: options.subtitleSize,
            subFontColor: options.subtitleColor, subBorderColor: options.borderColor, subBorderSize: options.borderSize,
            subMarginY: 100 - options.subtitlePosition, subAlignX: options.subtitleAlignment, subAssOverride: options.subtitleASS,
            subBoxOpacity: options.boxOpacity, subBoxColor: options.subtitleBoxColor, subOpacity: options.subtitleOpacity,
            subLineSpacing: options.subtitleSpacing)
    }

    /// Writes the same values the individual controls write: the position is stored as the distance from the bottom's complement.
    static func apply(_ values: SubtitleLookValues, to options: inout PlaybackOptions) {
        options.subtitleStyle = values.subStyle
        options.subtitleFont = values.subFontFamily
        options.subtitleSize = values.subFontSize
        options.subtitleColor = values.subFontColor
        options.borderColor = values.subBorderColor
        options.borderSize = values.subBorderSize
        options.subtitlePosition = 100 - values.subMarginY
        options.subtitleAlignment = values.subAlignX
        options.subtitleASS = values.subAssOverride
        options.boxOpacity = values.subBoxOpacity
        options.subtitleBoxColor = values.subBoxColor
        options.subtitleOpacity = values.subOpacity
        options.subtitleSpacing = values.subLineSpacing
    }

    static func matches(_ options: PlaybackOptions, _ preset: SubtitleLookPreset) -> Bool {
        snapshot(options) == preset.values
    }

    /// Desktop trims the name; an empty name saves nothing.
    static func normalizedName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Desktop's id: the lowercased name with whitespace runs as dashes, cut to 24 characters, then the count of looks before it was added.
    static func identifier(for name: String, existingCount: Int) -> String {
        let slug = name.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
        return "\(String(slug.prefix(24)))-\(existingCount)"
    }

    static func adding(name raw: String, values: SubtitleLookValues, to list: [SubtitleLookPreset]) -> [SubtitleLookPreset]? {
        guard let name = normalizedName(raw) else { return nil }
        return list + [SubtitleLookPreset(id: identifier(for: name, existingCount: list.count), name: name, values: values)]
    }

    static func overriding(id: String, values: SubtitleLookValues, in list: [SubtitleLookPreset]) -> [SubtitleLookPreset] {
        list.map { $0.id == id ? SubtitleLookPreset(id: $0.id, name: $0.name, values: values) : $0 }
    }

    static func removing(id: String, from list: [SubtitleLookPreset]) -> [SubtitleLookPreset] {
        list.filter { $0.id != id }
    }

    /// Desktop's `saveSubPresets` keeps the first twelve looks.
    static func committed(_ list: [SubtitleLookPreset]) -> [SubtitleLookPreset] {
        Array(list.prefix(maximumCount))
    }

    /// Desktop's `loadSubPresets`: no stored value, or data that does not decode, gives the seeds. A stored empty list stays empty.
    static func decode(_ data: Data?) -> [SubtitleLookPreset] {
        guard let data else { return seeds }
        return (try? JSONDecoder().decode([SubtitleLookPreset].self, from: data)) ?? seeds
    }

    static func encode(_ list: [SubtitleLookPreset]) throws -> Data {
        try JSONEncoder().encode(committed(list))
    }
}

/// The looks live in the profile's UserDefaults under `harbor.sub.presets.v1`, which `ProfileSettingsStore.keys` lists, so each profile keeps its own.
struct SubtitleLookPresetStore {
    static let key = "harbor.sub.presets.v1"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func presets() -> [SubtitleLookPreset] {
        SubtitleLookPresets.decode(defaults.data(forKey: Self.key))
    }

    @discardableResult func save(_ list: [SubtitleLookPreset]) -> Bool {
        guard let data = try? SubtitleLookPresets.encode(list) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
}
