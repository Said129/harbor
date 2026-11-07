import Foundation

/// Desktop's saved stream filters (`lib/streams/custom-filters.ts`, `views/settings/stream-filters-panel.tsx`).
/// A filter names the stream quality a profile prefers. Every category it sets must match (AND); inside a
/// category any listed value matches (OR); an empty category accepts anything. When nothing matches, the
/// unfiltered list stays and the picker reports that it fell back (Desktop `fellBack`).
struct CustomStreamFilter: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var resolution: [String]
    var source: [String]
    var codec: [String]
    var audio: [String]
    var requireHdr: Bool
    var cachedOnly: Bool
    /// Desktop `minSeeders`: nil or 0 accepts any seeder count.
    var minSeeders: Int?
    /// Desktop `maxSizeGb`: nil or 0 accepts any size.
    var maxSizeGb: Double?

    init(id: String = UUID().uuidString, name: String, resolution: [String] = [], source: [String] = [], codec: [String] = [], audio: [String] = [],
         requireHdr: Bool = false, cachedOnly: Bool = false, minSeeders: Int? = nil, maxSizeGb: Double? = nil) {
        self.id = id; self.name = name; self.resolution = resolution; self.source = source; self.codec = codec; self.audio = audio
        self.requireHdr = requireHdr; self.cachedOnly = cachedOnly; self.minSeeders = minSeeders; self.maxSizeGb = maxSizeGb
    }

    /// Desktop's `load.ts` keeps any array it finds, so the category values are kept as text. Only a
    /// filter without an id or a name is dropped; a bad number becomes "not set".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let storedID = ((try? c.decode(String.self, forKey: .id)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let storedName = ((try? c.decode(String.self, forKey: .name)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !storedID.isEmpty, !storedName.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "A stream filter needs an id and a name.")
        }
        id = storedID
        name = storedName
        resolution = CustomStreamFilters.uniqueValues(try? c.decodeIfPresent([String].self, forKey: .resolution))
        source = CustomStreamFilters.uniqueValues(try? c.decodeIfPresent([String].self, forKey: .source))
        codec = CustomStreamFilters.uniqueValues(try? c.decodeIfPresent([String].self, forKey: .codec))
        audio = CustomStreamFilters.uniqueValues(try? c.decodeIfPresent([String].self, forKey: .audio))
        requireHdr = (try? c.decodeIfPresent(Bool.self, forKey: .requireHdr)) ?? false
        cachedOnly = (try? c.decodeIfPresent(Bool.self, forKey: .cachedOnly)) ?? false
        minSeeders = CustomStreamFilters.wholeSeeders(try? c.decodeIfPresent(Double.self, forKey: .minSeeders))
        maxSizeGb = CustomStreamFilters.nonNegativeSize(try? c.decodeIfPresent(Double.self, forKey: .maxSizeGb))
    }

    /// Desktop's `isFilterEmpty` negated: whether this filter restricts anything at all.
    var hasPreferences: Bool {
        if !resolution.isEmpty || !source.isEmpty || !codec.isEmpty || !audio.isEmpty { return true }
        if requireHdr || cachedOnly { return true }
        if let seeders = minSeeders, seeders > 0 { return true }
        if let size = maxSizeGb, size > 0 { return true }
        return false
    }

    /// Desktop's `matchesCustomFilter`. It reads the parsed fields only (resolution, source, codec, audio,
    /// HDR, cache state, seeders, size), never the release name, title, description or addon.
    func matches(_ offer: StreamOffer) -> Bool {
        let raw = offer.raw
        guard CustomStreamFilters.listMatches(resolution, raw["resolution"]),
              CustomStreamFilters.listMatches(source, raw["source"]),
              CustomStreamFilters.listMatches(codec, raw["codec"]),
              CustomStreamFilters.listMatches(audio, raw["audio"]["codec"]) else { return false }
        if requireHdr && (raw["hdrFormat"].string ?? "").isEmpty { return false }
        if cachedOnly && !CustomStreamFilters.isCached(raw) { return false }
        if let seeders = minSeeders, seeders > 0 {
            guard let count = CustomStreamFilters.number(raw["seeders"]), count >= Double(seeders) else { return false }
        }
        if let size = maxSizeGb, size > 0, let bytes = CustomStreamFilters.number(raw["size"]), bytes > size * CustomStreamFilters.bytesPerGigabyte {
            return false
        }
        return true
    }
}

/// Pure rules for Desktop's saved stream filters: matching, the picker fallback, text validation and the JSON list.
enum CustomStreamFilters {
    static let resolutionOptions = ["4K", "1080p", "720p", "480p", "SD"]
    static let sourceOptions = ["BluRay", "REMUX", "WEB-DL", "WEBRip", "BDRip", "HDRip", "DVDRip", "HDTV", "CAM", "TS", "HDTS", "TC", "SCR", "Other"]
    static let codecOptions = ["HEVC", "AVC", "AV1", "VP9", "MPEG2", "Other"]
    static let audioOptions = ["Atmos", "TrueHD", "DTS-HD MA", "DTS", "DD+", "AC3", "AAC", "Opus", "FLAC", "Other"]
    static let bytesPerGigabyte = 1_073_741_824.0
    /// Desktop's `isPositive` treats 0 and null alike; the largest seeder count JavaScript keeps exactly.
    private static let maximumSeeders = 9_007_199_254_740_991.0

    /// Desktop `apply` rule in `play-picker.tsx` (lines 356-359): an active filter with preferences keeps only
    /// the matching streams; when none match, every stream stays and `fellBack` is set.
    static func apply(_ offers: [StreamOffer], filter: CustomStreamFilter?) -> (offers: [StreamOffer], fellBack: Bool) {
        guard let filter = filter, filter.hasPreferences else { return (offers, false) }
        let matched = offers.filter { filter.matches($0) }
        if matched.isEmpty { return (offers, true) }
        return (matched, false)
    }

    /// Desktop's `summarizeMulti`-style list in the settings row: up to three values, then "+N".
    static func dimensionText(_ values: [String]) -> String? {
        if values.isEmpty { return nil }
        if values.count <= 3 { return values.joined(separator: ", ") }
        return values.prefix(3).joined(separator: ", ") + ", +\(values.count - 3)"
    }

    /// Desktop's `toggleMulti` in the builder: a chip adds or removes its value and keeps the others.
    static func toggled(_ value: String, in selected: [String]) -> [String] {
        selected.contains(value) ? selected.filter { $0 != value } : selected + [value]
    }

    /// Desktop's builder minimum seeders: blank means none, otherwise a whole number of 0 or more.
    static func parseMinSeeders(_ text: String) -> (valid: Bool, value: Int?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return (true, nil) }
        guard let number = Double(trimmed), number.isFinite, number >= 0, number == number.rounded(.towardZero), number <= maximumSeeders else {
            return (false, nil)
        }
        return (true, Int(number))
    }

    /// Desktop's builder maximum size in GB: blank means none, otherwise a finite number of 0 or more.
    static func parseMaxSizeGb(_ text: String) -> (valid: Bool, value: Double?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return (true, nil) }
        guard let number = Double(trimmed), number.isFinite, number >= 0 else { return (false, nil) }
        return (true, number)
    }

    /// The text the builder shows for a stored size or seeder limit: "20", not "20.0".
    static func gigabyteText(_ value: Double) -> String {
        if value < 1e15, value == value.rounded(.towardZero) { return String(Int(value)) }
        return String(value)
    }

    static func encodeList(_ filters: [CustomStreamFilter]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(filters) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Desktop's saved list. A row without an id or name is dropped and a duplicate id keeps its first row,
    /// so the editor and the active id always point at one filter.
    static func decodeList(_ text: String) -> [CustomStreamFilter] {
        guard let rows = try? JSONDecoder().decode([LossyFilter].self, from: Data(text.utf8)) else { return [] }
        var seen = Set<String>()
        var filters: [CustomStreamFilter] = []
        for row in rows {
            if let filter = row.value, seen.insert(filter.id).inserted { filters.append(filter) }
        }
        return filters
    }

    // MARK: - Matching helpers

    static func listMatches(_ allowed: [String], _ value: JSONValue) -> Bool {
        if allowed.isEmpty { return true }
        guard let text = value.string else { return false }
        return allowed.contains(text)
    }

    /// Desktop: a stream is cached when any debrid service reports it cached or in its library.
    static func isCached(_ raw: JSONValue) -> Bool {
        raw["cached"].objectValue.values.contains(.bool(true)) || raw["inLibrary"].objectValue.values.contains(.bool(true))
    }

    /// Seeders and sizes can arrive as any JSON number case from the core; a missing value is nil.
    static func number(_ value: JSONValue) -> Double? {
        switch value {
        case .integer(let number): return Double(number)
        case .unsigned(let number): return Double(number)
        case .number(let number): return number.isFinite ? number : nil
        case .string(let text): return Double(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    static func uniqueValues(_ values: [String]?) -> [String] {
        var seen = Set<String>()
        return (values ?? []).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func wholeSeeders(_ value: Double?) -> Int? {
        guard let value = value, value.isFinite, value > 0, value == value.rounded(.towardZero), value <= maximumSeeders else { return nil }
        return Int(value)
    }

    static func nonNegativeSize(_ value: Double?) -> Double? {
        guard let value = value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

/// Decodes one list row, or nil when the row is not a usable filter.
private struct LossyFilter: Decodable {
    let value: CustomStreamFilter?
    init(from decoder: Decoder) throws {
        value = try? CustomStreamFilter(from: decoder)
    }
}

/// Desktop's saved filters in UserDefaults. `customStreamFilters` holds the JSON list and
/// `activeStreamFilterId` the chosen id, both listed in `ProfileSettingsStore.keys`, so each profile keeps its own.
enum CustomStreamFilterStore {
    static let filtersKey = "customStreamFilters"
    static let activeKey = "activeStreamFilterId"

    static func filters(defaults: UserDefaults = .standard) -> [CustomStreamFilter] {
        guard let text = defaults.string(forKey: filtersKey) else { return [] }
        return CustomStreamFilters.decodeList(text)
    }

    static func saveFilters(_ filters: [CustomStreamFilter], defaults: UserDefaults = .standard) {
        if let text = CustomStreamFilters.encodeList(filters) { defaults.set(text, forKey: filtersKey) }
    }

    static func activeID(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: activeKey)
    }

    static func setActiveID(_ id: String?, defaults: UserDefaults = .standard) {
        if let id = id { defaults.set(id, forKey: activeKey) } else { defaults.removeObject(forKey: activeKey) }
    }

    /// Desktop's `activeId`: the chosen filter only when it exists and has a preference.
    static func activeFilter(defaults: UserDefaults = .standard) -> CustomStreamFilter? {
        guard let id = activeID(defaults: defaults) else { return nil }
        return filters(defaults: defaults).first { $0.id == id && $0.hasPreferences }
    }

    /// Desktop's `upsert` (stream-filters-panel.tsx:85-97): a filter with preferences becomes active when saved;
    /// an empty one only clears the active id if it was the active filter.
    static func save(_ filter: CustomStreamFilter, defaults: UserDefaults = .standard) {
        var all = filters(defaults: defaults)
        let previousActive = activeFilter(defaults: defaults)?.id
        if let index = all.firstIndex(where: { $0.id == filter.id }) { all[index] = filter } else { all.append(filter) }
        saveFilters(all, defaults: defaults)
        if filter.hasPreferences {
            setActiveID(filter.id, defaults: defaults)
        } else {
            setActiveID(previousActive == filter.id ? nil : previousActive, defaults: defaults)
        }
    }

    /// Desktop's `toggleActive`: choosing the active filter again turns it off.
    static func toggleActive(_ id: String, defaults: UserDefaults = .standard) {
        let current = activeFilter(defaults: defaults)?.id
        setActiveID(current == id ? nil : id, defaults: defaults)
    }

    /// Desktop's `remove`: deleting the active filter clears the active id.
    static func delete(_ id: String, defaults: UserDefaults = .standard) {
        saveFilters(filters(defaults: defaults).filter { $0.id != id }, defaults: defaults)
        if activeID(defaults: defaults) == id { setActiveID(nil, defaults: defaults) }
    }

    /// The offers the picker should list for the saved active filter (see `CustomStreamFilters.apply`).
    static func applyActive(_ offers: [StreamOffer], defaults: UserDefaults = .standard) -> (offers: [StreamOffer], fellBack: Bool) {
        CustomStreamFilters.apply(offers, filter: activeFilter(defaults: defaults))
    }
}
