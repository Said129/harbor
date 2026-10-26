import Foundation

enum SimklLibraryEndpoint: Sendable {
    case all(SimklMediaKind), ratings, activities, delta(String), identities
    case status(SimklTarget, SimklListStatus), remove(SimklTarget), rating(SimklTarget, Int?)
    var method: String { switch self { case .status, .remove, .rating: "POST"; default: "GET" } }
    var path: String {
        switch self {
        case .all(let kind): "/sync/all-items/\(kind.bucket)/all"
        case .ratings: "/sync/ratings"
        case .activities: "/sync/activities"
        case .delta, .identities: "/sync/all-items"
        case .status: "/sync/add-to-list"
        case .remove: "/sync/history/remove"
        case .rating(_, let rating): rating == nil ? "/sync/ratings/remove" : "/sync/ratings"
        }
    }
    var query: [URLQueryItem] {
        switch self {
        case .all: [.init(name: "extended", value: "full"), .init(name: "episode_watched_at", value: "yes")]
        case .delta(let date): [.init(name: "date_from", value: date), .init(name: "extended", value: "full"), .init(name: "episode_watched_at", value: "yes")]
        case .identities: [.init(name: "extended", value: "simkl_ids_only")]
        default: []
        }
    }
    func body() throws -> JSONValue? {
        switch self {
        case .status(let target, let status):
            guard !target.ids.values.isEmpty, SimklListStatus.options(for: target.kind).contains(status) else { throw HarborError(code: "simkl-status") }
            return .object(["to": .string(status.rawValue), target.listBucket: .array([.object(["to": .string(status.rawValue), "ids": target.ids.json])])])
        case .remove(let target):
            guard !target.ids.values.isEmpty else { throw HarborError(code: "simkl-target") }
            return .object([target.listBucket: .array([.object(["ids": target.ids.json])])])
        case .rating(let target, let rating):
            guard !target.ids.values.isEmpty, rating.map({ (1...10).contains($0) }) ?? true else { throw HarborError(code: "simkl-rating") }
            var item = ["ids": target.ids.json]; if let rating { item["rating"] = .integer(Int64(rating)) }
            return .object([target.ratingBucket: .array([.object(item)])])
        default: return nil
        }
    }
}
