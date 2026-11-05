import XCTest
@testable import Harbor

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { seen } }
    func add(_ request: URLRequest) { lock.withLock { seen.append(request) } }
}

/// Desktop's Trakt comments (`lib/trakt/comments.ts`, `views/detail/trakt-comments.tsx`), the reading half.
final class TraktCommentsTests: XCTestCase {
    private func comment(_ fields: [String: JSONValue] = [:]) -> JSONValue {
        var base: [String: JSONValue] = [
            "id": .integer(42), "comment": .string("Loved it"), "spoiler": .bool(true), "review": .bool(false), "replies": .integer(2), "likes": .integer(9),
            "created_at": .string("2024-05-01T10:00:00.000Z"), "user_stats": .object(["rating": .integer(9)]),
            "user": .object(["username": .string("owned"), "name": .string("Owned Fan"), "ids": .object(["slug": .string("owned")]),
                             "images": .object(["avatar": .object(["full": .string("https://walter.trakt.tv/images/a.jpg")])])])]
        for (key, value) in fields { base[key] = value }
        return .object(base)
    }

    func testACommentIsReadWithItsAuthorRatingAndFlags() throws {
        let parsed = try XCTUnwrap(TraktComment.parse(comment()))
        XCTAssertEqual(parsed.id, 42); XCTAssertEqual(parsed.comment, "Loved it"); XCTAssertTrue(parsed.spoiler); XCTAssertFalse(parsed.review)
        XCTAssertEqual(parsed.replies, 2); XCTAssertEqual(parsed.likes, 9); XCTAssertEqual(parsed.userRating, 9)
        XCTAssertEqual(parsed.displayName, "Owned Fan"); XCTAssertEqual(parsed.avatarURL, "https://walter.trakt.tv/images/a.jpg")

        let bare = try XCTUnwrap(TraktComment.parse(.object(["id": .integer(1), "comment": .string("Hi"), "user": .object(["username": .string("plain"), "ids": .object(["slug": .string("plain-slug")])])])))
        XCTAssertEqual(bare.displayName, "plain"); XCTAssertFalse(bare.spoiler); XCTAssertEqual(bare.likes, 0); XCTAssertNil(bare.userRating)
        XCTAssertEqual(bare.avatarURL, "https://walter.trakt.tv/users/plain-slug/avatars/medium", "Without a picture the slug's default avatar is used")
        XCTAssertEqual(try XCTUnwrap(TraktComment.parse(comment(["user": .object(["username": .string("x"), "name": .string("")])]))).displayName, "x")
        XCTAssertNil(TraktComment.parse(.object(["comment": .string("No id"), "user": .object(["username": .string("x")])])))
        XCTAssertNil(TraktComment.parse(.object(["id": .integer(1), "comment": .string("No author")])))
    }

    func testAgesUseDesktopsBuckets() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func ago(_ seconds: Double) -> String {
            TraktComment.ago(from: now.addingTimeInterval(-seconds), now: now) { key, count in count.map { key.replacingOccurrences(of: "{n}", with: String($0)) } ?? key }
        }
        XCTAssertEqual(ago(30), "just now"); XCTAssertEqual(ago(59), "just now")
        XCTAssertEqual(ago(60), "1m ago"); XCTAssertEqual(ago(59 * 60), "59m ago")
        XCTAssertEqual(ago(3_600), "1h ago"); XCTAssertEqual(ago(23 * 3_600 + 3_599), "23h ago")
        XCTAssertEqual(ago(86_400), "1d ago"); XCTAssertEqual(ago(29 * 86_400), "29d ago")
        XCTAssertEqual(ago(30 * 86_400), "1mo ago"); XCTAssertEqual(ago(400 * 86_400), "13mo ago")
        XCTAssertEqual(ago(-500), "just now", "A date slightly in the future never goes negative")
    }

    func testTheTargetNeedsAnImdbIdAndAnimeHasNoTraktPage() {
        XCTAssertEqual(TraktCommentTarget.resolve(Media(id: "tt0111161", type: "movie", name: "Film")), .target(.movie("tt0111161")))
        XCTAssertEqual(TraktCommentTarget.resolve(Media(id: "tt0903747", type: "series", name: "Show")), .target(.show("tt0903747")))
        var viaTMDB = Media(id: "tmdb:tv:1396", type: "series", name: "Show"); viaTMDB.imdbID = "tt0903747"
        XCTAssertEqual(TraktCommentTarget.resolve(viaTMDB), .target(.show("tt0903747")), "A TMDB-keyed title uses its IMDb id")
        XCTAssertEqual(TraktCommentTarget.resolve(Media(id: "tmdb:tv:1396", type: "series", name: "Show")), .unidentified)
        XCTAssertEqual(TraktCommentTarget.resolve(Media(id: "kitsu:7442", type: "series", name: "Anime")), .anime)
        XCTAssertEqual(TraktCommentTarget.resolve(Media(id: "mal:16498", type: "anime", name: "Anime")), .anime)
        XCTAssertEqual(TraktCommentTarget.movie("tt1").path(.likes), "/movies/tt1/comments/likes")
        XCTAssertEqual(TraktCommentTarget.show("tt2").path(.newest), "/shows/tt2/comments/newest")
        XCTAssertEqual(TraktCommentTarget.show("tt2").path(.oldest), "/shows/tt2/comments/oldest")
        XCTAssertEqual(TraktCommentTarget.movie("tt1").pageURL?.absoluteString, "https://app.trakt.tv/movies/tt1?mode=media")
        XCTAssertEqual(TraktCommentTarget.show("tt2").pageURL?.absoluteString, "https://app.trakt.tv/shows/tt2?mode=media")
        XCTAssertEqual(TraktCommentSort.allCases.map(\.label), ["Likes", "Newest", "Oldest"])
    }

    func testRequestsGoToTraktsPublicApiWithItsHeadersAndPaging() async throws {
        let log = RequestLog()
        let body = try JSONEncoder().encode(JSONValue.array([comment(), comment(["id": .integer(43)])]))
        let service = TraktCommentsService(send: { request in log.add(request); return TraktReply(status: 200, data: body) })
        let found = await service.comments(.movie("tt1"), sort: .newest, page: 3, limit: 5)
        XCTAssertEqual(found.map(\.id), [42, 43])
        let request = try XCTUnwrap(log.requests.first)
        let parts = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(parts.host, "api.trakt.tv"); XCTAssertEqual(parts.path, "/movies/tt1/comments/newest")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") }), ["extended": "images", "page": "3", "limit": "5"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "trakt-api-version"), "2"); XCTAssertEqual(request.value(forHTTPHeaderField: "trakt-api-key"), TraktConfiguration.clientID)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "Reading comments needs no account")
        _ = await service.replies(to: 42)
        XCTAssertEqual(log.requests.last?.url?.path, "/comments/42/replies")
    }

    func testAFailedRequestAnswersNoComments() async {
        let unavailable = TraktCommentsService(send: { _ in TraktReply(status: 503, data: Data("{}".utf8)) })
        let missing = await unavailable.comments(.show("tt2"), sort: .likes)
        XCTAssertTrue(missing.isEmpty)
        let garbled = TraktCommentsService(send: { _ in TraktReply(status: 200, data: Data("not json".utf8)) })
        let none = await garbled.comments(.show("tt2"), sort: .likes), noReplies = await garbled.replies(to: 1)
        XCTAssertTrue(none.isEmpty); XCTAssertTrue(noReplies.isEmpty)
        let thrown = TraktCommentsService(send: { _ in throw HarborError(code: "network") })
        let offline = await thrown.comments(.show("tt2"), sort: .likes)
        XCTAssertTrue(offline.isEmpty)
        let mixed = TraktCommentsService(send: { _ in TraktReply(status: 200, data: Data(#"[{"id":1,"comment":"ok","user":{"username":"a"}},{"id":2}]"#.utf8)) })
        let kept = await mixed.comments(.show("tt2"), sort: .likes)
        XCTAssertEqual(kept.map(\.id), [1], "An entry without the fields of a comment is skipped")
    }
}
