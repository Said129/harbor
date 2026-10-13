import Foundation

/// Desktop queries an anime identity and its verified, aligned IMDb episode.
/// Never infer an anime season from its display number: split cours can differ.
enum StreamRequestPolicy {
    static func ids(_ media: Media, videoID: String, season: Int?, episode: Int?) -> [String] {
        var result = [videoID]
        let selected = media.videos?.first { $0.id == videoID }
        let anime = AnimeService.isAnime(media.id) || videoID.hasPrefix("kitsu:")
        let imdb = selected?.imdbID ?? media.imdbID
        if let imdb, imdb.range(of: "^tt[0-9]{7,}$", options: .regularExpression) != nil {
            if let episode {
                let mappedEpisode = selected?.imdbEpisode
                let mappedSeason = selected?.imdbSeason
                if !anime || (mappedEpisode == episode && mappedSeason != nil) {
                    result.append("\(imdb):\(mappedSeason ?? season ?? 1):\(mappedEpisode ?? episode)")
                }
            } else { result.append(imdb) }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    static func plans(_ plans: [RequestPlan]) -> [RequestPlan] {
        // One request per accepted scheme, like Desktop's pickIds. An addon
        // accepting both Kitsu and IMDb must receive both, not just the first.
        var seen = Set<String>()
        return plans.filter { seen.insert($0.key).inserted }
    }

    static func deduplicated(_ streams: [JSONValue]) -> [JSONValue] {
        var seen = Set<String>()
        return streams.filter { stream in
            let identity: String
            if let hash = stream["infoHash"].string { identity = "hash:" + hash.lowercased() + ":" + (stream["fileIdx"].textValue ?? "") }
            else if let url = stream["url"].string { identity = "url:" + url }
            else { identity = "name:" + (stream["name"].string ?? "") + ":" + (stream["title"].string ?? "") }
            return seen.insert((stream["addonId"].string ?? "") + ":" + identity).inserted
        }
    }
}
