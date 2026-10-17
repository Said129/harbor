import Foundation

struct SportsStandingCell: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let abbreviation: String
    let value: String
}
struct SportsStandingRow: Identifiable, Hashable, Sendable {
    let side: SportsSide
    let rank: Int
    let note: String
    let cells: [SportsStandingCell]
    var id: String { side.id }
    func value(_ names: [String]) -> String { names.compactMap { name in cells.first { $0.id == name }?.value }.first ?? "" }
}
struct SportsStandingGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let rows: [SportsStandingRow]
}
struct SportsStandings: Sendable {
    let title: String
    let season: String
    let groups: [SportsStandingGroup]
}

actor SportsStandingsService {
    static let shared = SportsStandingsService()
    private var cache: [String: (Date, SportsStandings)] = [:]
    func table(_ league: SportsLeague, season: Int? = nil, refresh: Bool = false) async throws -> SportsStandings {
        let key = league.id + ":" + (season.map(String.init) ?? "current")
        if !refresh, let entry = cache[key], Date().timeIntervalSince(entry.0) < 300 { return entry.1 }
        let query = season.map { "?season=\($0)" } ?? ""
        let json = try await HTTPClient().json("https://site.web.api.espn.com/apis/v2/sports/" + league.path + "/standings" + query, timeout: 30)
        let result = Self.parse(json, league: league)
        guard !result.groups.isEmpty else { throw HarborError(code: "sports-standings") }
        cache[key] = (Date(), result)
        if cache.count > 32, let oldest = cache.min(by: { $0.value.0 < $1.value.0 })?.key { cache[oldest] = nil }
        return result
    }
    func saved(_ league: SportsLeague, season: Int?) -> SportsStandings? { cache[league.id + ":" + (season.map(String.init) ?? "current")]?.1 }
    nonisolated private static func parse(_ json: JSONValue, league: SportsLeague) -> SportsStandings {
        let title = json["name"].string ?? league.title
        var groups: [SportsStandingGroup] = []
        // Providers publish conference groups, or a flat table. Nested divisions
        // are visited only when their parent has no published entries.
        func visit(_ source: JSONValue, depth: Int) {
            guard depth <= 4 else { return }
            var seen = Set<String>()
            let rows = source["standings"]["entries"].array.enumerated().compactMap { index, entry -> SportsStandingRow? in
                let team = entry["team"], athlete = entry["athlete"]
                let subject = team["displayName"].string == nil ? athlete : team
                guard let name = subject["displayName"].string ?? subject["fullName"].string, !name.isEmpty else { return nil }
                let id = subject["id"].textValue ?? name
                guard seen.insert(id).inserted else { return nil }
                let cells = entry["stats"].array.compactMap { stat -> SportsStandingCell? in
                    guard let name = stat["name"].string, let value = stat["displayValue"].textValue ?? stat["value"].textValue else { return nil }
                    return SportsStandingCell(id: name, label: stat["displayName"].string ?? stat["shortDisplayName"].string ?? name, abbreviation: stat["abbreviation"].string ?? stat["shortDisplayName"].string ?? name, value: value)
                }
                let rank = entry["stats"].array.first { ["rank", "playoffSeed"].contains($0["name"].string ?? "") }?["value"].integer
                let logo = subject["logo"].string ?? subject["logos"].array.first?["href"].string ?? subject["headshot"]["href"].string ?? subject["flag"]["href"].string
                let side = SportsSide(id: id, name: name, logo: logo, score: nil, winner: false)
                return SportsStandingRow(side: side, rank: rank.flatMap { $0 > 0 ? $0 : nil } ?? index + 1, note: entry["note"]["description"].string ?? "", cells: cells)
            }.sorted { $0.rank < $1.rank }
            if !rows.isEmpty {
                groups.append(SportsStandingGroup(id: (source["id"].textValue ?? "table") + ":\(groups.count)", title: source["name"].string ?? source["abbreviation"].string ?? title, rows: rows))
            } else { for child in source["children"].array { visit(child, depth: depth + 1) } }
        }
        visit(json, depth: 0)
        let season = json["season"]["displayName"].string ?? json["children"].array.first?["standings"]["seasonDisplayName"].string ?? json["season"]["year"].textValue ?? ""
        return SportsStandings(title: title, season: season, groups: groups)
    }
}
