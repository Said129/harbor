import Foundation

/// The release last played for a series season (Desktop's `SeasonLockEntry` in `lib/season-lock.ts`).
struct SeasonLockEntry: Codable, Equatable, Sendable {
    var infoHash: String?
    var fileIdx: Int?
    var addonId: String?
    var url: String?
    var parsedTitle: String?
    var resolution: String?
    var source: String?
    var bingeGroup: String?
    /// Anime keep one lock for the whole series (Desktop `seriesWide`).
    var seriesWide: Bool
    /// Milliseconds since 1970, as on Desktop.
    var savedAt: Double

    init(_ offer: StreamOffer, seriesWide: Bool, now: Date = Date()) {
        let raw = offer.raw
        infoHash = raw["infoHash"].string.flatMap { $0.isEmpty ? nil : $0 }
        fileIdx = raw["fileIdx"].integer
        addonId = offer.addonID.flatMap { $0.isEmpty ? nil : $0 }
        url = raw["url"].string.flatMap { $0.isEmpty ? nil : $0 }
        parsedTitle = raw["parsedTitle"].string.flatMap { $0.isEmpty ? nil : $0 }
        resolution = raw["resolution"].string.flatMap { $0.isEmpty ? nil : $0 }
        source = raw["source"].string.flatMap { $0.isEmpty ? nil : $0 }
        bingeGroup = offer.bingeGroup
        self.seriesWide = seriesWide
        savedAt = now.timeIntervalSince1970 * 1_000
    }

    /// Desktop's `streamMatchesSource`: the same torrent, else the same binge group, else the same addon,
    /// resolution and source. Season locks use this exact match, not the looser release-group match.
    func matches(_ offer: StreamOffer) -> Bool {
        let other = SeasonLockEntry(offer, seriesWide: false)
        if let infoHash, let otherHash = other.infoHash {
            return infoHash.lowercased() == otherHash.lowercased()
        }
        if let bingeGroup, let otherBinge = other.bingeGroup {
            return bingeGroup == otherBinge
        }
        guard let addonId else { return false }
        return addonId == other.addonId && resolution == other.resolution && source == other.source
    }
}

/// "Stay on one source for a season" (Desktop `lib/season-lock.ts`, `play-picker.tsx`, `use-pick-handler.ts`).
/// Locks are kept per profile in UserDefaults, like `StreamPlaybackHistory`. Desktop keeps them per device.
enum SeasonSourceLock {
    /// Desktop's TTL (120 days) and entry cap (300 newest).
    static let lifetime: TimeInterval = 120 * 86_400
    static let maximumEntries = 300

    /// Anime ids (`kitsu:`, `mal:`, `anilist:`, `anidb:`) lock one release for the whole series (Desktop `isAnimeMetaId`).
    static func isAnime(_ metaID: String) -> Bool {
        metaID.range(of: "^(kitsu|mal|anilist|anidb):", options: .regularExpression) != nil
    }

    /// Desktop's `seasonLock`: the setting applies to series and anime only.
    static func applies(enabled: Bool, mediaType: String, metaID: String) -> Bool {
        enabled && (mediaType == "series" || isAnime(metaID))
    }

    /// `metaID|sN` for a season and `metaID|all` otherwise (Desktop `seasonKey`).
    static func key(_ metaID: String, season: Int?) -> String {
        season.map { "\(metaID)|s\($0)" } ?? "\(metaID)|all"
    }

    private static func storeKey(_ owner: String) -> String { "streams.seasonLock.v1." + EBookShelf.hash(owner) }

    private static func readAll(owner: String, defaults: UserDefaults, now: Date) -> [String: SeasonLockEntry] {
        guard let data = defaults.data(forKey: storeKey(owner)),
              let saved = try? JSONDecoder().decode([String: SeasonLockEntry].self, from: data) else { return [:] }
        let current = now.timeIntervalSince1970 * 1_000
        return saved.filter { $0.value.savedAt > 0 && current - $0.value.savedAt <= lifetime * 1_000 }
    }

    private static func writeAll(_ entries: [String: SeasonLockEntry], owner: String, defaults: UserDefaults) {
        var kept = entries
        if kept.count > maximumEntries {
            let newest = kept.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(maximumEntries)
            kept = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(kept) { defaults.set(data, forKey: storeKey(owner)) }
    }

    /// Desktop's `saveSeasonLock`: called after a locked pick opens. A later pick replaces the lock.
    static func save(_ offer: StreamOffer, metaID: String, season: Int?, owner: String, defaults: UserDefaults = .standard, now: Date = Date()) {
        let wide = isAnime(metaID)
        var all = readAll(owner: owner, defaults: defaults, now: now)
        let slot = wide ? "\(metaID)|all" : key(metaID, season: season)
        all[slot] = SeasonLockEntry(offer, seriesWide: wide, now: now)
        writeAll(all, owner: owner, defaults: defaults)
    }

    /// Desktop's `readSeasonLock`: the lock for the season, else the series-wide lock. Anime ignore the season.
    static func read(metaID: String, season: Int?, owner: String, defaults: UserDefaults = .standard, now: Date = Date()) -> SeasonLockEntry? {
        let all = readAll(owner: owner, defaults: defaults, now: now)
        let effectiveSeason: Int? = isAnime(metaID) ? nil : season
        let perSeason = effectiveSeason.flatMap { all[key(metaID, season: $0)] }
        return perSeason ?? all["\(metaID)|all"]
    }

    /// Desktop's `clearSeasonLock`. Desktop never calls it, so a lock ends only when another pick replaces it or the TTL runs out.
    static func clear(metaID: String, season: Int?, owner: String, defaults: UserDefaults = .standard, now: Date = Date()) {
        var all = readAll(owner: owner, defaults: defaults, now: now)
        let effectiveSeason: Int? = isAnime(metaID) ? nil : season
        if let effectiveSeason { all[key(metaID, season: effectiveSeason)] = nil }
        all["\(metaID)|all"] = nil
        writeAll(all, owner: owner, defaults: defaults)
    }

    /// Desktop's `useAutoCandidates` with a lock: the release last played for this season moves to the front
    /// when it is playable now. A lock with no playable match leaves the order unchanged.
    static func ordered(_ offers: [StreamOffer], lock: SeasonLockEntry?) -> [StreamOffer] {
        guard let lock, let match = offers.first(where: { lock.matches($0) }), match.automaticallyPlayable else { return offers }
        return [match] + offers.filter { $0.id != match.id }
    }
}
