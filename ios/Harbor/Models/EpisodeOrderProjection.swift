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
}

/// Presentation and navigation reference real provider IDs. The source array
/// stays in its original order for Stremio's watched-bit encoding.
struct EpisodeOrderProjection: Sendable {
    let kind: TVDBEpisodeOrderKind
    let sections: [EpisodeOrderSection]
    let videos: [Episode]
    let unmatchedProviderIDs: [Int]
    private let orderedIDs: [String]
    private let regularIDs: Set<String>
    private let sequences: [String: [String]]

    func applies(to source: [Episode]) -> Bool { Set(source.map(\.id)) == Set(orderedIDs) }
    func ordered(_ source: [Episode]) -> [Episode]? {
        guard applies(to: source) else { return nil }
        var byID: [String: Episode] = [:]
        for episode in source where byID[episode.id] == nil { byID[episode.id] = episode }
        return orderedIDs.compactMap { byID[$0] }
    }
    func isRegular(_ id: String) -> Bool { regularIDs.contains(id) }
    func sequence(containing id: String) -> Set<String>? { sequences[id].map { Set($0) } }

    static func build(_ order: TVDBEpisodeOrder, source: [Episode], animeIdentity: Bool) -> Self? {
        var byID: [String: Episode] = [:]
        for episode in source where byID[episode.id] == nil { byID[episode.id] = episode }
        let distinct = source.filter { byID.removeValue(forKey: $0.id) != nil }
        let pairs = Dictionary(grouping: distinct.compactMap { episode -> (String, Episode)? in
            if let season = episode.imdbSeason, let number = episode.imdbEpisode { return ("\(season):\(number)", episode) }
            guard !animeIdentity, let season = episode.season, let number = episode.episode else { return nil }
            return ("\(season):\(number)", episode)
        }, by: { $0.0 })
        let regular = distinct.filter { ($0.season ?? 1) > 0 }
        let slots = order.seasons.flatMap(\.episodes).filter { $0.canonicalSeason > 0 }
        let numbers = regular.compactMap(\.episode), absolute = slots.compactMap(\.absolute)
        // A cour's local 1...12 must not be mistaken for the franchise's 1...131.
        let wholeAbsoluteIdentity = animeIdentity && !regular.isEmpty && Set(regular.compactMap(\.season)).count == 1
            && numbers.count == regular.count && Set(numbers).count == regular.count
            && absolute.count == regular.count && Set(absolute) == Set(numbers)
        let byAbsolute = Dictionary(grouping: regular, by: { $0.episode ?? 0 })
        var claimed = Set<String>(), projected: [String: Episode] = [:], sections: [EpisodeOrderSection] = [], missing: [Int] = []
        for season in order.seasons where season.id >= 0 {
            var episodes: [Episode] = []
            for (index, slot) in season.episodes.enumerated() {
                let pair = pairs["\(slot.canonicalSeason):\(slot.canonicalEpisode)"]?.map { $0.1 }
                let candidates = pair ?? (wholeAbsoluteIdentity ? slot.absolute.flatMap { byAbsolute[$0] } : nil)
                guard let candidates, candidates.count == 1, var episode = candidates.first, claimed.insert(episode.id).inserted else {
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
                projected[episode.id] = episode; episodes.append(episode)
            }
            if !episodes.isEmpty {
                sections.append(EpisodeOrderSection(id: String(season.id), number: season.id, name: season.name, joined: season.joined,
                    extra: season.id == 0, episodes: episodes, from: season.from, to: season.to))
            }
        }
        guard !claimed.isEmpty else { return nil }
        let leftovers = WatchedCodec.ordered(distinct.filter { !claimed.contains($0.id) })
        if !leftovers.isEmpty {
            let dates = leftovers.compactMap(\.released).filter { !$0.isEmpty }
            sections.append(EpisodeOrderSection(id: "extras", number: 0, name: nil, joined: false, extra: true,
                episodes: leftovers, from: dates.min(), to: dates.max()))
        }
        let main = sections.filter { !$0.extra }.flatMap(\.episodes).map(\.id)
        var sequences: [String: [String]] = [:]
        for id in main { sequences[id] = main }
        for section in sections where section.extra {
            let ids = section.episodes.map(\.id)
            for id in ids { sequences[id] = ids }
        }
        return Self(kind: order.kind, sections: sections, videos: source.map { projected[$0.id] ?? $0 }, unmatchedProviderIDs: missing,
            orderedIDs: sections.flatMap(\.episodes).map(\.id), regularIDs: Set(main), sequences: sequences)
    }
}
