import Foundation

enum MALPublicCatalog {
    static func page(_ rail: DiscoveryRail, page: Int, http: HTTPClient) async throws -> [Media] {
        struct Configuration: Decodable { let clientId: String }
        guard let url = Bundle.main.url(forResource: "DesktopMALCatalog", withExtension: "json"),
              let configuration = try? JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url)) else { throw HarborError(code: "anime-configuration") }
        let query = try request(rail.id, page: page)
        let response = try await http.malCatalog(path: query.path, parameters: query.parameters, clientID: configuration.clientId)
        return try parse(response)
    }

    static func request(_ railID: String, page: Int, now: Date = Date()) throws -> (path: String, parameters: [String: String]) {
        guard (1...100).contains(page) else { throw HarborError(code: "anime-page") }
        var parameters = ["limit": "25", "offset": String((page - 1) * 25), "nsfw": "false",
                          "fields": "alternative_titles,mean,genres,nsfw,media_type,start_season,start_date,synopsis,status"]
        switch railID {
        case "anime-popular": parameters["ranking_type"] = "bypopularity"
        case "anime-top-tv": parameters["ranking_type"] = "tv"
        case "anime-top-movies": parameters["ranking_type"] = "movie"
        case "anime-airing", "anime-upcoming":
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = calendar.dateComponents([.year, .month], from: now)
            guard var year = components.year, let month = components.month else { throw HarborError(code: "anime-season") }
            var quarter = (month - 1) / 3
            if railID == "anime-upcoming" { quarter += 1; if quarter == 4 { quarter = 0; year += 1 } }
            parameters["sort"] = "anime_num_list_users"
            return ("/anime/season/\(year)/\(["winter", "spring", "summer", "fall"][quarter])", parameters)
        default: throw HarborError(code: "anime-catalog")
        }
        return ("/anime/ranking", parameters)
    }

    static func parse(_ response: JSONValue) throws -> [Media] {
        guard case .array(let rows) = response["data"], rows.count <= 25 else { throw HarborError(code: "anime-response") }
        var ids = Set<String>()
        return rows.compactMap { row in
            let node = row["node"]
            guard let id = node["id"].integer, id > 0,
                  let nsfw = node["nsfw"].string, ["white", "gray"].contains(nsfw),
                  let title = node["title"].string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let genres = node["genres"].array.compactMap { $0["name"].string }
            guard !genres.contains(where: { ["hentai", "erotica"].contains($0.lowercased()) }), ids.insert("mal:\(id)").inserted else { return nil }
            let english = node["alternative_titles"]["en"].string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var media = Media(id: "mal:\(id)", type: node["media_type"].string == "movie" ? "movie" : "series", name: english.isEmpty ? title : english)
            media.poster = node["main_picture"]["large"].string ?? node["main_picture"]["medium"].string
            media.background = media.poster; media.description = node["synopsis"].string
            media.releaseInfo = node["start_season"]["year"].integer.map(String.init) ?? node["start_date"].string.map { String($0.prefix(4)) }
            media.genres = genres; media.adult = false; media.ratingSource = "MAL"
            if let score = node["mean"].numericValue, score > 0, score <= 10 { media.imdbRating = String(format: "%.1f", score) }
            return media
        }
    }
}
