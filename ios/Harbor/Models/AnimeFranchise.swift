import Foundation

struct AnimeFranchiseEntry: Codable, Hashable, Identifiable, Sendable {
    var media: Media
    let year: Int
    let startDate: String?
    let episodeCount: Int?
    let subtype: String?
    var current: Bool
    let upcoming: Bool
    var id: String { media.id }
    var extra: Bool {
        if media.type == "movie" || ["ona", "ova", "special", "music", "one_shot"].contains(subtype?.lowercased() ?? "") { return true }
        return episodeCount == 1 && !(media.type == "series" && (current || upcoming))
    }

    static func kitsu(_ resource: JSONValue, currentID: Int, now: Date) -> Self? {
        guard resource["type"].string == "anime", let id = positiveID(resource["id"]),
              case .object = resource["attributes"] else { return nil }
        let value = resource["attributes"]
        let title = nonempty(value["titles"]["en"].string, value["canonicalTitle"].string, value["titles"]["en_jp"].string) ?? "Unknown"
        let subtype = value["subtype"].string?.lowercased()
        let start = value["startDate"].string.flatMap { $0.isEmpty ? nil : $0 }
        let year = start.flatMap { Int($0.prefix(4)) } ?? 0
        var media = Media(id: "kitsu:\(id)", type: subtype == "movie" ? "movie" : "series", name: title)
        media.poster = image(value["posterImage"]["large"].string, value["posterImage"]["original"].string, value["posterImage"]["medium"].string)
        media.background = image(value["coverImage"]["original"].string, value["coverImage"]["large"].string, value["coverImage"]["small"].string)
        media.description = value["synopsis"].string ?? value["description"].string
        media.releaseInfo = year > 0 ? String(year) : nil
        if let score = value["averageRating"].textValue.flatMap(Double.init), score > 0, score <= 100 {
            media.imdbRating = String(format: "%.1f", score / 10); media.ratingSource = "Kitsu"
        }
        let status = value["status"].string?.lowercased() ?? ""
        let future = ["unreleased", "upcoming", "tba"].contains(status) || start.flatMap { ISO8601DateParser.shared.date($0 + "T00:00:00Z") }.map { $0 > now } == true
        return Self(media: media, year: year, startDate: start, episodeCount: value["episodeCount"].integer,
            subtype: subtype, current: id == currentID, upcoming: future)
    }

    static func anilist(_ value: JSONValue) -> Self? {
        guard let id = positiveID(value["id"]), let title = nonempty(value["title"]["english"].string, value["title"]["romaji"].string, value["title"]["userPreferred"].string) else { return nil }
        let format = value["format"].string
        let date = value["startDate"], year = value["seasonYear"].integer ?? date["year"].integer ?? 0
        var media = Media(id: "anilist:\(id)", type: format == "MOVIE" ? "movie" : "series", name: title)
        media.poster = image(value["coverImage"]["large"].string); media.background = image(value["bannerImage"].string)
        media.description = value["description"].string?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        media.releaseInfo = year > 0 ? String(year) : nil
        if let score = value["averageScore"].numericValue, score > 0, score <= 100 {
            media.imdbRating = String(format: "%.1f", score / 10); media.ratingSource = "AniList"
        }
        let start = date["year"].integer.flatMap { $0 > 0 ? String(format: "%04d-%02d-%02d", $0, date["month"].integer ?? 1, date["day"].integer ?? 1) : nil }
        return Self(media: media, year: year, startDate: start, episodeCount: value["episodes"].integer, subtype: format,
            current: false, upcoming: value["status"].string == "NOT_YET_RELEASED")
    }

    static func positiveID(_ value: JSONValue) -> Int? {
        if let id = value.integer, id > 0 { return id }
        guard let text = value.string, !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let id = Int(text), id > 0 else { return nil }
        return id
    }
    private static func nonempty(_ values: String?...) -> String? { values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } }
    private static func image(_ values: String?...) -> String? {
        values.compactMap { $0 }.first { raw in
            guard let url = URL(string: raw) else { return false }
            return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
        }
    }
}

struct AnimeFranchise: Sendable {
    let currentID: String
    let rootID: String
    let entries: [AnimeFranchiseEntry]
    let complete: Bool
    var scopedSplit: Bool { rootID == "kitsu:244" }
    var soloEntry: Bool { scopedSplit && currentID != rootID }

    static func merged(_ input: [AnimeFranchiseEntry]) -> [AnimeFranchiseEntry] {
        var byName: [String: AnimeFranchiseEntry] = [:], order: [String] = []
        for entry in input {
            let key = normalizedName(entry.media.name)
            guard !key.isEmpty else { continue }
            if byName[key] == nil { order.append(key) }
            if byName[key].map({ score(entry) > score($0) }) ?? true { byName[key] = entry }
        }
        var ids = Set<String>()
        return order.compactMap { byName[$0] }.filter {
            ($0.current || $0.upcoming || $0.startDate != nil || ($0.episodeCount ?? 0) > 0) && ids.insert($0.id).inserted
        }.enumerated().sorted { lhs, rhs in
            let first = lhs.element.startDate ?? "9999", second = rhs.element.startDate ?? "9999"
            return first == second ? lhs.offset < rhs.offset : first < second
        }.map(\.element)
    }

    static func normalizedName(_ name: String) -> String {
        var text = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[A-Z][A-Z0-9]{1,5}:\s*"#, with: "", options: .regularExpression).lowercased()
        for (word, number) in [("first", "1"), ("second", "2"), ("third", "3"), ("fourth", "4"), ("fifth", "5"), ("sixth", "6"), ("seventh", "7"), ("eighth", "8")] {
            text = text.replacingOccurrences(of: "\\b" + word + "\\b", with: number, options: .regularExpression)
        }
        let season = capture(#"(\d+)\s*(?:st|nd|rd|th)?\s*season|season\s*(\d+)"#, in: text)
        let part = capture(#"(\d+)\s*(?:st|nd|rd|th)?\s*(?:part|cour)|(?:part|cour)\s*(\d+)"#, in: text)
        let suffix = season == nil && part == nil ? capture(#"\s(\d{1,2})\s*$"#, in: text) : nil
        let number = [season, part].compactMap { $0 }.joined(separator: "p")
        let base = text.replacingOccurrences(of: #"\d+\s*(?:st|nd|rd|th)?\s*(?:season|part|cour)|(?:season|part|cour)\s*\d+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+\d{1,2}\s*$"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "ou", with: "o").replacingOccurrences(of: "oo", with: "o").replacingOccurrences(of: "uu", with: "u")
        let discriminator = number.isEmpty ? suffix ?? "" : number
        return discriminator.isEmpty ? base : base + "#" + discriminator
    }
    private static func score(_ entry: AnimeFranchiseEntry) -> Int {
        (entry.current ? 1000 : 0) + (entry.id.hasPrefix("kitsu:") ? 4 : 0) + (entry.startDate == nil ? 0 : 2) + ((entry.episodeCount ?? 0) > 0 ? 1 : 0)
    }
    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for index in 1..<match.numberOfRanges { if let range = Range(match.range(at: index), in: text) { return String(text[range]) } }
        return nil
    }
}
