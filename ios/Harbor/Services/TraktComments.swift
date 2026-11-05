import Foundation

/// A comment on Trakt (Desktop's `TraktComment` in `lib/trakt/comments.ts`).
struct TraktComment: Identifiable, Equatable, Sendable {
    let id: Int
    let comment: String
    let spoiler: Bool
    let review: Bool
    let replies: Int
    let likes: Int
    let createdAt: String
    /// The author's own rating of the title, 1 to 10.
    let userRating: Int?
    let username: String
    let name: String?
    let avatar: String?
    let slug: String?

    var displayName: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? username }
    var avatarURL: String? { avatar ?? slug.map { "https://walter.trakt.tv/users/\($0)/avatars/medium" } }

    static func parse(_ raw: JSONValue) -> TraktComment? {
        guard let id = raw["id"].integer, let text = raw["comment"].string, let username = raw["user"]["username"].string else { return nil }
        return TraktComment(id: id, comment: text, spoiler: raw["spoiler"] == .bool(true), review: raw["review"] == .bool(true),
                            replies: raw["replies"].integer ?? 0, likes: raw["likes"].integer ?? 0, createdAt: raw["created_at"].string ?? "",
                            userRating: raw["user_stats"]["rating"].integer, username: username, name: raw["user"]["name"].string,
                            avatar: raw["user"]["images"]["avatar"]["full"].string, slug: raw["user"]["ids"]["slug"].string)
    }

    /// Desktop's `timeAgo`; `text` translates a key and fills its `{n}`.
    static func ago(from date: Date, now: Date = Date(), text: (String, Int?) -> String) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        if minutes < 1 { return text("just now", nil) }
        if minutes < 60 { return text("{n}m ago", minutes) }
        let hours = minutes / 60
        if hours < 24 { return text("{n}h ago", hours) }
        let days = hours / 24
        if days < 30 { return text("{n}d ago", days) }
        return text("{n}mo ago", days / 30)
    }
}

enum TraktCommentSort: String, CaseIterable, Sendable {
    case likes, newest, oldest
    var label: String {
        switch self {
        case .likes: "Likes"
        case .newest: "Newest"
        case .oldest: "Oldest"
        }
    }
}

/// What the comments belong to. Harbor's detail page shows a movie's or a show's comments.
enum TraktCommentTarget: Equatable, Sendable {
    case movie(String)
    case show(String)

    enum Resolution: Equatable, Sendable {
        case target(TraktCommentTarget)
        case anime
        case unidentified
    }

    /// Desktop's `resolveTraktTarget` for a title: anime has no Trakt page, and an IMDb id is needed to find the rest.
    static func resolve(_ media: Media) -> Resolution {
        if AnimeService.isAnime(media.id) { return .anime }
        let candidates = [media.id, media.imdbID ?? ""]
        guard let imdb = candidates.first(where: { $0.range(of: "^tt[0-9]+$", options: .regularExpression) != nil }) else { return .unidentified }
        return .target(media.type == "movie" ? .movie(imdb) : .show(imdb))
    }

    /// Desktop's `commentsPath`.
    func path(_ sort: TraktCommentSort) -> String {
        switch self {
        case .movie(let id): "/movies/\(id)/comments/\(sort.rawValue)"
        case .show(let id): "/shows/\(id)/comments/\(sort.rawValue)"
        }
    }

    /// "Open on Trakt".
    var pageURL: URL? {
        switch self {
        case .movie(let id): URL(string: "https://app.trakt.tv/movies/\(id)?mode=media")
        case .show(let id): URL(string: "https://app.trakt.tv/shows/\(id)?mode=media")
        }
    }
}

/// Reads comments from Trakt's public API; no account is needed. Failures answer an empty list, as on Desktop.
struct TraktCommentsService: Sendable {
    static let pageSize = 20
    var send: @Sendable (URLRequest) async throws -> TraktReply = { try await HTTPClient().traktReply($0) }

    static func request(_ path: String, query: [(String, String)]) -> URLRequest? {
        var parts = URLComponents(string: "https://api.trakt.tv" + path)
        parts?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = parts?.url else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(TraktConfiguration.clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func list(_ request: URLRequest?) async -> [TraktComment] {
        guard let request, let reply = try? await send(request), (200..<300).contains(reply.status),
              let json = try? JSONDecoder().decode(JSONValue.self, from: reply.data) else { return [] }
        return json.array.compactMap(TraktComment.parse)
    }

    func comments(_ target: TraktCommentTarget, sort: TraktCommentSort, page: Int = 1, limit: Int = TraktCommentsService.pageSize) async -> [TraktComment] {
        await list(Self.request(target.path(sort), query: [("extended", "images"), ("page", String(page)), ("limit", String(limit))]))
    }

    func replies(to id: Int) async -> [TraktComment] {
        await list(Self.request("/comments/\(id)/replies", query: [("extended", "images")]))
    }
}
