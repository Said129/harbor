import Foundation

/// The bodies and paths Desktop's Trakt comment, like and rating calls send (`lib/trakt/comments.ts`).
/// Pure value logic: nothing here sends a request, and no screen uses it yet.
enum TraktCommentRequests {
    /// Desktop's `subjectBody` for a movie or show. Harbor's targets carry only the IMDb id, so only `imdb` is sent.
    private static func subject(_ target: TraktCommentTarget) -> (key: String, imdb: String) {
        switch target {
        case .movie(let id): return ("movie", id)
        case .show(let id): return ("show", id)
        }
    }

    /// Desktop's `postComment` body: a review flag and share flag that are always false.
    static func postBody(_ target: TraktCommentTarget, comment: String, spoiler: Bool) -> JSONValue {
        let subject = subject(target)
        return .object([
            "comment": .string(comment),
            "spoiler": .bool(spoiler),
            "review": .bool(false),
            "share": .bool(false),
            subject.key: .object(["ids": .object(["imdb": .string(subject.imdb)])]),
        ])
    }

    /// `POST` likes a comment and `DELETE` removes the like.
    static func likePath(_ commentID: Int) -> String { "/comments/\(commentID)/like" }

    /// `DELETE` removes a comment.
    static func deletePath(_ commentID: Int) -> String { "/comments/\(commentID)" }

    /// Desktop's `ratingPath`: the rating endpoint of a movie or show.
    static func ratingPath(_ target: TraktCommentTarget) -> String {
        switch target {
        case .movie(let id): return "/movies/\(id)/rating"
        case .show(let id): return "/shows/\(id)/rating"
        }
    }

    private static func listKey(_ target: TraktCommentTarget) -> String {
        switch target {
        case .movie: return "movies"
        case .show: return "shows"
        }
    }

    /// Desktop's `rateContent` body for `/sync/ratings`. Trakt needs the TMDB id here, so nil when there is none.
    static func ratingBody(_ target: TraktCommentTarget, tmdb: Int?, rating: Int) -> JSONValue? {
        guard let tmdb else { return nil }
        let entry: JSONValue = .object(["rating": .integer(Int64(rating)), "ids": .object(["tmdb": .integer(Int64(tmdb))])])
        return .object([listKey(target): .array([entry])])
    }

    /// Desktop's `removeRating` body for `/sync/ratings/remove`, which also needs the TMDB id.
    static func removeRatingBody(_ target: TraktCommentTarget, tmdb: Int?) -> JSONValue? {
        guard let tmdb else { return nil }
        return .object([listKey(target): .array([.object(["ids": .object(["tmdb": .integer(Int64(tmdb))])])])])
    }
}
