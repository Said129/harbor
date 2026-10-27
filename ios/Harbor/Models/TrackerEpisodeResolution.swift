import Foundation

struct TrackerEpisodeIdentity: Codable, Equatable, Sendable {
    var showTitle: String
    var showYear: Int?
    var season: Int
    var number: Int
    var name: String?
    var airDate: String?
    var episodeTvdbId: Int?
    var episodeImdbId: String?
    var key: String {
        [TrackerEpisodeMatch.normalize(showTitle), showYear.map(String.init) ?? "", episodeTvdbId.map(String.init) ?? "",
         episodeImdbId ?? "", airDate ?? "", TrackerEpisodeMatch.normalize(name), String(season), String(number)].joined(separator: "|")
    }
}
struct TrackerShowIDs: Codable, Equatable, Sendable {
    let json: JSONValue
    init(_ raw: JSONValue) {
        var ids: [String: JSONValue] = [:]
        if let imdb = raw["imdb"].string, imdb.range(of: "^tt[0-9]+$", options: .regularExpression) != nil { ids["imdb"] = .string(imdb) }
        for key in ["tmdb", "tvdb", "trakt"] { if let value = raw[key].integer, value > 0 { ids[key] = .integer(Int64(value)) } }
        if let slug = raw["slug"].string, !slug.isEmpty, slug.utf8.count <= 200 { ids["slug"] = .string(slug) }
        json = .object(ids)
    }
    // A foreign TMDB/TVDB number must never be mistaken for a Trakt show id.
    var parameter: String? { json["trakt"].integer.map(String.init) ?? json["imdb"].string ?? json["slug"].string }
}
struct TrackerShowCandidate: Codable, Equatable, Sendable {
    let showIds: TrackerShowIDs
    let title: String
    let year: Int?
}
struct TrackerEpisodeCandidate: Codable, Equatable, Sendable {
    let number: Int
    var title: String?
    var airDate: String?
    var tvdbId: Int?
    var imdbId: String?
}
struct TrackerSeasonListing: Codable, Equatable, Sendable {
    let number: Int
    let episodes: [TrackerEpisodeCandidate]
}
struct TrackerResolvedEpisode: Codable, Equatable, Sendable {
    let showIds: TrackerShowIDs
    let season: Int
    let number: Int
    func simklHistoryBody(now: Date = Date()) -> JSONValue {
        .object(["shows": .array([.object(["ids": showIds.json, "seasons": .array([.object([
            "number": .integer(Int64(season)), "episodes": .array([.object([
                "number": .integer(Int64(number)), "watched_at": .string(ISO8601DateFormatter().string(from: now))])])])])])])])
    }
}
struct TrackerResolutionResult: Codable, Equatable, Sendable {
    let episode: TrackerResolvedEpisode?
    let reason: String?
    static let error = Self(episode: nil, reason: "error")
    static let notFound = Self(episode: nil, reason: "not-found")
    static func found(_ episode: TrackerResolvedEpisode) -> Self { .init(episode: episode, reason: nil) }
    var json: JSONValue {
        if let episode { return .object(["ok": .bool(true), "episode": .object([
            "showIds": episode.showIds.json, "season": .integer(Int64(episode.season)), "number": .integer(Int64(episode.number))])]) }
        return .object(["ok": .bool(false), "reason": .string(reason ?? "error")])
    }
}

/// Desktop 0.9.132 tracker-resolve/match.ts. Episode ids outrank title/date
/// guesses; a shared batch release date cannot identify a unique episode.
enum TrackerEpisodeMatch {
    static func normalize(_ value: String?) -> String {
        var text = (value ?? "").decomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "[\\u0300-\\u036f]", with: "", options: .regularExpression).lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("the ") { text = String(text.dropFirst(4)) }; return text
    }
    static func distinctive(_ value: String?) -> Bool {
        let text = normalize(value)
        return text.count >= 4 && text.range(of: "^(episode\\s*[0-9]+$|part\\s*[0-9]+$|chapter\\s*[0-9]+$|special\\b)", options: .regularExpression) == nil
    }
    static func days(_ first: String?, _ second: String?) -> Double? {
        func date(_ value: String?) -> Date? {
            guard var value, !value.isEmpty else { return nil }
            if value.count == 10 { value += "T00:00:00Z" }
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: value)
        }
        guard let first = date(first), let second = date(second) else { return nil }
        return abs(first.timeIntervalSince(second)) / 86_400
    }
    private static func sameID(_ identity: TrackerEpisodeIdentity, _ candidate: TrackerEpisodeCandidate) -> Bool {
        if let first = identity.episodeTvdbId, let second = candidate.tvdbId { return first == second }
        if let first = identity.episodeImdbId, let second = candidate.imdbId { return first == second }
        return false
    }
    private static func conflictingID(_ identity: TrackerEpisodeIdentity, _ candidate: TrackerEpisodeCandidate) -> Bool {
        if let first = identity.episodeTvdbId, let second = candidate.tvdbId { return first != second }
        if let first = identity.episodeImdbId, let second = candidate.imdbId { return first != second }
        return false
    }
    static func matches(_ identity: TrackerEpisodeIdentity, _ candidate: TrackerEpisodeCandidate) -> Bool {
        if sameID(identity, candidate) { return true }; if conflictingID(identity, candidate) { return false }
        if distinctive(identity.name) && distinctive(candidate.title) { return normalize(identity.name) == normalize(candidate.title) }
        return days(identity.airDate, candidate.airDate).map { $0 <= 3 } ?? false
    }
    static func comparable(_ identity: TrackerEpisodeIdentity, _ seasons: [TrackerSeasonListing]) -> Bool {
        seasons.contains { season in season.episodes.contains {
            sameID(identity, $0) || days(identity.airDate, $0.airDate) != nil || (distinctive(identity.name) && distinctive($0.title))
        } }
    }
    static func seasonOrder(_ target: Int) -> [Int] {
        var result: [Int] = []
        func add(_ value: Int) { if value >= 0 && !result.contains(value) { result.append(value) } }
        add(target); add(1); add(0)
        for distance in 1...5 { add(target - distance); add(target + distance) }; return result
    }
    private static func ordered(_ identity: TrackerEpisodeIdentity, _ seasons: [TrackerSeasonListing]) -> [(Int, TrackerEpisodeCandidate)] {
        var latest: [Int: TrackerSeasonListing] = [:]; for season in seasons { latest[season.number] = season }
        let order = seasonOrder(identity.season)
        let selected = order.compactMap { latest[$0] } + seasons.filter { !order.contains($0.number) }
        return selected.flatMap { season in season.episodes.map { (season.number, $0) } }
    }
    static func exact(_ identity: TrackerEpisodeIdentity, _ seasons: [TrackerSeasonListing]) -> (season: Int, number: Int)? {
        ordered(identity, seasons).first { sameID(identity, $0.1) }.map { ($0.0, $0.1.number) }
    }
    static func find(_ identity: TrackerEpisodeIdentity, _ seasons: [TrackerSeasonListing]) -> (season: Int, number: Int)? {
        let ordered = ordered(identity, seasons)
        if let hit = ordered.first(where: { sameID(identity, $0.1) }) { return (hit.0, hit.1.number) }
        let matching = ordered.filter { matches(identity, $0.1) }
        let titled = matching.filter { distinctive(identity.name) && distinctive($0.1.title) && normalize(identity.name) == normalize($0.1.title) }
        let hits = titled.isEmpty ? matching : titled
        return hits.count == 1 ? (hits[0].0, hits[0].1.number) : nil
    }
}
