import Foundation

struct VODEpisode: Identifiable, Sendable {
    let channel: LiveChannel
    let season: Int
    let episode: Int
    let title: String
    var plot: String?
    var id: String { channel.id }
}
struct VODMovie: Identifiable, Sendable {
    let channel: LiveChannel
    let title: String
    let year: Int?
    var id: String { channel.id }
    var media: Media { Media(id: "vod:" + EBookShelf.hash(id), type: "movie", name: title, poster: channel.logo, background: channel.logo, description: channel.group, releaseInfo: year.map(String.init)) }
}
struct VODSeries: Identifiable, Sendable {
    let id: String
    let source: String
    let title: String
    let logo: String?
    let group: String?
    let xtreamID: String?
    var episodes: [VODEpisode]
    var media: Media { Media(id: "vod:" + EBookShelf.hash(id), type: "series", name: title, poster: logo, background: logo, description: group) }
}
struct VODLibrary: Sendable {
    var movies: [VODMovie] = []
    var series: [VODSeries] = []
    static func build(_ channels: [LiveChannel]) throws -> Self {
        var result = Self(), seen = Set<String>(), seenChannels = Set<String>(), shows: [String: VODSeries] = [:]
        for channel in channels {
            try Task.checkCancellation()
            guard seenChannels.insert(channel.id).inserted else { continue }
            switch VODTitles.kind(channel) {
            case "movie":
                let title = VODTitles.clean(channel.name), year = VODTitles.year(channel.name)
                let key = channel.source + "|" + VODTitles.normalized(title) + "|" + String(year ?? 0)
                if seen.insert(key).inserted { result.movies.append(VODMovie(channel: channel, title: title, year: year)) }
            case "series":
                let title = VODTitles.show(channel.name), xtream = channel.attributes["xtream-series-id"]
                let id = channel.source + "|" + (xtream.map { "xtream:" + $0 } ?? VODTitles.normalized(title))
                var series = shows[id] ?? VODSeries(id: id, source: channel.source, title: title, logo: channel.logo, group: channel.group, xtreamID: xtream, episodes: [])
                if xtream == nil {
                    let number = VODTitles.number(channel.name)
                    series.episodes.append(VODEpisode(channel: channel, season: number?.0 ?? 1, episode: number?.1 ?? 0, title: VODTitles.clean(channel.name)))
                }
                shows[id] = series
            default: break
            }
        }
        result.series = shows.values.map { original in
            var item = original
            let fallback = item.episodes.filter { $0.episode == 0 }.sorted { $0.channel.url < $1.channel.url }
            let numbers = Dictionary(uniqueKeysWithValues: fallback.enumerated().map { ($0.element.id, $0.offset + 1) })
            item.episodes = item.episodes.map { $0.episode == 0 ? VODEpisode(channel: $0.channel, season: $0.season, episode: numbers[$0.id] ?? 1, title: $0.title, plot: $0.plot) : $0 }.sorted { $0.season == $1.season ? $0.episode < $1.episode : $0.season < $1.season }
            return item
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        result.movies.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return result
    }
}

// These precedence and title-cleaning rules follow Desktop's vod-classify/title.
enum VODTitles {
    private static let season = #"\bS(\d{1,2})\s*[._\-\s]?\s*E(\d{1,3})\b"#
    private static let alternate = #"\b(\d{1,2})x(\d{1,3})\b"#
    private static let yearPattern = #"\b(19\d{2}|20\d{2})\b"#
    private static let noise = #"\b(2160p|1080p|720p|480p|4k|uhd|fhd|hd|sd|hevc|x265|x264|h\.?264|h\.?265|web-?dl|web-?rip|bluray|blu-?ray|bdrip|hdrip|dvdrip|hdtv|multi|dual|multi-?sub|subbed|dubbed|imax|remux|10bit|aac|ac3|eac3|dts|ddp?5\.?1|hdr10?|dolby|atmos|vision)\b"#
    private static let seriesGroup = #"\b(serie|series|s[ée]ries|tv ?show|tv ?shows|staffel|temporada)\b"#
    private static let movieGroup = #"\b(vod|movie|movies|film|films|cinema|pel[ií]culas?|filme)\b"#
    private struct ExpressionBank: @unchecked Sendable {
        // Regex objects are immutable after construction and only match text.
        let values: [String: NSRegularExpression]
        init(_ patterns: [String]) {
            var values: [String: NSRegularExpression] = [:]
            for pattern in patterns {
                values[pattern + "|i"] = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                values[pattern + "|s"] = try! NSRegularExpression(pattern: pattern)
            }
            self.values = values
        }
    }
    private static let bank = ExpressionBank([season, alternate, yearPattern, noise, seriesGroup, movieGroup, #"/series/"#, #"/movie/"#, #"/live/"#, #"\.(mkv|mp4|avi|m4v|mov|flv|wmv|mpg|mpeg|webm)(\?|$)"#, #"\.(ts|m3u8)(\?|$)"#, #"[\[(][^\])]*[\])]"#, #"[._]+"#, #"\s{2,}"#, #"[\-|:]+\s*$|^[\-|:]+\s*"#, #"\s*[-|:]?\s*\b(?:episode|ep|part|pt)\b\s*\.?\s*\d{1,3}\s*$"#, #"^(.*\S)\s+[-|:]\s+\S.*$"#, #"[^a-z0-9]+"#, #"^\s*(?:[A-Z]{2,4}|[\x{1F1E6}-\x{1F1FF}]{2})\s*[|\-:]\s*"#, #"^(.{1,14}?)\s+[|\-:]\s+(.+)$"#, #"^[^a-zÀ-￿]{1,14}$"#])
    static func kind(_ channel: LiveChannel) -> String {
        let declared = (channel.attributes["tvg-type"] ?? channel.attributes["type"] ?? "").lowercased()
        if ["movie", "series"].contains(declared) { return declared }
        let url = channel.url, group = channel.group ?? ""
        if match(#"/series/"#, url) != nil { return "series" }
        if match(#"/movie/"#, url) != nil { return "movie" }
        if match(#"/live/"#, url) != nil { return "live" }
        let vod = match(#"\.(mkv|mp4|avi|m4v|mov|flv|wmv|mpg|mpeg|webm)(\?|$)"#, url) != nil
        let live = match(#"\.(ts|m3u8)(\?|$)"#, url) != nil
        let series = match(seriesGroup, group) != nil
        if !(vod && !live && !series), number(channel.name) != nil { return "series" }
        if series && !live { return "series" }
        if match(movieGroup, group) != nil && !live { return "movie" }
        return vod && !live ? "movie" : "live"
    }
    static func number(_ name: String) -> (Int, Int)? {
        for pattern in [season, alternate] {
            if let found = match(pattern, name), let first = Range(found.range(at: 1), in: name), let second = Range(found.range(at: 2), in: name), let season = Int(name[first]), let episode = Int(name[second]) { return (season, episode) }
        }
        return nil
    }
    static func year(_ name: String) -> Int? { match(yearPattern, name).flatMap { Range($0.range(at: 1), in: name) }.flatMap { Int(name[$0]) } }
    static func clean(_ name: String) -> String {
        var value = tags(name)
        for pattern in [#"[\[(][^\])]*[\])]"#, season, alternate, yearPattern, noise, #"[._]+"#, #"\s{2,}"#] { value = replace(pattern, value, " ") }
        value = replace(#"[\-|:]+\s*$|^[\-|:]+\s*"#, value, "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? name.trimmingCharacters(in: .whitespacesAndNewlines) : value
    }
    static func show(_ name: String) -> String {
        if let found = match(season, name) ?? match(alternate, name), let range = Range(found.range, in: name) { return clean(String(name[..<range.lowerBound])) }
        let shortened = replace(#"\s*[-|:]?\s*\b(?:episode|ep|part|pt)\b\s*\.?\s*\d{1,3}\s*$"#, name, "").trimmingCharacters(in: .whitespaces)
        if shortened != name.trimmingCharacters(in: .whitespaces), !shortened.isEmpty { return clean(shortened) }
        let tagged = tags(name)
        if let found = match(#"^(.*\S)\s+[-|:]\s+\S.*$"#, tagged), let range = Range(found.range(at: 1), in: tagged) { let title = String(tagged[range]); if !isTag(title) { return clean(title) } }
        return clean(name)
    }
    static func normalized(_ title: String) -> String {
        let ascii = replace(#"[^a-z0-9]+"#, title.lowercased(), "-").trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return ascii.isEmpty ? EBookShelf.hash(title.lowercased()) : ascii
    }
    private static func tags(_ name: String) -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<4 {
            let next = replace(#"^\s*(?:[A-Z]{2,4}|[\x{1F1E6}-\x{1F1FF}]{2})\s*[|\-:]\s*"#, value, "", insensitive: false)
            if next != value { value = next; continue }
            guard let found = match(#"^(.{1,14}?)\s+[|\-:]\s+(.+)$"#, value, insensitive: false), let first = Range(found.range(at: 1), in: value), let second = Range(found.range(at: 2), in: value), isTag(String(value[first]).trimmingCharacters(in: .whitespaces)) else { break }
            value = String(value[second]).trimmingCharacters(in: .whitespaces)
        }
        return value
    }
    private static func isTag(_ name: String) -> Bool { match(#"^[^a-zÀ-￿]{1,14}$"#, name, insensitive: false) != nil }
    private static func match(_ pattern: String, _ value: String, insensitive: Bool = true) -> NSTextCheckingResult? { bank.values[pattern + (insensitive ? "|i" : "|s")]?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) }
    private static func replace(_ pattern: String, _ value: String, _ replacement: String, insensitive: Bool = true) -> String { bank.values[pattern + (insensitive ? "|i" : "|s")]?.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: replacement) ?? value }
}
