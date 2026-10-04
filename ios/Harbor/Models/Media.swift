import Foundation

struct Media: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: String
    let name: String
    var poster: String?
    var background: String?
    var logo: String?
    var description: String?
    var releaseInfo: String?
    var genres: [String]?
    var videos: [Episode]?
    var behaviorHints: BehaviorHints?
    struct BehaviorHints: Codable, Hashable, Sendable { var defaultVideoId: String? }
    var identity: String { "\(type):\(id)" }
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
    var id: String { plan.key }
}

struct StreamOffer: Identifiable, Sendable {
    let id: Int
    let raw: JSONValue
    var title: String { raw["title"].string ?? raw["name"].string ?? raw["addonName"].string ?? "Stream" }
    var source: String { raw["addonName"].string ?? "Addon" }
    var quality: String { raw["tier"].string ?? "" }
}

struct PlaybackSource: Codable, Identifiable, Sendable {
    let url: String
    let headers: [String: String]?
    let subtitles: [Subtitle]?
    let via: String
    var id: String { url }
    struct Subtitle: Codable, Sendable { let url: String; var lang: String?; var id: String? }
}
