import Foundation

struct TraktWatchedState: Codable, Equatable, Sendable {
    let at: Date
    var keys: Set<String>
    init(at: Date, history: JSONValue) throws {
        self.at = at; keys = []
        for item in try TraktLibraryItem.history(history) {
            for prefix in Self.prefixes(item.ids) {
                if item.type == .movie { keys.insert(prefix) }
                else if let season = item.season, let episode = item.episode, season >= 0, episode > 0 { keys.insert("\(prefix):\(season):\(episode)") }
            }
        }
    }
    init(at: Date, keys: Set<String>) { self.at = at; self.keys = keys }
    func fresh(_ now: Date) -> Bool { now.timeIntervalSince(at) <= 86_400 }
    private static func prefixes(_ ids: TrackerShowIDs) -> [String] {
        var result: [String] = []
        if let imdb = ids.json["imdb"].string { result.append("imdb:" + imdb) }
        if let tmdb = ids.json["tmdb"].integer { result.append("tmdb:\(tmdb)") }; return result
    }
    static func prefixes(_ media: Media) -> [String] {
        var ids: [String: JSONValue] = [:]
        if let target = TraktLibraryTarget(media) { ids = target.ids.json.objectValue }
        if let imdb = media.imdbID { ids["imdb"] = .string(imdb) }; return prefixes(.init(.object(ids)))
    }
    func movie(_ media: Media) -> Bool { Self.prefixes(media).contains { keys.contains($0) } }
    func episodes(_ media: Media) -> Set<String> {
        let prefixes = Self.prefixes(media)
        var result = Set<String>()
        for episode in media.videos ?? [] {
            guard let season = episode.season, let number = episode.episode else { continue }
            var canonicalSeason = season, canonicalEpisode = number
            if let value = episode.imdbSeason { canonicalSeason = value }
            if let value = episode.imdbEpisode { canonicalEpisode = value }
            let mapped = episode.imdbID.flatMap { TrackerShowIDs(.object(["imdb": .string($0)])).json["imdb"].string }
            let anime = ["kitsu:", "mal:", "anilist:", "anidb:"].contains { media.id.hasPrefix($0) }
            let aliases = mapped.map { ["imdb:" + $0] } ?? (anime ? [] : prefixes)
            if aliases.contains(where: { keys.contains("\($0):\(canonicalSeason):\(canonicalEpisode)") }) { result.insert(episode.watchedKey) }
        }
        return result
    }
    mutating func record(_ target: TraktWatchTarget) {
        for prefix in Self.prefixes(target.ids) {
            if target.kind == .movie { keys.insert(prefix) }
            else if target.kind == .episode, let season = target.season, let number = target.number { keys.insert("\(prefix):\(season):\(number)") }
        }
    }
}
