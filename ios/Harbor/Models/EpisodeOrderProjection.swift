import Foundation

struct EpisodeOrderSection: Identifiable, Sendable {
    let id: String
    let number: Int
    let name: String?
    let joined: Bool
    let extra: Bool
    let episodes: [Episode]
    let from: String?
    let to: String?
    let rows: [EpisodeOrderRow]
    var count: Int { rows.count }
    init(id: String, number: Int, name: String?, joined: Bool, extra: Bool, episodes: [Episode], from: String?, to: String?, rows: [EpisodeOrderRow]? = nil) {
        self.id = id; self.number = number; self.name = name; self.joined = joined; self.extra = extra
        self.episodes = episodes; self.from = from; self.to = to; self.rows = rows ?? episodes.map(EpisodeOrderRow.episode)
    }
}

/// Presentation and navigation reference real provider IDs. The source array
/// stays in its original order for Stremio's watched-bit encoding.
struct EpisodeOrderProjection: Sendable {
    let kind: TVDBEpisodeOrderKind
    let sections: [EpisodeOrderSection]
    let videos: [Episode]
    let unmatchedProviderIDs: [Int]
    let unmatchedFranchiseSourceKeys: [String]
    private let orderedIDs: [String]
    private let regularIDs: Set<String>
    private let sequences: [String: [String]]

    func applies(to source: [Episode]) -> Bool { Set(source.map(\.routingKey)) == Set(orderedIDs) }
    func ordered(_ source: [Episode]) -> [Episode]? {
        guard applies(to: source) else { return nil }
        var byID: [String: Episode] = [:]
        for episode in source where byID[episode.routingKey] == nil { byID[episode.routingKey] = episode }
        return orderedIDs.compactMap { byID[$0] }
    }
    func isRegular(_ id: String) -> Bool { regularIDs.contains(id) }
    func sequence(containing id: String) -> Set<String>? { sequences[id].map { Set($0) } }

    static func build(_ order: TVDBEpisodeOrder, source: [Episode], animeIdentity: Bool, currentSourceID: String? = nil, franchise: [AnimeFranchiseEntry] = []) -> Self? {
        var byID: [String: Episode] = [:]
        for episode in source where byID[episode.routingKey] == nil { byID[episode.routingKey] = episode }
        let distinct = source.filter { byID.removeValue(forKey: $0.routingKey) != nil }
        let compatible = distinct.filter { $0.tvdbSeriesID == nil || $0.tvdbSeriesID == order.seriesID }
        let pairs = Dictionary(grouping: compatible.compactMap { episode -> (String, Episode)? in
            if let season = episode.imdbSeason, let number = episode.imdbEpisode { return ("\(season):\(number)", episode) }
            guard !animeIdentity, let season = episode.season, let number = episode.episode else { return nil }
            return ("\(season):\(number)", episode)
        }, by: { $0.0 })
        let regular = compatible.filter { ($0.season ?? 1) > 0 }
        let slots = order.seasons.flatMap(\.episodes).filter { $0.canonicalSeason > 0 }
        let numbers = regular.compactMap(\.episode), absolute = slots.compactMap(\.absolute)
        // A cour's local 1...12 must not be mistaken for the franchise's 1...131.
        let wholeAbsoluteIdentity = animeIdentity && !regular.isEmpty && Set(regular.compactMap(\.sourceMetaID)).count <= 1 && Set(regular.compactMap(\.season)).count == 1
            && numbers.count == regular.count && Set(numbers).count == regular.count
            && absolute.count == regular.count && Set(absolute) == Set(numbers)
        let byAbsolute = Dictionary(grouping: regular, by: { $0.episode ?? 0 })
        let explicitAbsolute = Dictionary(grouping: compatible.compactMap { episode in episode.absoluteNumber.map { ($0, episode) } }, by: { $0.0 })
        let tvdbIDs = Dictionary(grouping: compatible.compactMap { episode in episode.tvdbEpisodeID.map { ($0, episode) } }, by: { $0.0 })
        var claimed = Set<String>(), projected: [String: Episode] = [:], sections: [EpisodeOrderSection] = [], missing: [Int] = []
        var claimedExtras = Set<String>()
        func candidate(_ values: [Episode]?) -> Episode? {
            guard let values, !values.isEmpty else { return nil }
            // Overlapping franchise entries retain insertion priority. Two
            // conflicting rows inside one source remain ambiguous.
            guard values.count == 1 || (values.allSatisfy { $0.sourceMetaID != nil }
                && Set(values.compactMap(\.sourceMetaID)).count == values.count) else { return nil }
            return values.first { !claimed.contains($0.routingKey) }
        }
        for season in order.seasons where season.id >= 0 {
            var episodes: [Episode] = [], rows: [EpisodeOrderRow] = []
            for (index, slot) in season.episodes.enumerated() {
                let pair = candidate(pairs["\(slot.canonicalSeason):\(slot.canonicalEpisode)"]?.map { $0.1 })
                let tvdb = candidate(tvdbIDs[slot.id]?.map { $0.1 })
                let absolute = candidate(slot.absolute.flatMap { explicitAbsolute[$0]?.map { $0.1 } }
                    ?? (wholeAbsoluteIdentity ? slot.absolute.flatMap { byAbsolute[$0] } : nil))
                let pairNumber: Int? = pair?.imdbEpisode ?? pair?.episode
                let tvdbNumber: Int? = tvdb?.imdbEpisode ?? tvdb?.episode
                let pairCorrectsStaleID = pair != nil && tvdb != nil && pair?.routingKey != tvdb?.routingKey
                    && pairNumber == slot.canonicalEpisode && tvdbNumber != slot.canonicalEpisode
                guard var episode = (pairCorrectsStaleID ? pair : tvdb) ?? pair ?? absolute,
                      claimed.insert(episode.routingKey).inserted else {
                    if let extra = AnimeFranchiseExtra.match(slot, entries: franchise, claimed: claimedExtras) {
                        claimedExtras.insert(extra.entry.id); rows.append(.franchise(extra)); continue
                    }
                    missing.append(slot.id); continue
                }
                if order.kind.joined {
                    episode.displaySeason = 1
                    episode.displayEpisode = order.kind == .absolute ? index + 1 : slot.absolute ?? index + 1
                } else { episode.displaySeason = slot.season; episode.displayEpisode = slot.number }
                if !slot.name.isEmpty { episode.name = slot.name; episode.title = nil }
                if !slot.overview.isEmpty { episode.overview = slot.overview }
                let host = episode.thumbnail.flatMap(URL.init(string:))?.host?.lowercased()
                if episode.thumbnail == nil || host == "images.metahub.space", let image = slot.image { episode.thumbnail = image }
                if episode.released == nil { episode.released = slot.aired }
                if episode.runtime == nil { episode.runtime = slot.runtime.map(Double.init) }
                projected[episode.routingKey] = episode; episodes.append(episode); rows.append(.episode(episode))
            }
            if !rows.isEmpty {
                sections.append(EpisodeOrderSection(id: String(season.id), number: season.id, name: season.name, joined: season.joined,
                    extra: season.id == 0, episodes: episodes, from: season.from, to: season.to, rows: rows))
            }
        }
        guard !claimed.isEmpty || !claimedExtras.isEmpty else { return nil }
        let unmatched = distinct.filter { !claimed.contains($0.routingKey) }
        // Desktop's Extras bucket keeps the current source's unmatched rows.
        // Unplaced siblings belong to their own entry, not this TVDB show's Extras.
        let leftovers = WatchedCodec.ordered(unmatched.filter { episode in
            currentSourceID == nil || episode.sourceMetaID == nil || episode.sourceMetaID == currentSourceID
        })
        let leftoverKeys = Set(leftovers.map(\.routingKey))
        let unplacedFranchise = unmatched.filter { !leftoverKeys.contains($0.routingKey) }.map(\.routingKey)
        if !leftovers.isEmpty {
            let dates = leftovers.compactMap(\.released).filter { !$0.isEmpty }
            sections.append(EpisodeOrderSection(id: "extras", number: 0, name: nil, joined: false, extra: true,
                episodes: leftovers, from: dates.min(), to: dates.max()))
        }
        let main = sections.filter { !$0.extra }.flatMap(\.episodes).map(\.routingKey)
        var sequences: [String: [String]] = [:]
        for id in main { sequences[id] = main }
        for section in sections where section.extra {
            let ids = section.episodes.map(\.routingKey)
            for id in ids { sequences[id] = ids }
        }
        let videos = source.compactMap { episode in projected[episode.routingKey] ?? (leftoverKeys.contains(episode.routingKey) ? episode : nil) }
        return Self(kind: order.kind, sections: sections, videos: videos, unmatchedProviderIDs: missing, unmatchedFranchiseSourceKeys: unplacedFranchise,
            orderedIDs: sections.flatMap(\.episodes).map(\.routingKey), regularIDs: Set(main), sequences: sequences)
    }
}
