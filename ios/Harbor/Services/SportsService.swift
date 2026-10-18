import Foundation

actor SportsService {
    static let shared = SportsService()
    private let base = "https://site.api.espn.com/apis/site/v2/sports/"
    private var cache: [String: (Date, [SportsEvent])] = [:]
    func savedEvents(_ league: SportsLeague, date: String) -> [SportsEvent]? { cache[league.id + ":" + date]?.1 }
    func events(_ league: SportsLeague, date: String, refresh: Bool) async throws -> [SportsEvent] {
        let key = league.id + ":" + date
        if !refresh, let entry = cache[key], Date().timeIntervalSince(entry.0) < 120 { return entry.1 }
        let data = try await HTTPClient().json(base + league.path + "/scoreboard?dates=" + date, timeout: 25)
        guard case .array(let raw) = data["events"] else { throw HarborError(code: "sports-response") }
        let result = Self.parse(raw, league: league)
        cache[key] = (Date(), result)
        if cache.count > 96, let oldest = cache.min(by: { $0.value.0 < $1.value.0 })?.key { cache[oldest] = nil }
        return result
    }
    func summary(_ event: SportsEvent) async throws -> SportsSummary {
        guard event.eventID.utf8.allSatisfy({ (48...57).contains($0) }), !event.eventID.isEmpty else { throw HarborError(code: "sports-response") }
        let data = try await HTTPClient().json(base + event.league.path + "/summary?event=" + event.eventID, timeout: 30)
        var summary = SportsSummary()
        for team in data["boxscore"]["teams"].array {
            let values = team["statistics"].array.enumerated().compactMap { index, value -> SportsStatistic? in
                guard let text = value["displayValue"].textValue, let title = value["label"].string ?? value["displayName"].string ?? value["name"].string else { return nil }
                return SportsStatistic(id: String(index), title: title, value: text)
            }
            if !values.isEmpty { summary.groups.append(SportsStatGroup(id: team["team"]["id"].textValue ?? String(summary.groups.count), title: team["team"]["displayName"].string ?? "Estadísticas", values: values)) }
        }
        for roster in data["boxscore"]["players"].array {
            for (index, group) in roster["statistics"].array.enumerated() {
                let labels = group["labels"].array.compactMap(\.string)
                let values = group["athletes"].array.compactMap { row -> SportsStatistic? in
                    guard let name = row["athlete"]["displayName"].string else { return nil }
                    let stats = row["stats"].array.compactMap(\.textValue)
                    let text = zip(labels, stats).map { $0 + " " + $1 }.joined(separator: " · ")
                    guard !text.isEmpty else { return nil }
                    return SportsStatistic(id: row["athlete"]["id"].textValue ?? name, title: name, value: text)
                }
                if !values.isEmpty { summary.groups.append(SportsStatGroup(id: "players-\(summary.groups.count)-\(index)", title: [roster["team"]["displayName"].string, group["text"].string ?? group["name"].string].compactMap { $0 }.joined(separator: " · "), values: values)) }
            }
        }
        let comments = data["commentary"].array.isEmpty ? data["plays"].array : data["commentary"].array
        summary.commentary = comments.suffix(100).compactMap { $0["text"].string ?? $0["comment"].string }
        return summary
    }
    nonisolated private static func parse(_ values: [JSONValue], league: SportsLeague) -> [SportsEvent] {
        var events: [SportsEvent] = [], seen = Set<String>()
        for value in values {
            guard let eventID = value["id"].textValue else { continue }
            var competitions: [JSONValue] = []
            for group in value["groupings"].array {
                let draw = group["grouping"]["displayName"].string ?? ""
                if league.path == "tennis/atp" && draw.lowercased().hasPrefix("women") || league.path == "tennis/wta" && draw.lowercased().hasPrefix("men") { continue }
                competitions.append(contentsOf: group["competitions"].array)
            }
            if competitions.isEmpty { competitions = value["competitions"].array }
            if !["combat", "tennis", "motorsport", "golf", "swimming", "athletics", "cycling"].contains(league.group) { competitions = Array(competitions.prefix(1)) }
            for competition in competitions {
                let id = league.id + ":" + eventID + ":" + (competition["id"].textValue ?? "0")
                guard seen.insert(id).inserted else { continue }
                let sides = competition["competitors"].array.compactMap { side($0, league: league) }
                guard !sides.isEmpty else { continue }
                let rawDate = competition["date"].string ?? value["date"].string ?? ""
                guard let date = isoDate(rawDate) else { continue }
                let state = competition["status"]["type"]["state"].string ?? value["status"]["type"]["state"].string ?? "pre"
                let detail = competition["status"]["type"]["detail"].string ?? value["status"]["type"]["detail"].string ?? ""
                var broadcasts = competition["broadcasts"].array.flatMap { $0["names"].array.compactMap(\.string) }
                broadcasts += competition["geoBroadcasts"].array.compactMap { $0["media"]["shortName"].string }
                var names = Set<String>(); broadcasts = broadcasts.filter { names.insert($0).inserted }
                let link = value["links"].array.compactMap { $0["href"].string }.first { raw in guard let url = URL(string: raw), url.scheme == "https", let host = url.host else { return false }; return host == "espn.com" || host.hasSuffix(".espn.com") }
                events.append(SportsEvent(id: id, eventID: eventID, league: league, title: competition["name"].string ?? value["name"].string ?? sides.map(\.name).joined(separator: " · "), date: date, state: state, status: detail, sides: sides, venue: competition["venue"]["fullName"].string ?? "", broadcasts: broadcasts, link: link))
            }
        }
        return events.sorted { a, b in let left = a.state == "in" ? 0 : a.state == "pre" ? 1 : 2, right = b.state == "in" ? 0 : b.state == "pre" ? 1 : 2; return left == right ? a.date < b.date : left < right }
    }
    nonisolated private static func side(_ value: JSONValue, league: SportsLeague) -> SportsSide? {
        let team = value["team"], athlete = value["athlete"], roster = value["roster"]
        guard let name = team["displayName"].string ?? athlete["displayName"].string ?? athlete["fullName"].string ?? roster["displayName"].string, !name.isEmpty else { return nil }
        let id = team["id"].textValue ?? athlete["id"].textValue ?? value["id"].textValue ?? name
        let logo = team["logo"].string ?? team["logos"].array.first?["href"].string ?? athlete["headshot"]["href"].string ?? athlete["flag"]["href"].string
        var score = value["score"]["displayValue"].textValue ?? value["score"]["value"].textValue ?? value["score"].textValue
        if score == nil && league.group == "tennis" && !value["linescores"].array.isEmpty { score = String(value["linescores"].array.filter { $0["winner"] == .bool(true) }.count) }
        if score == nil, ["motorsport", "golf", "cycling", "swimming", "athletics"].contains(league.group), let position = value["order"].integer { score = "#\(position)" }
        let periods = value["linescores"].array.enumerated().compactMap { index, line -> SportsPeriod? in
            guard let score = line["displayValue"].textValue ?? line["value"].textValue else { return nil }
            return SportsPeriod(id: line["period"].integer ?? index + 1, value: score)
        }
        return SportsSide(id: id, name: name, logo: logo, score: score, winner: value["winner"] == .bool(true), record: value["records"].array.first?["summary"].string, periods: periods)
    }
    nonisolated private static func isoDate(_ raw: String) -> Date? {
        // ESPN also publishes minute-precision timestamps, such as
        // 2025-10-25T23:00Z, while Foundation's internet style needs seconds.
        let value = raw.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$", options: .regularExpression) != nil ? String(raw.prefix(16)) + ":00" + String(raw.dropFirst(16)) : raw
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value)
    }
}
