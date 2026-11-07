import XCTest
@testable import Harbor

/// Desktop's MyAnimeList lists (`lib/mal/lists.ts`, `views/library/mal-tab.tsx`), with canned API pages.
final class MyAnimeListListsTests: XCTestCase {
    private final class ScriptedMALLists: MALTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [AniListReply]
        private var sent: [URLRequest] = []
        init(_ replies: [AniListReply]) { self.replies = replies }
        var requests: [URLRequest] { lock.withLock { sent } }
        func send(_ request: URLRequest) async throws -> AniListReply {
            lock.withLock {
                sent.append(request)
                return replies.isEmpty ? AniListReply(status: 500, data: Data(), retryAfter: nil) : replies.removeFirst()
            }
        }
    }

    private let nextAddress = "https://api.myanimelist.net/v2/users/@me/animelist?offset=1000"

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func node(_ id: Int, _ status: String, _ title: String, watched: Int = 0, total: Int? = 12, type: String = "tv") -> String {
        let totalText = total.map { String($0) } ?? "null"
        return """
        {"node": {"id": \(id), "title": "\(title)", "main_picture": {"medium": "m\(id)", "large": "l\(id)"}, "num_episodes": \(totalText), "media_type": "\(type)", "my_list_status": {"status": "\(status)", "score": 0, "num_episodes_watched": \(watched), "is_rewatching": false, "updated_at": "2026-01-01T00:00:00+00:00"}}}
        """
    }

    private func pageText(_ nodes: [String], next: String? = nil) -> String {
        let nextText = next.map { "\"\($0)\"" } ?? "null"
        return "{\"data\": [\(nodes.joined(separator: ","))], \"paging\": {\"next\": \(nextText)}}"
    }

    /// One API page: a watching title, a plan-to-watch movie, a node with no list status, a node with an unknown
    /// status, a duplicate of the first title, a blank title, a title with no episode count and a completed title.
    private func cannedNodes() -> [String] {
        [
            node(1, "watching", "Alpha", watched: 3, total: 12),
            node(2, "plan_to_watch", "Beta", watched: 5, total: 0, type: "movie"),
            #"{"node": {"id": 3, "title": "No status", "my_list_status": null}}"#,
            node(4, "rewatching", "Bogus"),
            node(1, "completed", "Alpha again", watched: 12),
            node(6, "on_hold", ""),
            node(7, "dropped", "Gamma", total: nil),
            node(8, "completed", "Delta", watched: 24, total: 24)
        ]
    }

    private func canned() throws -> [MALListEntry] {
        MALLists.unique(MALLists.parsePage(try json(pageText(cannedNodes()))))
    }

    func testParsePageSkipsNodesWithoutAKnownStatusAndKeepsTheRest() throws {
        let entries = MALLists.parsePage(try json(pageText(cannedNodes())))
        XCTAssertEqual(entries.map(\.media.id), [1, 2, 1, 6, 7, 8])
        XCTAssertEqual(entries.first?.status, .watching)
        XCTAssertEqual(entries.first?.watched, 3)
        XCTAssertEqual(entries.first?.media.poster, "l1", "the large picture is preferred")
        XCTAssertEqual(entries[1].media.isMovie, true)
    }

    func testUniqueKeepsTheFirstPlaceEachTitleIsListed() throws {
        let entries = try canned()
        XCTAssertEqual(entries.map(\.media.id), [1, 2, 6, 7, 8])
        XCTAssertEqual(entries.first?.status, .watching, "the duplicate completed entry is dropped")
        XCTAssertEqual(entries.first?.watched, 3)
    }

    func testNextAddressIsReadFromPagingAndAbsentAtTheEnd() throws {
        XCTAssertEqual(MALLists.nextPath(try json(pageText([], next: nextAddress))), nextAddress)
        XCTAssertNil(MALLists.nextPath(try json(pageText([], next: nil))))
    }

    func testSectionTitlesAndOrderOnTheScreenAreDesktops() {
        XCTAssertEqual(MALListSection.allCases.map(\.title), ["Watching", "Plan to Watch", "Completed", "On Hold", "Dropped"])
    }

    func testGroupsFollowTheScreenOrderNotTheOrderTheAPIReturnsThem() throws {
        let entries = MALLists.unique(MALLists.parsePage(try json(pageText([
            node(8, "completed", "Delta"), node(7, "dropped", "Gamma"), node(9, "watching", "Zeta"), node(2, "plan_to_watch", "Beta")
        ]))))
        let groups = MALLists.groups(entries, kind: .all, query: "")
        XCTAssertEqual(groups.map(\.section), [.watching, .planning, .completed, .dropped])
        XCTAssertEqual(groups.first?.entries.map(\.media.id), [9], "a group keeps the order the API gave")
    }

    func testTypeFilterSplitsMoviesFromShowsAndCountsEachPill() throws {
        let entries = try canned()
        XCTAssertEqual(MALLists.groups(entries, kind: .movie, query: "").flatMap(\.entries).map(\.media.id), [2])
        // Groups follow the screen order (watching, plan to watch, completed, on hold, dropped), so the completed title 8 comes before the dropped 6 and 7.
        XCTAssertEqual(MALLists.groups(entries, kind: .series, query: "").flatMap(\.entries).map(\.media.id), [1, 8, 6, 7])
        XCTAssertEqual(MALLists.count(entries, kind: .series, query: ""), 4)
        XCTAssertEqual(MALLists.count(entries, kind: .all, query: ""), 5)
    }

    func testSearchTrimsIgnoresCaseAndFindsNothingForAnUnknownTitle() throws {
        let entries = try canned()
        XCTAssertEqual(MALLists.groups(entries, kind: .all, query: "  alpha ").flatMap(\.entries).map(\.media.id), [1])
        XCTAssertEqual(MALLists.groups(entries, kind: .all, query: "DELTA").flatMap(\.entries).map(\.media.id), [8])
        XCTAssertTrue(MALLists.groups(entries, kind: .all, query: "zzz").isEmpty)
    }

    func testProgressShowsTheTotalOnlyWhenMyAnimeListKnowsIt() throws {
        let entries = try canned()
        XCTAssertEqual(MALLists.progressLabel(entries[0]), "3 / 12")
        XCTAssertEqual(MALLists.progressLabel(entries[1]), "5", "a zero total is unknown, not zero episodes")
        XCTAssertEqual(MALLists.progressLabel(entries[3]), "0", "a missing total shows the count alone")
    }

    func testHarborTitleUsesTheMalIdentityAndSkipsBlankTitles() throws {
        let entries = try canned()
        let alpha = try XCTUnwrap(MALLists.harborMedia(entries[0].media))
        XCTAssertEqual(alpha.id, "mal:1")
        XCTAssertEqual(alpha.type, "series")
        XCTAssertEqual(alpha.name, "Alpha")
        XCTAssertEqual(alpha.poster, "l1")
        let beta = try XCTUnwrap(MALLists.harborMedia(entries[1].media))
        XCTAssertEqual(beta.type, "movie")
        XCTAssertNil(MALLists.harborMedia(entries[2].media), "a blank title does not open a detail screen")
    }

    func testFetchFollowsPagingAndRefreshesOnceAfterAnUnauthorizedPage() async throws {
        let first = AniListReply(status: 200, data: Data(pageText([node(1, "watching", "Alpha")], next: nextAddress).utf8), retryAfter: nil)
        let second = AniListReply(status: 200, data: Data(pageText([node(2, "completed", "Beta")]).utf8), retryAfter: nil)
        let transport = ScriptedMALLists([AniListReply(status: 401, data: Data(), retryAfter: nil), first, second])
        let entries = try await MALListsService.fetchAll(token: "old-token", client: MALClient(transport: transport),
                                                         refresh: { "fresh-token" })
        XCTAssertEqual(entries.map(\.media.id), [1, 2])
        let requests = transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer old-token")
        XCTAssertEqual(requests[1].url, requests[0].url, "the unauthorized page is repeated")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fresh-token")
        XCTAssertEqual(requests[2].url?.absoluteString, nextAddress)
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer fresh-token")
    }

    func testFetchRethrowsTheUnauthorizedErrorWhenMyAnimeListRefusesTheRefresh() async throws {
        let transport = ScriptedMALLists([AniListReply(status: 401, data: Data(), retryAfter: nil)])
        do {
            _ = try await MALListsService.fetchAll(token: "old-token", client: MALClient(transport: transport), refresh: { nil })
            XCTFail("a refused refresh must fail the list")
        } catch let error as MALAPIError {
            XCTAssertEqual(error.status, 401)
        }
    }

    func testFetchStopsWhenTheNextAddressRepeats() async throws {
        let page = AniListReply(status: 200, data: Data(pageText([node(1, "watching", "Alpha")], next: nextAddress).utf8), retryAfter: nil)
        let transport = ScriptedMALLists([page, page, page])
        let entries = try await MALListsService.fetchAll(token: "token", client: MALClient(transport: transport), refresh: { nil })
        XCTAssertEqual(entries.map(\.media.id), [1])
        XCTAssertEqual(transport.requests.count, 2, "the repeated address is requested once more, then the loop ends")
    }
}
