import Foundation

struct Media: Codable, Identifiable, Hashable, Sendable {
    var id: String
    let type: String
    let name: String
    var poster: String?
    var background: String?
    var logo: String?
    var description: String?
    var releaseInfo: String?
    var released: String?
    var imdbRating: String?
    var ratingSource: String?
    var adult: Bool?
    var runtime: String?
    var director: [String]?
    var writer: [String]?
    var cast: [String]?
    var country: String?
    var genres: [String]?
    var videos: [Episode]?
    var behaviorHints: BehaviorHints?
    var details: MediaDetails?
    struct BehaviorHints: Codable, Hashable, Sendable { var defaultVideoId: String? }
    var identity: String { "\(type):\(id)" }
    var fallbackPoster: String? { imdbArtwork("poster") }
    var fallbackBackground: String? { imdbArtwork("background") }
    private func imdbArtwork(_ kind: String) -> String? {
        guard id.range(of: "^tt[0-9]{7,}$", options: .regularExpression) != nil else { return nil }
        return "https://images.metahub.space/\(kind)/medium/\(id)/img"
    }
    var episodic: Bool { type == "series" || videos?.contains(where: { $0.season != nil && $0.episode != nil }) == true }
    var safeForKids: Bool {
        guard adult != true else { return false }
        let labels = Set((genres ?? []).map { $0.lowercased() })
        let excluded: Set<String> = ["action", "biography", "crime", "history", "horror", "romance", "thriller", "war"]
        guard labels.isDisjoint(with: excluded), labels.contains("family") || (labels.contains("animation") && labels.contains("comedy")) else { return false }
        if let released, let date = Episode(id: "release", released: released).releaseDate { return date <= Date() }
        if let year = releaseInfo.flatMap({ Int($0.prefix(4)) }) { return year <= Calendar.current.component(.year, from: Date()) }
        return true
    }

    static func parse(_ value: JSONValue, kind: String) -> Media? {
        guard let id = value["id"].string, !id.isEmpty,
              let name = value["name"].string, !name.isEmpty else { return nil }
        var media = Media(id: id, type: value["type"].string ?? kind, name: name)
        media.poster = value["poster"].string; media.background = value["background"].string
        media.logo = value["logo"].string; media.description = value["description"].string
        media.releaseInfo = value["releaseInfo"].string
        media.released = value["released"].string
        if let rating = value["imdbRating"].textValue, let number = Double(rating), number > 0, number <= 10 { media.imdbRating = rating }
        media.runtime = value["runtime"].textValue
        media.country = value["country"].string
        if value["adult"] != .null { media.adult = value["adult"] == .bool(true) }
        media.genres = value["genres"].array.compactMap(\.string)
        media.director = value["director"].array.compactMap(\.string)
        var writers = Set<String>()
        media.writer = value["writer"].array.compactMap(\.string).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && writers.insert($0).inserted }
        media.cast = value["cast"].array.compactMap(\.string)
        if let videoID = value["behaviorHints"]["defaultVideoId"].string { media.behaviorHints = BehaviorHints(defaultVideoId: videoID) }
        media.videos = value["videos"].array.compactMap { video in
            guard let id = video["id"].string, !id.isEmpty else { return nil }
            return Episode(id: id, season: video["season"].integer, episode: video["episode"].integer ?? video["number"].integer, name: video["name"].string, title: video["title"].string, thumbnail: video["thumbnail"].string, overview: video["overview"].string ?? video["description"].string, released: video["released"].string ?? video["firstAired"].string)
        }
        var trailers = Set<String>()
        let candidates = Array(value["trailerStreams"].array.prefix(100)) + Array(value["trailers"].array.prefix(100))
        let videos = candidates.compactMap { value -> MediaDetails.Trailer? in
            guard let key = value["ytId"].string ?? value["source"].string,
                  let trailer = MediaDetails.Trailer.youtube(key, title: value["title"].string ?? value["name"].string ?? value["type"].string),
                  trailers.insert(key).inserted else { return nil }
            return trailer
        }
        if !videos.isEmpty { var details = MediaDetails(); details.trailers = Array(videos.prefix(30)); media.details = details }
        return media
    }
}

struct MediaDetails: Codable, Hashable, Sendable {
    struct Credit: Codable, Hashable, Identifiable, Sendable {
        let id: Int
        let name: String
        let role: String
        var photo: String?
    }
    struct Trailer: Codable, Hashable, Identifiable, Sendable {
        let id: String
        let title: String
        let url: String
        let thumbnail: String?
        static func youtube(_ key: String, title: String?) -> Trailer? {
            guard key.utf8.count == 11, key.range(of: "^[a-zA-Z0-9_-]{11}$", options: .regularExpression) != nil else { return nil }
            let label = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Trailer(id: key, title: label.isEmpty ? "Tráiler" : String(label.prefix(160)), url: "https://www.youtube.com/watch?v=\(key)", thumbnail: "https://i.ytimg.com/vi/\(key)/hqdefault.jpg")
        }
    }
    var tagline: String?
    var status: String?
    var language: String?
    var countries: [String] = []
    var studios: [String] = []
    var budget: Int64?
    var revenue: Int64?
    var votes: Int?
    var cast: [Credit] = []
    var crew: [Credit] = []
    var recommendations: [Media] = []
    var similar: [Media] = []
    var trailers: [Trailer] = []
    var backdrops: [String] = []
    var posters: [String] = []
    var logos: [String] = []
    var collectionName: String?
    var collection: [Media] = []
    func includingTrailers(from fallback: MediaDetails?) -> MediaDetails {
        var result = self
        var seen = Set<String>()
        result.trailers = Array((trailers + (fallback?.trailers ?? [])).filter { seen.insert($0.id).inserted }.prefix(30))
        return result
    }
}

extension JSONValue {
    var textValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): String(value)
        case .integer(let value): String(value)
        default: nil
        }
    }
}

struct Episode: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var season: Int?
    var episode: Int?
    var name: String?
    var title: String?
    var thumbnail: String?
    var overview: String?
    var runtime: Double?
    var released: String?
    var watchedKey: String { "\(season ?? 0):\(episode ?? 0)" }
    var releaseDate: Date? {
        guard let released else { return nil }
        return ISO8601DateFormatter().date(from: released) ?? ISO8601DateFormatter().date(from: String(released.prefix(10)) + "T00:00:00Z")
    }
    var available: Bool { releaseDate.map { $0 <= Date() } ?? true }
}

struct Addon: Codable, Identifiable, Sendable {
    var manifest: JSONValue
    var transportUrl: String
    var enabled: Bool
    // Transport, not manifest ID, identifies configured instances of one addon.
    var id: String { transportUrl }
    var name: String { manifest["name"].string ?? "Addon" }
}

struct CatalogDefinition: Codable, Sendable {
    var id: String
    var type: String
    var name: String
    var extra: [Extra]
    struct Extra: Codable, Sendable {
        var name: String
        var isRequired: Bool
        var options: [String]
    }
}

struct RequestPlan: Codable, Identifiable, Sendable {
    let key: String
    let url: String
    let title: String
    let kind: String
    let addon: Addon
    let addonPriority: Int
    let timeoutMs: Int
    let catalog: CatalogDefinition?
    var id: String { key }
}

struct CatalogRow: Identifiable, Sendable {
    let plan: RequestPlan
    var metas: [Media]
    var selectedGenre: String? = nil
    var receivedCount: Int? = nil
    var id: String { plan.key }
}

struct StreamOffer: Identifiable, Sendable {
    let id: Int
    let raw: JSONValue
    var title: String { raw["title"].string ?? raw["name"].string ?? raw["addonName"].string ?? "Stream" }
    var source: String { raw["addonName"].string ?? "Addon" }
    var quality: String { raw["tier"].string ?? "" }
    var addonID: String? { raw["addonId"].string }
    var bingeGroup: String? { raw["behaviorHints"]["bingeGroup"].string.flatMap { $0.isEmpty ? nil : $0 } }
}

struct PlaybackSource: Codable, Identifiable, Sendable {
    let url: String
    let headers: [String: String]?
    let subtitles: [Subtitle]?
    let via: String
    var id: String { url }
    struct Subtitle: Codable, Sendable { let url: String; var lang: String?; var id: String? }
}
