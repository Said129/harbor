import Foundation

/// Supplement public anime episodes without changing their playback or library identity.
actor AnimeEpisodeService {
    static let shared = AnimeEpisodeService()
    private struct Supplement: Sendable { let mapping: JSONValue; let canonical: [Episode] }
    private struct Entry { let value: Supplement; let expires: Date }
    private var cache: [String: Entry] = [:]
    private var pending: [String: Task<Supplement?, Never>] = [:]

    func episodes(for media: Media, grouping: AnimeEpisodeGrouping = .seasons) async -> [Episode] {
        await variants(for: media).episodes(grouping)
    }

    func variants(for media: Media) async -> AnimeEpisodeVariants {
        let original = media.videos ?? []
        guard media.episodic, !original.isEmpty, let query = Self.query(media) else {
            return AnimeEpisodeVariants(seasons: original, continuous: original)
        }
        guard let supplement = await supplement(for: query), !Task.isCancelled else {
            let source = Self.providerEpisodes(original)
            return AnimeEpisodeVariants(seasons: source, continuous: source)
        }
        return Self.variants(mapping: supplement.mapping, canonical: supplement.canonical, original: original, animeIdentity: AnimeService.isAnime(media.id))
    }

    static func variants(mapping: JSONValue, canonical: [Episode], original: [Episode], animeIdentity: Bool) -> AnimeEpisodeVariants {
        let source = providerEpisodes(original)
        let continuous = applying(mapping, canonical: canonical, to: source, animeIdentity: animeIdentity)
        let seasons = continuous.map { episode in
            var value = episode; value.displaySeason = nil; value.displayEpisode = nil; return value
        }
        return AnimeEpisodeVariants(seasons: seasons, continuous: continuous, tvdbSeriesID: mapping["mappings"]["thetvdb_id"].integer.flatMap { $0 > 0 ? $0 : nil },
            kitsuID: mapping["mappings"]["kitsu_id"].integer.flatMap { $0 > 0 ? $0 : nil })
    }

    private static func providerEpisodes(_ original: [Episode]) -> [Episode] {
        // A previous build may have persisted its forced continuous presentation.
        // Restore the provider's coordinates before choosing either visible order.
        original.map { episode in
            var value = episode; value.displaySeason = nil; value.displayEpisode = nil; return value
        }
    }

    func hasAnimeIdentity(for media: Media) async -> Bool {
        guard let query = Self.query(media, allowUnknown: true) else { return false }
        return await supplement(for: query) != nil
    }

    private func supplement(for query: String) async -> Supplement? {
        let supplement: Supplement?
        if let entry = cache[query], entry.expires > Date() { supplement = entry.value }
        else if let task = pending[query] { supplement = await task.value }
        else {
            let task = Task { await Self.fetch(query) }
            pending[query] = task
            supplement = await task.value
            pending[query] = nil
            if let supplement {
                if cache.count >= 32, let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key { cache[oldest] = nil }
                cache[query] = Entry(value: supplement, expires: Date().addingTimeInterval(1800))
            }
        }
        return supplement
    }

    private static func query(_ media: Media, allowUnknown: Bool = false) -> String? {
        let providers = ["kitsu": "kitsu_id", "mal": "mal_id", "anilist": "anilist_id", "anidb": "anidb_id"]
        let components = media.id.split(separator: ":")
        if components.count == 2, let key = providers[String(components[0])], let number = Int64(components[1]), number > 0 { return "\(key)=\(number)" }
        guard allowUnknown || media.type == "anime" || media.genres?.contains(where: { ["anime", "animation"].contains($0.lowercased()) }) == true,
              media.id.range(of: "^tt[0-9]{7,}$", options: .regularExpression) != nil else { return nil }
        return "imdb_id=\(media.id)"
    }

    private static func fetch(_ query: String) async -> Supplement? {
        do {
            let requested = query.split(separator: "=", maxSplits: 1)
            let providers = ["kitsu_id": "kitsu", "mal_id": "mal", "anilist_id": "anilist", "anidb_id": "anidb", "imdb_id": "imdb"]
            guard requested.count == 2, let provider = providers[String(requested[0])] else { return nil }
            let identity = provider == "imdb" ? String(requested[1]) : provider + ":" + String(requested[1])
            let mapping = try await AnimeFranchiseService.shared.response(.mapping(identity))
            guard mapping["mappings"][String(requested[0])].textValue == String(requested[1]) else { return nil }
            guard let kitsu = mapping["mappings"]["kitsu_id"].integer, kitsu > 0 else { return nil }
            // A Kitsu entry supplies the anime's own episode order. TV/IMDb
            // seasons in the mapping are retained only as lookup coordinates.
            let canonical = try await AnimeService.metadata(id: "kitsu:\(kitsu)", kind: "series")
            guard canonical.id == "kitsu:\(kitsu)" else { return nil }
            return Supplement(mapping: mapping, canonical: canonical.videos ?? [])
        } catch { return nil }
    }

    static func applying(_ mapping: JSONValue, canonical: [Episode], to original: [Episode], animeIdentity: Bool) -> [Episode] {
        guard case .object(let entries) = mapping["episodes"] else { return original }
        let regular = canonical.filter { ($0.season ?? 1) > 0 && ($0.episode ?? 0) > 0 }
        var byNumber: [Int: Episode] = [:]
        for episode in regular {
            guard let number = episode.episode, byNumber[number] == nil else { return original }
            byNumber[number] = episode
        }
        let numeric = entries.compactMap { key, value -> (Int, JSONValue)? in
            guard let number = Int(key), number > 0, (value["seasonNumber"].integer ?? 1) > 0 else { return nil }
            return (number, value)
        }
        var coordinates: [String: Int] = [:]
        var ambiguous = Set<String>()
        for (number, value) in numeric {
            guard let season = value["seasonNumber"].integer, let episode = value["episodeNumber"].integer, season > 0, episode > 0 else { continue }
            let key = "\(season):\(episode)"
            if coordinates[key] != nil { ambiguous.insert(key) }
            coordinates[key] = number
        }
        let ordinary = original.filter { ($0.season ?? 1) > 0 }
        let sourceNumbers = ordinary.compactMap(\.episode)
        let uniqueNumbers = Set(sourceNumbers).count == ordinary.count
        let sourceAlreadyCanonical = Set(ordinary.compactMap(\.season)).count == 1 && uniqueNumbers && Set(sourceNumbers) == Set(byNumber.keys)
        let numbers = original.map { episode -> Int? in
            guard (episode.season ?? 1) > 0 else { return nil }
            if (animeIdentity && uniqueNumbers) || sourceAlreadyCanonical, let number = episode.episode, byNumber[number] != nil { return number }
            guard !ambiguous.contains(episode.watchedKey) else { return nil }
            return coordinates[episode.watchedKey]
        }
        let ordinaryCount = ordinary.count
        let resolved = numbers.compactMap { $0 }
        let complete = !regular.isEmpty && ordinaryCount == regular.count && resolved.count == ordinaryCount && Set(resolved) == Set(byNumber.keys)
        let singleSeason = Set(regular.compactMap(\.season)) == [1]
        let mappingIDs = mapping["mappings"]
        let hunter = mappingIDs["kitsu_id"].integer == 6448 || mappingIDs["mal_id"].integer == 11061
            || mappingIDs["anilist_id"].integer == 11061 || mappingIDs["anidb_id"].integer == 8550
            || mappingIDs["thetvdb_id"].integer == 252322 || mappingIDs["imdb_id"].string == "tt2098220"
            || mappingIDs["themoviedb_id"].textValue == "46298"
        var usedTVDB = Set(original.compactMap(\.tvdbEpisodeID)), usedAbsolute = Set(original.compactMap(\.absoluteNumber))
        return zip(original, numbers).map { source, number in
            guard let number, let reference = byNumber[number], let entry = entries[String(number)] else { return source }
            var result = source
            if complete && singleSeason { result.displaySeason = 1; result.displayEpisode = number }
            let absolute = entry["absoluteEpisodeNumber"].integer.flatMap { $0 > 0 ? $0 : nil }
            // Preserve the reference's scoped defense against the known HxH
            // mapping whose titles and episode identities refer to different arcs.
            if hunter, let absolute, absolute != number {
                if result.runtime == nil { result.runtime = entry["runtime"].numericValue }
                return result
            }
            let mappedSeason = entry["seasonNumber"].integer, mappedNumber = entry["episodeNumber"].integer
            let sourceSeason = source.imdbSeason ?? source.season ?? 1, sourceNumber = source.imdbEpisode ?? source.episode
            let shifted = (mappedSeason == 0 && sourceSeason > 0)
                || (mappedSeason == sourceSeason && (mappedSeason ?? 0) > 0 && mappedNumber != nil && mappedNumber != sourceNumber)
            let tvdbID = entry["tvdbId"].integer.flatMap { $0 > 0 ? $0 : nil }
            let duplicateTVDB = tvdbID.map { usedTVDB.contains($0) && source.tvdbEpisodeID != $0 } ?? false
            let duplicateAbsolute = absolute.map { usedAbsolute.contains($0) && source.absoluteNumber != $0 } ?? false
            if !shifted && !duplicateTVDB && !duplicateAbsolute {
                if let tvdbID { result.tvdbEpisodeID = tvdbID; usedTVDB.insert(tvdbID) }
                if let absolute { result.absoluteNumber = absolute; usedAbsolute.insert(absolute) }
            }
            result.tvdbSeriesID = mappingIDs["thetvdb_id"].integer.flatMap { $0 > 0 ? $0 : nil }
            if !shifted, let mappedSeason, mappedSeason >= 0, let mappedNumber, mappedNumber > 0 {
                if result.imdbSeason == nil { result.imdbSeason = mappedSeason }
                if result.imdbEpisode == nil { result.imdbEpisode = mappedNumber }
                if let imdb = mappingIDs["imdb_id"].string, imdb.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil {
                    result.imdbID = imdb
                    result.verifiedIMDBCoordinates = result.imdbSeason == mappedSeason && result.imdbEpisode == mappedNumber
                }
            }
            // Actual episode artwork takes precedence over generated Metahub
            // URLs whose older season mapping may now return 404.
            if let image = imageURL(entry["image"].string) { result.thumbnail = image }
            else if result.thumbnail == nil { result.thumbnail = imageURL(reference.thumbnail) }
            return result
        }
    }

    private static func imageURL(_ raw: String?) -> String? {
        guard let raw, let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        return raw
    }
}
