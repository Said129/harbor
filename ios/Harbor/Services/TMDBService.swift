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
    func kidsDefinitions() -> [DiscoveryRail] {
        let movies = ["certification_country": "US", "certification.lte": "PG", "without_genres": "27,53", "include_adult": "false", "sort_by": "popularity.desc"]
        let television = ["without_genres": "27,53", "include_adult": "false", "sort_by": "popularity.desc"]
        return [("Tendencias para peques", "10751,16"), ("Películas de animación", "16"), ("Películas familiares", "10751"), ("Aventuras", "12,10751")].enumerated().map { index, definition in
            var parameters = movies; parameters["with_genres"] = definition.1; parameters["vote_count.gte"] = "100"
            return DiscoveryRail(id: "kids-movie-\(index)", title: definition.0, kind: "movie", path: "discover/movie", parameters: parameters)
        } + [("Series infantiles", "10762"), ("Noches en familia", "10751")].enumerated().map { index, definition in
            var parameters = television; parameters["with_genres"] = definition.1
            return DiscoveryRail(id: "kids-tv-\(index)", title: definition.0, kind: "series", path: "discover/tv", parameters: parameters)
        }
    }
    func definitions(_ kind: String) -> [DiscoveryRail] {
        let providerKind = kind == "movie" ? "movie" : "tv"
        var rows = [
            DiscoveryRail(id: "tmdb-\(kind)-top10", title: kind == "movie" ? "Top 10 películas de hoy" : "Top 10 series de hoy", kind: kind, path: "trending/\(providerKind)/day"),
            DiscoveryRail(id: "tmdb-\(kind)-trending", title: "Tendencias de la semana", kind: kind, path: "trending/\(providerKind)/week"),
            DiscoveryRail(id: "tmdb-\(kind)-current", title: kind == "movie" ? "Ahora en cines" : "En emisión", kind: kind, path: "\(providerKind)/\(kind == "movie" ? "now_playing" : "on_the_air")"),
            DiscoveryRail(id: "tmdb-\(kind)-rated", title: "Clásicos imprescindibles", kind: kind, path: "\(providerKind)/top_rated"),
            DiscoveryRail(id: "tmdb-\(kind)-gems", title: "Joyas por descubrir", kind: kind, path: "discover/\(providerKind)", parameters: ["vote_average.gte": "7.6", "vote_count.gte": "200", "vote_count.lte": "1500", "sort_by": "vote_average.desc"])
        ]
        if kind == "movie" {
            if Calendar.current.component(.month, from: Date()) == 10 { rows.insert(DiscoveryRail(id: "tmdb-spooky", title: "Spooky Season", kind: kind, path: "discover/movie", parameters: ["with_genres": "27", "sort_by": "popularity.desc"]), at: 2) }
            rows.append(DiscoveryRail(id: "tmdb-coming", title: "Próximamente en cines", kind: kind, path: "movie/upcoming"))
            rows.append(DiscoveryRail(id: "tmdb-quick", title: "Menos de 90 minutos", kind: kind, path: "discover/movie", parameters: ["with_runtime.lte": "90", "with_runtime.gte": "40", "vote_count.gte": "100", "sort_by": "popularity.desc"]))
            rows.append(DiscoveryRail(id: "tmdb-decade-2010", title: "Lo mejor de los 2010", kind: kind, path: "discover/movie", parameters: ["primary_release_date.gte": "2010-01-01", "primary_release_date.lte": "2019-12-31", "vote_average.gte": "7.6", "vote_count.gte": "2000", "sort_by": "vote_count.desc"]))
            rows.append(DiscoveryRail(id: "tmdb-decade-90", title: "Imprescindibles de los 90", kind: kind, path: "discover/movie", parameters: ["primary_release_date.gte": "1990-01-01", "primary_release_date.lte": "1999-12-31", "vote_average.gte": "7.6", "vote_count.gte": "1000", "sort_by": "popularity.desc"]))
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
        return results.compactMap { makeMedia($0, kind: rail.kind, configuration: configuration) }
    }
    private func makeMedia(_ value: JSONValue, kind: String, configuration: MetadataConfiguration) -> Media? {
            guard let id = value["id"].integer, let title = value[kind == "movie" ? "title" : "name"].string else { return nil }
            let original = value[kind == "movie" ? "original_title" : "original_name"].string
            var media = Media(id: "tmdb:\(kind == "movie" ? "movie" : "tv"):\(id)", type: kind, name: configuration.translateTitles ? title : original ?? title)
            media.poster = image(value["poster_path"].string, size: "w342")
            media.background = image(value["backdrop_path"].string, size: "w1280")
            media.description = value["overview"].string
            media.adult = value["adult"] == .bool(true)
            media.released = value[kind == "movie" ? "release_date" : "first_air_date"].string
            media.releaseInfo = media.released.map { String($0.prefix(4)) }
            if let rating = value["vote_average"].numericValue, rating > 0 { media.imdbRating = String(format: "%.1f", rating); media.ratingSource = "TMDB" }
            return media
    }
    func collections(query: String, page: Int, configuration: MetadataConfiguration) async throws -> CollectionPage {
        let response = try await get("search/collection", parameters: ["query": query, "page": String(page), "include_adult": "false"], configuration: configuration)
        guard case .array(let values) = response["results"] else { throw HarborError(code: "invalid-metadata-response") }
        let items = values.compactMap { value -> MovieCollection? in
            guard let id = value["id"].integer, let name = value["name"].string else { return nil }
            return MovieCollection(id: id, name: name, description: value["overview"].string, poster: image(value["poster_path"].string, size: "w500"), background: image(value["backdrop_path"].string, size: "w1280"))
        }
        return CollectionPage(items: items, totalPages: response["total_pages"].integer ?? page)
    }
    func collection(_ id: Int, configuration: MetadataConfiguration) async throws -> CollectionDetails {
        let response = try await get("collection/\(id)", configuration: configuration)
        guard let name = response["name"].string, case .array(let parts) = response["parts"] else { throw HarborError(code: "invalid-metadata-response") }
        let items = parts.compactMap { makeMedia($0, kind: "movie", configuration: configuration) }.sorted { ($0.released ?? "9999") < ($1.released ?? "9999") }
        return CollectionDetails(name: name, description: response["overview"].string, background: image(response["backdrop_path"].string, size: "w1280"), parts: items)
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
        let value = try await get(path, parameters: ["append_to_response": "external_ids,images,credits,recommendations,similar,videos", "include_image_language": "\(configuration.language.prefix(2)),en,null"], configuration: configuration)
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
        var details = MediaDetails()
        details.tagline = value["tagline"].string
        details.status = value["status"].string
        details.language = value["original_language"].string
        details.countries = value["production_countries"].array.compactMap { $0["name"].string }
        details.studios = value["production_companies"].array.compactMap { $0["name"].string }
        details.votes = value["vote_count"].integer
        if let amount = value["budget"].integer, amount > 0 { details.budget = Int64(amount) }
        if let amount = value["revenue"].integer, amount > 0 { details.revenue = Int64(amount) }
        details.cast = value["credits"]["cast"].array.prefix(60).compactMap { credit in
            guard let id = credit["id"].integer, let name = credit["name"].string else { return nil }
            return MediaDetails.Credit(id: id, name: name, role: credit["character"].string ?? "", photo: image(credit["profile_path"].string, size: "w185"))
        }
        details.crew = value["credits"]["crew"].array.compactMap { credit in
            guard let id = credit["id"].integer, let name = credit["name"].string, let role = credit["job"].string,
                  ["Director", "Writer", "Screenplay", "Producer", "Director of Photography", "Original Music Composer", "Editor"].contains(role) else { return nil }
            return MediaDetails.Credit(id: id, name: name, role: role)
        }
        details.recommendations = Array(value["recommendations"]["results"].array.compactMap { makeMedia($0, kind: media.type, configuration: configuration) }.prefix(20))
        details.similar = Array(value["similar"]["results"].array.compactMap { makeMedia($0, kind: media.type, configuration: configuration) }.prefix(20))
        details.trailers = value["videos"]["results"].array.prefix(20).compactMap { trailer in
            guard trailer["site"].string == "YouTube", let key = trailer["key"].string,
                  key.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else { return nil }
            return MediaDetails.Trailer(id: key, title: trailer["name"].string ?? trailer["type"].string ?? "Vídeo", url: "https://www.youtube.com/watch?v=\(key)", thumbnail: "https://i.ytimg.com/vi/\(key)/hqdefault.jpg")
        }
        details.backdrops = Array(value["images"]["backdrops"].array.compactMap { image($0["file_path"].string, size: "w1280") }.prefix(24))
        details.posters = Array(value["images"]["posters"].array.compactMap { image($0["file_path"].string, size: "w500") }.prefix(24))
        details.logos = Array(value["images"]["logos"].array.compactMap { image($0["file_path"].string, size: "w500") }.prefix(24))
        if let id = value["belongs_to_collection"]["id"].integer, let collection = try? await self.collection(id, configuration: configuration) {
            details.collectionName = collection.name; details.collection = collection.parts
        }
        try Task.checkCancellation()
        result.details = details
        return result
    }
    private func get(_ path: String, parameters: [String: String] = [:], configuration: MetadataConfiguration) async throws -> JSONValue {
        guard !configuration.tmdbKey.isEmpty, var url = URLComponents(string: "https://api.themoviedb.org/3/\(path)") else { throw HarborError(code: "metadata-not-configured") }
        url.queryItems = [URLQueryItem(name: "api_key", value: configuration.tmdbKey), URLQueryItem(name: "language", value: configuration.language)] + parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let target = url.string else { throw HarborError(code: "invalid-url") }
        return try await http.json(target, timeout: 15, credentialed: true)
    }
    private func image(_ path: String?, size: String) -> String? { path.map { "https://image.tmdb.org/t/p/\(size)\($0)" } }
}
