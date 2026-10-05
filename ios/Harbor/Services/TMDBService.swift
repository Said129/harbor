import Foundation

struct DiscoveryRail: Identifiable, Sendable {
    let id: String
    let title: String
    let kind: String
    let path: String
    var parameters: [String: String] = [:]
    var metas: [Media] = []
}

struct TMDBService: Sendable {
    private let http = HTTPClient()
    func definitions(_ kind: String) -> [DiscoveryRail] {
        let providerKind = kind == "movie" ? "movie" : "tv"
        var rows = [
            DiscoveryRail(id: "tmdb-\(kind)-trending", title: "Tendencias de la semana", kind: kind, path: "trending/\(providerKind)/week"),
            DiscoveryRail(id: "tmdb-\(kind)-current", title: kind == "movie" ? "Ahora en cines" : "En emisión", kind: kind, path: "\(providerKind)/\(kind == "movie" ? "now_playing" : "on_the_air")"),
            DiscoveryRail(id: "tmdb-\(kind)-rated", title: "Clásicos imprescindibles", kind: kind, path: "\(providerKind)/top_rated"),
            DiscoveryRail(id: "tmdb-\(kind)-gems", title: "Joyas por descubrir", kind: kind, path: "discover/\(providerKind)", parameters: ["vote_average.gte": "7.6", "vote_count.gte": "200", "vote_count.lte": "1500", "sort_by": "vote_average.desc"])
        ]
        if kind == "movie" {
            if Calendar.current.component(.month, from: Date()) == 10 { rows.insert(DiscoveryRail(id: "tmdb-spooky", title: "Spooky Season", kind: kind, path: "discover/movie", parameters: ["with_genres": "27", "sort_by": "popularity.desc"]), at: 2) }
            rows.append(DiscoveryRail(id: "tmdb-coming", title: "Próximamente en cines", kind: kind, path: "movie/upcoming"))
            rows.append(DiscoveryRail(id: "tmdb-quick", title: "Menos de 90 minutos", kind: kind, path: "discover/movie", parameters: ["with_runtime.lte": "90", "with_runtime.gte": "40", "vote_count.gte": "100", "sort_by": "popularity.desc"]))
        }
        for (name, id) in [("Acción", 28), ("Comedia", 35), ("Drama", 18), ("Ciencia ficción", 878), ("Animación", 16), ("Documentales", 99)] {
            let genre = kind == "series" && id == 28 ? 10759 : kind == "series" && id == 878 ? 10765 : id
            rows.append(DiscoveryRail(id: "tmdb-\(kind)-genre-\(genre)", title: name, kind: kind, path: "discover/\(providerKind)", parameters: ["with_genres": String(genre), "sort_by": "popularity.desc"]))
        }
        return rows
    }
    func page(_ rail: DiscoveryRail, page: Int, configuration: MetadataConfiguration) async throws -> [Media] {
        var params = rail.parameters
        params["page"] = String(page); params["region"] = configuration.region
        let response = try await get(rail.path, parameters: params, configuration: configuration)
        guard case .array(let results) = response["results"] else { throw HarborError(code: "invalid-metadata-response") }
        return results.compactMap { value in
            guard let id = value["id"].integer, let title = value[rail.kind == "movie" ? "title" : "name"].string else { return nil }
            let original = value[rail.kind == "movie" ? "original_title" : "original_name"].string
            var media = Media(id: "tmdb:\(rail.kind == "movie" ? "movie" : "tv"):\(id)", type: rail.kind, name: configuration.translateTitles ? title : original ?? title)
            media.poster = image(value["poster_path"].string, size: "w342")
            media.background = image(value["backdrop_path"].string, size: "w1280")
            media.description = value["overview"].string
            media.releaseInfo = value[rail.kind == "movie" ? "release_date" : "first_air_date"].string.map { String($0.prefix(4)) }
            if let rating = value["vote_average"].numericValue, rating > 0 { media.imdbRating = String(format: "%.1f", rating) }
            return media
        }
    }
    func detail(_ media: Media, configuration: MetadataConfiguration) async throws -> Media {
        let pieces = media.id.split(separator: ":")
        let path: String
        if pieces.count == 3 && pieces[0] == "tmdb" { path = "\(pieces[1])/\(pieces[2])" }
        else if media.id.hasPrefix("tt") {
            let found = try await get("find/\(media.id)", parameters: ["external_source": "imdb_id"], configuration: configuration)
            guard let raw = found[media.type == "movie" ? "movie_results" : "tv_results"].array.first, let id = raw["id"].integer else { return media }
            path = "\(media.type == "movie" ? "movie" : "tv")/\(id)"
        } else { return media }
        let value = try await get(path, parameters: ["append_to_response": "external_ids,images,credits", "include_image_language": "\(configuration.language.prefix(2)),en,null"], configuration: configuration)
        var result = media
        if let imdb = value["imdb_id"].string ?? value["external_ids"]["imdb_id"].string, !imdb.isEmpty { result.id = imdb }
        result.background = image(value["backdrop_path"].string, size: "w1280") ?? result.background
        result.poster = image(value["poster_path"].string, size: "w342") ?? result.poster
        result.logo = value["images"]["logos"].array.first.flatMap { image($0["file_path"].string, size: "w500") } ?? result.logo
        result.description = value["overview"].string ?? result.description
        result.genres = value["genres"].array.compactMap { $0["name"].string }
        result.cast = Array(value["credits"]["cast"].array.compactMap { $0["name"].string }.prefix(15))
        result.director = value["credits"]["crew"].array.filter { $0["job"].string == "Director" }.compactMap { $0["name"].string }
        if let minutes = value["runtime"].integer { result.runtime = "\(minutes) min" }
        return result
    }
    private func get(_ path: String, parameters: [String: String] = [:], configuration: MetadataConfiguration) async throws -> JSONValue {
        guard !configuration.tmdbKey.isEmpty, var url = URLComponents(string: "https://api.themoviedb.org/3/\(path)") else { throw HarborError(code: "metadata-not-configured") }
        url.queryItems = [URLQueryItem(name: "api_key", value: configuration.tmdbKey), URLQueryItem(name: "language", value: configuration.language)] + parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let target = url.string else { throw HarborError(code: "invalid-url") }
        return try await http.json(target, timeout: 15)
    }
    private func image(_ path: String?, size: String) -> String? { path.map { "https://image.tmdb.org/t/p/\(size)\($0)" } }
}
