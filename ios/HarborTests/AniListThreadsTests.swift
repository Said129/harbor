import XCTest
@testable import Harbor

/// Desktop's AniList threads and comments (`lib/anilist/threads.ts`, `views/detail/anilist-comments.tsx`),
/// its anime relations (`lib/anilist/relations.ts`, `animeRelations`) and the avatar rules of `anilist-avatar-sync.tsx`.
final class AniListThreadsTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// Answers each request from a script and keeps the requests, so the tests can read their headers and variables.
    private final class ScriptedAniList: AniListTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []
        private let answer: @Sendable (URLRequest) -> AniListReply

        init(answer: @escaping @Sendable (URLRequest) -> AniListReply) { self.answer = answer }

        func send(_ request: URLRequest) async throws -> AniListReply {
            lock.lock(); recorded.append(request); lock.unlock()
            return answer(request)
        }

        var requests: [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }
    }

    private func reply(_ text: String) -> AniListReply {
        AniListReply(status: 200, data: Data(text.utf8), retryAfter: nil)
    }

    private func variables(_ request: URLRequest) -> JSONValue {
        guard let body = request.httpBody, let parsed = try? JSONDecoder().decode(JSONValue.self, from: body) else { return .null }
        return parsed["variables"]
    }

    private let threadsJSON = """
    {"data": {"Page": {"threads": [
      {"id": 501, "title": "Episode 3 thoughts", "bodyHtml": "<p>First line<br>Second &amp; last</p>", "replyCount": 4, "viewCount": 120,
       "isLocked": false, "isSticky": true, "createdAt": 1700000000, "updatedAt": 1700000100, "siteUrl": "https://anilist.co/forum/thread/501",
       "user": {"id": 7, "name": "Mika", "avatar": {"medium": "https://img.example/m.jpg", "large": "https://img.example/l.jpg"}}},
      {"id": 502, "title": "Locked one", "bodyHtml": null, "replyCount": 0, "viewCount": 2,
       "isLocked": true, "isSticky": false, "createdAt": 1700000500, "updatedAt": 1700000500, "siteUrl": null, "user": null}
    ], "pageInfo": {"currentPage": 1, "lastPage": 2, "hasNextPage": true}}}}
    """

    private let commentsJSON = """
    {"data": {"Page": {"threadComments": [
      {"id": 9001, "commentHtml": "<p>Great &quot;arc&quot;</p>", "likeCount": 3, "isLiked": true, "createdAt": 1700000000, "siteUrl": null,
       "user": {"id": 8, "name": "Ren", "avatar": {"medium": null, "large": "https://img.example/ren.jpg"}}},
      {"id": 9002, "commentHtml": "<p>&lt;3 &#039;this&#039;</p>", "likeCount": 0, "isLiked": false, "createdAt": 1700000600, "siteUrl": null, "user": null}
    ]}}}
    """

    func testThreadsPageMapsBodiesAuthorsAndPaging() throws {
        let page = AniListThreads.threadsPage(try json(threadsJSON)["data"])
        XCTAssertEqual(page.threads.map(\.id), [501, 502])
        XCTAssertTrue(page.hasNextPage)
        XCTAssertEqual(page.threads[0].body, "First line\nSecond & last", "tags go, entities decode once, &amp; last")
        XCTAssertTrue(page.threads[0].isSticky)
        XCTAssertEqual(page.threads[0].author.avatar, "https://img.example/m.jpg", "the medium picture comes first")
        XCTAssertEqual(page.threads[0].author.name, "Mika")
        XCTAssertNil(page.threads[1].author.name, "a missing user shows as Unknown in the view")
        XCTAssertEqual(page.threads[1].author.id, 0)
        XCTAssertNil(page.threads[1].author.avatar)
        XCTAssertEqual(page.threads[1].body, "")
        XCTAssertTrue(page.threads[1].isLocked)
    }

    func testCommentsKeepServerOrderAndFallBackToTheLargeAvatar() throws {
        let comments = AniListThreads.parseComments(try json(commentsJSON)["data"])
        XCTAssertEqual(comments.map(\.id), [9001, 9002])
        XCTAssertEqual(comments[0].text, "Great \"arc\"")
        XCTAssertEqual(comments[0].likes, 3)
        XCTAssertTrue(comments[0].isLiked)
        XCTAssertEqual(comments[0].author.avatar, "https://img.example/ren.jpg")
        XCTAssertEqual(comments[1].text, "<3 'this'", "a decoded less-than sign is text, not markup")
        XCTAssertNil(comments[1].author.name)
    }

    func testHTMLTextReadsLineBreaksCaseInsensitivelyAndDecodesAmpersandsLast() {
        XCTAssertEqual(AniListThreads.text(fromHTML: "x<br/>y<BR>z"), "x\ny\nz")
        XCTAssertEqual(AniListThreads.text(fromHTML: "a&amp;lt; &lt;b&gt;"), "a&lt; <b>", "&amp;lt; must stay as text")
    }

    func testAgeStringsFollowDesktopTimeAgo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let text: (String, Int?) -> String = { key, count in key.replacingOccurrences(of: "{n}", with: count.map(String.init) ?? "") }
        XCTAssertEqual(AniListThreads.ago(unixSeconds: 1_700_000_000 - 30, now: now, text: text), "just now")
        XCTAssertEqual(AniListThreads.ago(unixSeconds: 1_700_000_000 - 125, now: now, text: text), "2m ago")
        XCTAssertEqual(AniListThreads.ago(unixSeconds: 1_700_000_000 - 18_000, now: now, text: text), "5h ago")
        XCTAssertEqual(AniListThreads.ago(unixSeconds: 1_700_000_000 - 259_200, now: now, text: text), "3d ago")
        XCTAssertEqual(AniListThreads.ago(unixSeconds: 1_700_000_000 - 3_888_000, now: now, text: text), "1mo ago")
        XCTAssertEqual(AniListThreads.ago(unixSeconds: 1_700_000_500, now: now, text: text), "just now", "a time ahead of now is just now")
    }

    /// Relations graph: 10 has prequel 9 and sequel 11, a side story 12 and a movie 13 (both left out).
    /// 9 has prequel 8. 11 has sequel 14 and a nameless sequel 15, which is seen but never listed or walked.
    private func relationsReply(for id: Int) -> String {
        let graph: [Int: String] = [
            10: #"{"data":{"Media":{"relations":{"edges":[{"relationType":"PREQUEL","node":{"id":9,"format":"TV","status":"FINISHED","title":{"english":"Nine","romaji":"Nine R","userPreferred":null},"seasonYear":2010,"startDate":{"year":2010},"coverImage":{"large":"https://img.example/9.jpg"}}},{"relationType":"SEQUEL","node":{"id":11,"format":"TV","status":"FINISHED","title":{"english":"Eleven","romaji":null,"userPreferred":null},"seasonYear":2014,"startDate":{"year":2014},"coverImage":{"large":null}}},{"relationType":"SIDE_STORY","node":{"id":12,"format":"TV","status":"FINISHED","title":{"english":"Side","romaji":null,"userPreferred":null},"seasonYear":2012,"startDate":null,"coverImage":null}},{"relationType":"SEQUEL","node":{"id":13,"format":"MOVIE","status":"FINISHED","title":{"english":"Film","romaji":null,"userPreferred":null},"seasonYear":2015,"startDate":null,"coverImage":null}}]}}}}"#,
            9: #"{"data":{"Media":{"relations":{"edges":[{"relationType":"PREQUEL","node":{"id":8,"format":"TV","status":"FINISHED","title":{"english":null,"romaji":"Eight","userPreferred":null},"seasonYear":null,"startDate":{"year":2005},"coverImage":null}},{"relationType":"SEQUEL","node":{"id":10,"format":"TV","status":"FINISHED","title":{"english":"Ten","romaji":null,"userPreferred":null},"seasonYear":2010,"startDate":null,"coverImage":null}}]}}}}"#,
            11: #"{"data":{"Media":{"relations":{"edges":[{"relationType":"SEQUEL","node":{"id":14,"format":"TV","status":"NOT_YET_RELEASED","title":{"english":"Fourteen","romaji":null,"userPreferred":null},"seasonYear":2018,"startDate":null,"coverImage":null}},{"relationType":"SEQUEL","node":{"id":15,"format":"TV","status":"FINISHED","title":{"english":"  ","romaji":null,"userPreferred":null},"seasonYear":2019,"startDate":null,"coverImage":null}}]}}}}"#
        ]
        return graph[id] ?? #"{"data":{"Media":{"relations":{"edges":[]}}}}"#
    }

    func testRelationsWalkKeepsPrequelsAndSequelsOnlyAndSortsThem() async throws {
        let transport = ScriptedAniList { request in
            let id = self.variables(request)["id"].integer ?? -1
            return self.reply(self.relationsReply(for: id))
        }
        let relations = await AniListRelationsService(client: AniListClient(transport: transport)).relations(anilistID: 10)
        XCTAssertEqual(relations.map(\.id), [9, 8, 11, 14])
        XCTAssertEqual(relations.map(\.kind), [.prequel, .prequel, .sequel, .sequel])
        XCTAssertEqual(relations.map(\.year), [2010, 2005, 2014, 2018])
        XCTAssertEqual(relations[0].name, "Nine")
        XCTAssertEqual(relations[1].name, "Eight", "romaji is the fallback title")
        XCTAssertEqual(relations[0].poster, "https://img.example/9.jpg")
        XCTAssertTrue(relations[3].upcoming, "NOT_YET_RELEASED is upcoming")
        XCTAssertFalse(relations[0].upcoming)
        let fetched = transport.requests.compactMap { variables($0)["id"].integer }
        XCTAssertEqual(fetched, [10, 9, 11, 8, 14], "a nameless title is never walked from")
        XCTAssertFalse(relations.contains { $0.id == 12 || $0.id == 13 || $0.id == 15 })
    }

    func testRelationRequestsSendNoToken() async throws {
        let transport = ScriptedAniList { _ in self.reply(#"{"data":{"Media":{"relations":{"edges":[]}}}}"#) }
        _ = await AniListRelationsService(client: AniListClient(transport: transport)).relations(anilistID: 10)
        XCTAssertFalse(transport.requests.isEmpty)
        XCTAssertTrue(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    func testThreadRequestsCarryTheViewerTokenAndTheMediaID() async throws {
        let transport = ScriptedAniList { _ in self.reply(self.threadsJSON) }
        let page = try await AniListThreadsService(client: AniListClient(transport: transport), token: "test-token-only")
            .threads(mediaID: 77, page: 2, perPage: 20)
        XCTAssertEqual(page.threads.count, 2)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-only")
        XCTAssertEqual(variables(request)["mediaId"].integer, 77)
        XCTAssertEqual(variables(request)["page"].integer, 2)
        XCTAssertEqual(variables(request)["perPage"].integer, 20)
    }

    @MainActor func testProfileAvatarNeedsTheSettingAndAUsableURL() {
        let url = "https://img.example/a.jpg"
        XCTAssertNil(TrackerAvatarResolver.profileAvatar(enabled: false, anilistAvatar: url))
        XCTAssertNil(TrackerAvatarResolver.profileAvatar(enabled: true, anilistAvatar: nil))
        XCTAssertEqual(TrackerAvatarResolver.profileAvatar(enabled: true, anilistAvatar: "  \(url) \n"), url)
        XCTAssertNil(TrackerAvatarResolver.profileAvatar(enabled: true, anilistAvatar: "https://someone@img.example/a.jpg"), "user information is refused")
        XCTAssertNil(TrackerAvatarResolver.profileAvatar(enabled: true, anilistAvatar: "javascript:alert(1)"))
    }

    @MainActor func testClearingRemovesOnlyThePictureAniListSet() {
        let url = "https://img.example/a.jpg"
        XCTAssertTrue(TrackerAvatarResolver.shouldClear(profileAvatar: url, anilistAvatar: url))
        XCTAssertFalse(TrackerAvatarResolver.shouldClear(profileAvatar: "https://img.example/other.jpg", anilistAvatar: url))
        XCTAssertFalse(TrackerAvatarResolver.shouldClear(profileAvatar: nil, anilistAvatar: url))
        XCTAssertFalse(TrackerAvatarResolver.shouldClear(profileAvatar: url, anilistAvatar: nil))
    }

    @MainActor func testPreferencesUseDesktopKeysAndDefaultOff() {
        let keys = ["showAnilistComments", "anilistBlurComments", "useAnilistAvatar"]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        defer { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        let preferences = AniListPreferences()
        XCTAssertFalse(preferences.showAnilistComments)
        XCTAssertFalse(preferences.anilistBlurComments)
        XCTAssertFalse(preferences.useAnilistAvatar)
        UserDefaults.standard.set(true, forKey: "anilistBlurComments")
        preferences.reloadPreferences()
        XCTAssertTrue(preferences.anilistBlurComments)
        XCTAssertTrue(ProfileSettingsStore.keys.isSuperset(of: keys), "the three keys follow the profile")
    }
}
