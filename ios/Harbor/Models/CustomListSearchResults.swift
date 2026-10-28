import Foundation

enum CustomListSearchResults {
    static func map(_ response: JSONValue, english: JSONValue = .null, configuration: MetadataConfiguration) -> [Media] {
        let englishNames = Dictionary(english["results"].array.compactMap { value -> (Int, String)? in
            guard let id = value["id"].integer, let name = value["title"].string ?? value["name"].string, !name.isEmpty else { return nil }
            return (id, name)
        }, uniquingKeysWith: { _, last in last })
        var movies: [Media] = [], series: [Media] = []
        for value in response["results"].array {
            guard let id = value["id"].integer, let kind = value["media_type"].string, ["movie", "tv"].contains(kind),
                let poster = value["poster_path"].string, !poster.isEmpty,
                let title = value[kind == "movie" ? "title" : "name"].string else { continue }
            let animated = value["genre_ids"].array.contains(.integer(16)) || value["genres"].array.contains { $0 == .string("Animation") || $0["id"].integer == 16 }
            let anime = animated && (value["original_language"].string == "ja" || value["origin_country"].array.contains(.string("JP")))
            let original = value[kind == "movie" ? "original_title" : "original_name"].string.flatMap { $0.isEmpty ? nil : $0 }
            var name = configuration.translateTitles || anime ? title : original ?? title
            if anime, configuration.translateTitles, let englishName = englishNames[id],
               name.range(of: "[\u{3040}-\u{30FF}\u{3400}-\u{4DBF}\u{4E00}-\u{9FFF}]", options: .regularExpression) != nil { name = englishName }
            var media = Media(id: "tmdb:\(kind):\(id)", type: kind == "movie" ? "movie" : "series", name: name)
            media.poster = "https://image.tmdb.org/t/p/w500" + poster
            if let background = value["backdrop_path"].string, !background.isEmpty { media.background = "https://image.tmdb.org/t/p/w780" + background }
            media.description = value["overview"].string
            media.originalLanguage = value["original_language"].string
            media.released = value[kind == "movie" ? "release_date" : "first_air_date"].string
            media.releaseInfo = media.released.map { String($0.prefix(4)) }
            media.adult = value["adult"] == .bool(true)
            if let rating = value["vote_average"].numericValue, rating > 0 { media.imdbRating = String(format: "%.1f", rating); media.ratingSource = "TMDB" }
            if kind == "movie" { movies.append(media) } else { series.append(media) }
        }
        return Array(movies.prefix(12)) + Array(series.prefix(12))
    }
}
