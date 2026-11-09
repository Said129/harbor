import Foundation

/// Desktop queries an anime identity and its verified, aligned IMDb episode.
/// Never infer an anime season from its display number: split cours can differ.
enum StreamRequestPolicy {
    private static let uncachedMarker = try! NSRegularExpression(pattern: #"\b(?:rd|ad|pm|dl|tb|oc)\s*download\b|\buncached\b|[⬇⏳⌛⏬🔽📥☁]"#, options: .caseInsensitive)
    private static let hostedTorrentIdentity = try! NSRegularExpression(pattern: #"(?:^|[/=])([a-fA-F0-9]{40})(?:/(\d+))?(?=[/?#]|$)"#)

    static func ids(_ media: Media, videoID: String, season: Int?, episode: Int?) -> [String] {
        var result = [videoID]
        let selected = media.videos?.first { $0.id == videoID }
        let anime = AnimeService.isAnime(media.id) || videoID.hasPrefix("kitsu:")
        let imdb = selected?.imdbID ?? media.imdbID
        if let imdb, imdb.range(of: "^tt[0-9]{7,}$", options: .regularExpression) != nil {
            if let episode {
                let mappedEpisode = selected?.imdbEpisode
                let mappedSeason = selected?.imdbSeason
                if !anime || (mappedSeason != nil && (mappedEpisode == episode || selected?.verifiedIMDBCoordinates == true)) {
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

    static func hasStandardScheme(_ id: String) -> Bool {
        ["tt", "tmdb:", "kitsu:", "mal:", "anidb:", "anilist:", "tvdb:", "simkl:"].contains(where: id.hasPrefix)
    }

    static func declaredTypeID(_ ids: [String], addon: Addon) -> (id: String, types: [String])? {
        let priority = ["kitsu", "mal", "anidb", "anilist", "tt", "tmdb"]
        let ordered = ids.sorted { first, second in
            let left = priority.firstIndex(where: first.hasPrefix) ?? priority.count
            let right = priority.firstIndex(where: second.hasPrefix) ?? priority.count
            return left < right
        }
        for id in ordered {
            let types = AddonOriginPolicy.declaredStreamTypes(addon, id: id)
            if !types.isEmpty { return (id, types) }
        }
        return nil
    }

    /// Desktop recovers a missing torrent identity for an explicitly uncached
    /// addon response before it is deduplicated and checked for availability.
    static func recoveringUncachedIdentity(_ stream: JSONValue) -> JSONValue {
        guard stream["infoHash"].string?.isEmpty != false, case .object(var fields) = stream else { return stream }
        let label = ["name", "title", "description"].compactMap { stream[$0].string }.joined(separator: " ")
        guard uncachedMarker.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)) != nil else { return stream }
        if let url = stream["url"].string,
           let match = hostedTorrentIdentity.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
           let range = Range(match.range(at: 1), in: url) {
            fields["infoHash"] = .string(url[range].lowercased())
            if stream["fileIdx"] == .null, let range = Range(match.range(at: 2), in: url),
               let index = Int64(url[range]) { fields["fileIdx"] = .integer(index) }
            return .object(fields)
        }
        for entry in stream["sources"].array.compactMap(\.string) where entry.lowercased().hasPrefix("dht:") {
            let value = String(entry.dropFirst(4))
            guard value.utf8.count == 40, let hash = TorrentLink.parseMagnet(value)?.infoHash else { continue }
            fields["infoHash"] = .string(hash)
            return .object(fields)
        }
        return stream
    }

    static func deduplicated(_ streams: [JSONValue]) -> [JSONValue] {
        var indices: [String: Int] = [:]
        var result: [JSONValue] = []
        for stream in streams {
            let identity: String
            if let hash = stream["infoHash"].string { identity = "hash:" + hash.lowercased() + ":" + (stream["fileIdx"].textValue ?? "") }
            else if let url = stream["url"].string { identity = "url:" + url }
            else { identity = "name:" + (stream["name"].string ?? "") + ":" + (stream["title"].string ?? "") }
            let key = (stream["addonId"].string ?? "") + ":" + identity
            if let index = indices[key] {
                guard case .object(var fields) = result[index], !stream["sources"].array.isEmpty else { continue }
                var seen = Set<String>()
                let sources = (result[index]["sources"].array + stream["sources"].array).compactMap(\.string)
                fields["sources"] = .array(sources.filter { seen.insert($0).inserted }.map(JSONValue.string))
                result[index] = .object(fields)
            } else {
                indices[key] = result.count
                result.append(stream)
            }
        }
        return result
    }
}
