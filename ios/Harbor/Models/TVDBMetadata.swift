import Foundation

enum TVDBRequest: Hashable, Sendable {
    case remote(String)
    case series(Int)
    case episodes(series: Int, order: String, language: String?, page: Int)

    var path: String {
        get throws {
            switch self {
            case .remote(let imdb):
                guard imdb.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil else { throw HarborError(code: "tvdb-request") }
                return "/search/remoteid/" + imdb
            case .series(let id):
                guard id > 0 else { throw HarborError(code: "tvdb-request") }
                return "/series/\(id)/extended?short=true"
            case .episodes(let id, let order, let language, let page):
                guard id > 0, ["default", "dvd", "absolute", "alternate", "regional"].contains(order), (0..<20).contains(page),
                      language == nil || language!.range(of: "^[a-z]{3}$", options: .regularExpression) != nil else { throw HarborError(code: "tvdb-request") }
                return "/series/\(id)/episodes/\(order)" + (language.map { "/" + $0 } ?? "") + "?page=\(page)"
            }
        }
    }
}

struct TVDBEpisodeMetadata: Sendable {
    let id: Int
    let season: Int
    let number: Int
    let absolute: Int?
    let image: String?
    let name: String?
    let overview: String?

    init?(_ value: JSONValue) {
        guard let id = value["id"].integer, id > 0, let season = value["seasonNumber"].integer, season >= 0,
              let number = value["number"].integer, number > 0 else { return nil }
        self.id = id; self.season = season; self.number = number
        absolute = value["absoluteNumber"].integer.flatMap { $0 > 0 ? $0 : nil }
        image = Self.imageURL(value["image"].string)
        name = value["name"].string; overview = value["overview"].string
    }

    static func imageURL(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, !raw.hasPrefix("//"),
              let url = URL(string: raw.hasPrefix("/") ? "https://artworks.thetvdb.com" + raw : raw),
              url.scheme == "https", url.host?.lowercased() == "artworks.thetvdb.com", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return nil }
        return url.absoluteString
    }

    /// Ambiguous coordinates never borrow another episode's still or text.
    /// Playback, progress and the selected season/continuous order stay intact.
    static func applying(_ rows: [Self], to source: [Episode], animeIdentity: Bool) -> [Episode] {
        let pairs = Dictionary(grouping: rows, by: { "\($0.season):\($0.number)" })
        let absolute = Dictionary(grouping: rows.filter { $0.season > 0 && $0.absolute != nil }, by: { $0.absolute! })
        let regular = source.filter { ($0.season ?? 1) > 0 }
        let animeNumbers = regular.compactMap(\.episode)
        let providerAbsolute = rows.filter { $0.season > 0 }.compactMap(\.absolute)
        let absoluteIdentity = animeIdentity && !regular.isEmpty && Set(regular.compactMap(\.season)).count == 1
            && Set(animeNumbers).count == regular.count && providerAbsolute.count == regular.count
            && Set(providerAbsolute) == Set(animeNumbers)
        return source.map { episode in
            let lookup: [Self]?
            if let season = episode.imdbSeason, let number = episode.imdbEpisode { lookup = pairs["\(season):\(number)"] }
            else if animeIdentity {
                lookup = absoluteIdentity && (episode.season ?? 1) > 0 ? episode.episode.flatMap { absolute[$0] } : nil
            } else { lookup = pairs[episode.watchedKey] }
            guard let lookup, lookup.count == 1, let row = lookup.first else { return episode }
            var value = episode
            let oldHost = episode.thumbnail.flatMap(URL.init(string:))?.host?.lowercased()
            if episode.thumbnail == nil || oldHost == "images.metahub.space", let image = row.image { value.thumbnail = image }
            if value.name?.isEmpty ?? true, value.title?.isEmpty ?? true { value.name = row.name }
            if value.overview?.isEmpty ?? true { value.overview = row.overview }
            return value
        }
    }
}
