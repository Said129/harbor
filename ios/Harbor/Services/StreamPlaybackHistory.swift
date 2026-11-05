import Foundation

/// The stream last played for a title or episode (Desktop's `PlaybackEntry` in `lib/playback-history.ts`).
struct StreamPlaybackEntry: Codable, Equatable, Sendable {
    var infoHash: String?
    var fileIdx: Int?
    var addonId: String?
    var url: String?
    var title: String?
    var parsedTitle: String?
    var resolution: String?
    var source: String?
    var size: Int64?
    /// Milliseconds since 1970, as on Desktop.
    var savedAt: Double

    init(infoHash: String? = nil, fileIdx: Int? = nil, addonId: String? = nil, url: String? = nil, title: String? = nil, parsedTitle: String? = nil,
         resolution: String? = nil, source: String? = nil, size: Int64? = nil, savedAt: Double) {
        self.infoHash = infoHash; self.fileIdx = fileIdx; self.addonId = addonId; self.url = url; self.title = title
        self.parsedTitle = parsedTitle; self.resolution = resolution; self.source = source; self.size = size; self.savedAt = savedAt
    }

    init(_ offer: StreamOffer, now: Date = Date()) {
        let raw = offer.raw
        self.init(infoHash: Self.text(raw["infoHash"]), fileIdx: raw["fileIdx"].integer, addonId: Self.text(raw["addonId"]), url: Self.text(raw["url"]),
                  title: Self.text(raw["title"]), parsedTitle: Self.text(raw["parsedTitle"]), resolution: Self.text(raw["resolution"]),
                  source: Self.text(raw["source"]), size: raw["size"].textValue.flatMap { Int64($0) }, savedAt: now.timeIntervalSince1970 * 1_000)
    }

    private static func text(_ value: JSONValue) -> String? { value.string.flatMap { $0.isEmpty ? nil : $0 } }

    /// Desktop's `streamMatchesEntry`: the same torrent (and file), the same release from the same addon, or the same address.
    func matches(_ offer: StreamOffer) -> Bool {
        let raw = offer.raw
        let otherIndex = raw["fileIdx"].integer
        if let infoHash, let otherHash = Self.text(raw["infoHash"]) {
            if infoHash.lowercased() != otherHash.lowercased() { return false }
            guard let fileIdx, let otherIndex else { return true }
            return fileIdx == otherIndex
        }
        let otherSize = raw["size"].textValue.flatMap { Int64($0) }
        if let addonId, Self.text(raw["addonId"]) == addonId, let parsedTitle, Self.text(raw["parsedTitle"]) == parsedTitle,
           resolution == raw["resolution"].string, source == raw["source"].string,
           fileIdx == nil || otherIndex == nil || fileIdx == otherIndex,
           size == nil || otherSize == nil || size == otherSize { return true }
        if let url, let otherURL = Self.text(raw["url"]) { return url == otherURL }
        return false
    }
}

/// "Remember last stream": what each profile played last, per title or episode, for 30 days and at most 200 entries.
enum StreamPlaybackHistory {
    static let lifetime: TimeInterval = 30 * 86_400
    static let maximumEntries = 200

    static func key(_ metaID: String, season: Int?, episode: Int?) -> String {
        if let season, let episode { return "\(metaID)|s\(season)e\(episode)" }
        return metaID
    }

    private static func storeKey(_ owner: String) -> String { "streams.history.v1." + EBookShelf.hash(owner) }

    private static func readAll(owner: String, defaults: UserDefaults, now: Date) -> [String: StreamPlaybackEntry] {
        guard let data = defaults.data(forKey: storeKey(owner)),
              let saved = try? JSONDecoder().decode([String: StreamPlaybackEntry].self, from: data) else { return [:] }
        let current = now.timeIntervalSince1970 * 1_000
        return saved.filter { $0.value.savedAt > 0 && current - $0.value.savedAt <= lifetime * 1_000 }
    }

    private static func writeAll(_ entries: [String: StreamPlaybackEntry], owner: String, defaults: UserDefaults) {
        var kept = entries
        if kept.count > maximumEntries {
            let newest = kept.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(maximumEntries)
            kept = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(kept) { defaults.set(data, forKey: storeKey(owner)) }
    }

    static func entry(metaID: String, season: Int?, episode: Int?, owner: String, defaults: UserDefaults = .standard, now: Date = Date()) -> StreamPlaybackEntry? {
        readAll(owner: owner, defaults: defaults, now: now)[key(metaID, season: season, episode: episode)]
    }

    static func save(_ entry: StreamPlaybackEntry, metaID: String, season: Int?, episode: Int?, owner: String, defaults: UserDefaults = .standard, now: Date = Date()) {
        var all = readAll(owner: owner, defaults: defaults, now: now)
        all[key(metaID, season: season, episode: episode)] = entry
        writeAll(all, owner: owner, defaults: defaults)
    }

    static func clear(metaID: String, season: Int?, episode: Int?, owner: String, defaults: UserDefaults = .standard, now: Date = Date()) {
        var all = readAll(owner: owner, defaults: defaults, now: now)
        all[key(metaID, season: season, episode: episode)] = nil
        writeAll(all, owner: owner, defaults: defaults)
    }
}
