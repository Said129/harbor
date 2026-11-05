import XCTest
@testable import Harbor

private final class ScriptedAniList: AniListTransport, @unchecked Sendable {
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

private func reply(_ json: String, status: Int = 200, retryAfter: String? = nil) -> AniListReply {
    AniListReply(status: status, data: Data(json.utf8), retryAfter: retryAfter)
}

private final class PauseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []
    var all: [TimeInterval] { lock.withLock { values } }
    func add(_ value: TimeInterval) { lock.withLock { values.append(value) } }
}

@MainActor private final class EventLog { var events: [AniListSyncEvent] = [] }

@MainActor private final class MemorySessions: AniListSessionPersistence {
    var stored: AniListSession?
    func readAniListSession(owner: String) throws -> AniListSession? { stored }
    func writeAniListSession(_ session: AniListSession?, owner: String) throws { stored = session }
}

private func body(_ request: URLRequest) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(request.httpBody))
}

private let entryReply = #"{"data":{"Media":{"id":5,"episodes":12,"mediaListEntry":{"id":1,"progress":2,"status":"CURRENT"}}}}"#

/// Desktop's AniList tracker (`lib/anilist`): sign-in by pasted code, and progress sync while watching.
@MainActor final class AniListTests: XCTestCase {
    func testPastedCodesAreReadFromAddressesAndQuotes() {
        XCTAssertEqual(AniListAuth.extractCode("  \"abc123\"  "), "abc123")
        XCTAssertEqual(AniListAuth.extractCode("https://anilist.co/api/v2/oauth/pin?code=ab%2Fcd&state=1"), "ab/cd")
        XCTAssertEqual(AniListAuth.extractCode("https://example.org/#code=tok"), "tok")
        XCTAssertEqual(AniListAuth.extractCode("code=zzz"), "code=zzz", "Without ? & or # in front, the text is taken as it is")
        XCTAssertEqual(AniListAuth.extractCode("'quoted'"), "quoted")
        XCTAssertEqual(AniListAuth.extractCode("   "), "")
    }

    func testAuthorizeAddressCarriesTheClientAndPinRedirect() throws {
        let parts = try XCTUnwrap(AniListAuth.authorizeURL().flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(parts.host, "anilist.co"); XCTAssertEqual(parts.path, "/api/v2/oauth/authorize")
        let items = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items, ["client_id": "42941", "redirect_uri": "https://anilist.co/api/v2/oauth/pin", "response_type": "code"])
    }

    func testAuthenticationErrorsAreRecognisedLikeDesktop() {
        XCTAssertTrue(AniListAPIError(status: 401, body: "").isAuthenticationError)
        XCTAssertTrue(AniListAPIError(status: 400, body: #"{"errors":[{"message":"Invalid token"}]}"#).isAuthenticationError)
        XCTAssertTrue(AniListAPIError(status: 200, body: "token expired.").isAuthenticationError)
        XCTAssertTrue(AniListAPIError(status: 200, body: "Token has expired").isAuthenticationError)
        XCTAssertTrue(AniListAPIError(status: 200, body: "Unauthenticated.").isAuthenticationError)
        XCTAssertFalse(AniListAPIError(status: 400, body: "Something else").isAuthenticationError)
        XCTAssertFalse(AniListAPIError(status: 500, body: "invalid token").isAuthenticationError, "Only 401, 400 and GraphQL replies can mean a bad token")
        XCTAssertFalse(AniListAPIError(status: 200, body: #"{"errors":[{"message":"Not Found."}]}"#).isAuthenticationError)
    }

    func testClientRetriesOnceAfterARateLimitAndReportsGraphQLErrors() async throws {
        let pauses = PauseLog()
        let limited = ScriptedAniList([reply("{}", status: 429, retryAfter: "3"), reply(#"{"data":{"ok":true}}"#)])
        let client = AniListClient(transport: limited, pause: { pauses.add($0) })
        let data = try await client.request("query { x }", variables: ["id": .integer(4)], token: "tok")
        XCTAssertEqual(data["ok"], .bool(true)); XCTAssertEqual(pauses.all, [3])
        XCTAssertEqual(limited.requests.count, 2)
        let first = try XCTUnwrap(limited.requests.first)
        XCTAssertEqual(first.value(forHTTPHeaderField: "Authorization"), "Bearer tok"); XCTAssertEqual(first.httpMethod, "POST")
        XCTAssertEqual(try body(first)["variables"]["id"].integer, 4); XCTAssertEqual(try body(first)["query"].string, "query { x }")

        let anonymous = ScriptedAniList([reply(#"{"errors":[{"message":"A"},{"message":"B"}]}"#)])
        do { _ = try await AniListClient(transport: anonymous).request("q", token: nil); XCTFail("GraphQL errors fail the request") }
        catch let error as AniListAPIError { XCTAssertEqual(error, AniListAPIError(status: 200, body: "A; B")) }
        XCTAssertNil(anonymous.requests.first?.value(forHTTPHeaderField: "Authorization"))

        let twice = ScriptedAniList([reply("{}", status: 429), reply("{}", status: 429)])
        do { _ = try await AniListClient(transport: twice, pause: { pauses.add($0) }).request("q", token: nil); XCTFail("A second 429 fails") }
        catch let error as AniListAPIError { XCTAssertEqual(error.status, 429) }
        XCTAssertEqual(pauses.all, [3, 1], "Without Retry-After the wait is one second")
        let missing = ScriptedAniList([reply(#"{"data":null}"#)])
        do { _ = try await AniListClient(transport: missing).request("q", token: nil); XCTFail("No data fails") }
        catch let error as AniListAPIError { XCTAssertEqual(error.body, "Missing GraphQL data") }
    }

    func testSessionFromAPastedCodeExchangesItThenReadsTheViewer() async throws {
        let viewer = #"{"data":{"Viewer":{"id":7,"name":"Owned","avatar":{"large":"https://s4.anilist.co/l.png","medium":null},"siteUrl":"https://anilist.co/user/Owned"}}}"#
        let transport = ScriptedAniList([reply(#"{"access_token":"tok"}"#), reply(viewer)])
        let now = Date(timeIntervalSince1970: 1_000)
        let session = try await AniListAuth.session(from: "https://anilist.co/api/v2/oauth/pin?code=abc", transport: transport, now: now)
        XCTAssertEqual(session, AniListSession(accessToken: "tok", createdAt: 1_000_000, expiresAt: 1_000_000 + 31_536_000_000, userId: 7, userName: "Owned", avatar: "https://s4.anilist.co/l.png"))
        XCTAssertTrue(session.valid); XCTAssertTrue(session.isActive(at: now)); XCTAssertFalse(session.isActive(at: Date(timeIntervalSince1970: 40_000_000)))
        let exchange = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(exchange.url, AniListAuth.tokenExchange); XCTAssertEqual(try body(exchange)["code"].string, "abc")
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")

        for (script, message) in [([AniListReply](), "Paste the code from AniList to continue"),
                                  ([reply("{}", status: 400)], "AniList rejected that code. Authorize again and paste the newest one."),
                                  ([reply(#"{"nope":1}"#)], "AniList did not return a token. Try authorizing again.")] {
            let paste = script.isEmpty ? "  " : "abc"
            do { _ = try await AniListAuth.session(from: paste, transport: ScriptedAniList(script)); XCTFail(message) }
            catch let error as AniListUserError { XCTAssertEqual(error.message, message) }
        }
    }

    func testRequestsOutsideAniListAndHarborsExchangeNeverLeave() async {
        for address in ["https://evil.example/", "http://graphql.anilist.co/", "https://graphql.anilist.co:8443/", "https://graphql.anilist.co/other",
                        "https://user@graphql.anilist.co/", "https://bugs.harbor.site/v1/other", "https://anilist.co/"] {
            do { _ = try await HTTPClient().anilistReply(URLRequest(url: URL(string: address)!)); XCTFail(address) }
            catch let error as HarborError { XCTAssertEqual(error.code, "anilist-request", address) }
            catch { XCTFail("\(address): \(error)") }
        }
    }

    func testTrackerTargetFollowsKitsuStreamsThenMetaIds() {
        XCTAssertEqual(AniListTracking.target(metaID: "kitsu:12", videoID: "kitsu:12:5", fallbackEpisode: 3), AniListTrackerTarget(id: "kitsu:12", episode: 5))
        XCTAssertEqual(AniListTracking.target(metaID: "tt0001", videoID: "kitsu:99:4", fallbackEpisode: 1), AniListTrackerTarget(id: "kitsu:99", episode: 4),
                       "A Kitsu stream id names the entry even when the title is an IMDb id")
        XCTAssertEqual(AniListTracking.target(metaID: "kitsu:12", sourceID: "kitsu:13", videoID: "kitsu:12:5", fallbackEpisode: 7), AniListTrackerTarget(id: "kitsu:13", episode: 7),
                       "A stream of another entry says nothing about this one")
        XCTAssertEqual(AniListTracking.target(metaID: "anilist:3", videoID: nil, fallbackEpisode: 2), AniListTrackerTarget(id: "anilist:3", episode: 2))
        XCTAssertNil(AniListTracking.target(metaID: "tt0001", videoID: "tt0001:1:2", fallbackEpisode: 2))
        XCTAssertEqual(AniListTracking.entryID("mal:5"), "mal:5")
        for bad in ["kitsu:5:2", "mal:x", "tmdb:1", "kitsu:", ""] { XCTAssertNil(AniListTracking.entryID(bad), bad) }
        XCTAssertNil(AniListTracking.entryID(nil))
    }

    func testPlaybackPhasesFollowNinetySecondsAndSeventyPercent() {
        XCTAssertEqual(AniListTracking.phase(position: 89, duration: 1_400, ended: false), .none)
        XCTAssertEqual(AniListTracking.phase(position: 90, duration: 1_400, ended: false), .watching)
        XCTAssertEqual(AniListTracking.phase(position: 979, duration: 1_400, ended: false), .watching)
        XCTAssertEqual(AniListTracking.phase(position: 980, duration: 1_400, ended: false), .progress)
        XCTAssertEqual(AniListTracking.phase(position: 1_000, duration: 0, ended: false), .watching, "An unknown length never reaches the ratio")
        XCTAssertEqual(AniListTracking.phase(position: 95, duration: 100, ended: true), .progress)
        XCTAssertEqual(AniListTracking.phase(position: 80, duration: 100, ended: true), .none, "Short clips never sync")
        XCTAssertEqual(AniListTracking.phase(position: .nan, duration: 100, ended: true), .none)
    }

    func testSyncPlanMovesForwardOnlyAndCompletesTheLastEpisode() {
        XCTAssertEqual(AniListSyncPlan.progress(status: "CURRENT", current: 3, total: 12, target: 4), .save(progress: 4, status: "CURRENT"))
        XCTAssertEqual(AniListSyncPlan.progress(status: "CURRENT", current: 3, total: 12, target: 12), .save(progress: 12, status: "COMPLETED"))
        XCTAssertEqual(AniListSyncPlan.progress(status: "CURRENT", current: 3, total: 12, target: 13), .skip, "Past the last episode")
        XCTAssertEqual(AniListSyncPlan.progress(status: "CURRENT", current: 3, total: 12, target: 3), .remember(3))
        XCTAssertEqual(AniListSyncPlan.progress(status: "CURRENT", current: 3, total: 12, target: 2), .remember(3), "Never lowers a count")
        XCTAssertEqual(AniListSyncPlan.progress(status: "COMPLETED", current: 12, total: 12, target: 5), .skip)
        XCTAssertEqual(AniListSyncPlan.progress(status: "REPEATING", current: 2, total: 12, target: 5), .skip)
        XCTAssertEqual(AniListSyncPlan.progress(status: "PLANNING", current: 0, total: 0, target: 100), .save(progress: 100, status: "CURRENT"), "Unknown length")
        XCTAssertTrue(AniListSyncPlan.marksWatching(hasEntry: false, status: nil, progress: 0, total: 0))
        XCTAssertTrue(AniListSyncPlan.marksWatching(hasEntry: true, status: "PLANNING", progress: 0, total: 12))
        XCTAssertFalse(AniListSyncPlan.marksWatching(hasEntry: true, status: "CURRENT", progress: 1, total: 12))
        XCTAssertFalse(AniListSyncPlan.marksWatching(hasEntry: true, status: "PLANNING", progress: 12, total: 12))
    }

    func testSyncWritesTheEpisodeOnceAndRemembersIt() async throws {
        let transport = ScriptedAniList([reply(entryReply), reply(#"{"data":{"SaveMediaListEntry":{"id":1,"progress":3,"status":"CURRENT"}}}"#)])
        let log = EventLog()
        let sync = AniListSync(client: AniListClient(transport: transport), token: "tok", kitsuToAniList: { _ in nil }, emit: { log.events.append($0) })
        let settled = await sync.syncProgress("anilist:5", episode: 3, title: "Owned Show")
        XCTAssertTrue(settled)
        XCTAssertEqual(log.events, [.syncing(title: "Owned Show", episode: 3), .ok(title: "Owned Show", episode: 3)])
        let variables = try body(transport.requests[1])["variables"]
        XCTAssertEqual(variables["mediaId"].integer, 5); XCTAssertEqual(variables["progress"].integer, 3); XCTAssertEqual(variables["status"].string, "CURRENT")
        let again = await sync.syncProgress("anilist:5", episode: 3, title: "Owned Show")
        XCTAssertTrue(again); XCTAssertEqual(transport.requests.count, 2, "The same episode within a minute writes and asks nothing")
    }

    func testAnUnconfirmedWriteStaysRetryableAndAnAheadListWritesNothing() async {
        let unconfirmed = ScriptedAniList([reply(entryReply), reply(#"{"data":{"SaveMediaListEntry":{"id":1,"progress":2,"status":"CURRENT"}}}"#)])
        let log = EventLog()
        let sync = AniListSync(client: AniListClient(transport: unconfirmed), token: "tok", kitsuToAniList: { _ in nil }, emit: { log.events.append($0) })
        let settled = await sync.syncProgress("anilist:5", episode: 3, title: "Owned Show")
        XCTAssertFalse(settled); XCTAssertEqual(log.events.last, .error(title: "Owned Show", reason: .updateNotConfirmed))

        let ahead = ScriptedAniList([reply(entryReply)])
        let quiet = EventLog()
        let other = AniListSync(client: AniListClient(transport: ahead), token: "tok", kitsuToAniList: { _ in nil }, emit: { quiet.events.append($0) })
        let done = await other.syncProgress("anilist:5", episode: 1, title: "Owned Show")
        XCTAssertTrue(done); XCTAssertEqual(ahead.requests.count, 1, "Only the entry was read"); XCTAssertTrue(quiet.events.isEmpty)

        let failing = ScriptedAniList([])
        let failures = EventLog()
        let unreachable = AniListSync(client: AniListClient(transport: failing), token: "tok", kitsuToAniList: { _ in nil }, emit: { failures.events.append($0) })
        let result = await unreachable.syncProgress("anilist:5", episode: 3, title: "Owned Show")
        XCTAssertFalse(result); XCTAssertEqual(failures.events, [.error(title: "Owned Show", reason: .unreachable)])
    }

    func testWatchingMovesAPlanningEntryToCurrentOnce() async throws {
        let planning = #"{"data":{"Media":{"id":5,"episodes":12,"mediaListEntry":{"id":1,"progress":0,"status":"PLANNING"}}}}"#
        let transport = ScriptedAniList([reply(planning), reply(#"{"data":{"SaveMediaListEntry":{"id":1,"status":"CURRENT"}}}"#)])
        let log = EventLog()
        let sync = AniListSync(client: AniListClient(transport: transport), token: "tok", kitsuToAniList: { _ in nil }, emit: { log.events.append($0) })
        await sync.markWatching("anilist:5", title: "Owned Show")
        await sync.markWatching("anilist:5", title: "Owned Show")
        XCTAssertEqual(transport.requests.count, 2); XCTAssertEqual(log.events, [.watching(title: "Owned Show")])
        XCTAssertEqual(try body(transport.requests[1])["variables"]["status"].string, "CURRENT")

        let current = ScriptedAniList([reply(entryReply)])
        let untouched = AniListSync(client: AniListClient(transport: current), token: "tok", kitsuToAniList: { _ in nil })
        await untouched.markWatching("anilist:5", title: "Owned Show")
        XCTAssertEqual(current.requests.count, 1, "A list entry that is already under way is left alone")
    }

    func testMediaIdsResolveFromAnilistKitsuAndMalIds() async {
        let transport = ScriptedAniList([reply(#"{"data":{"Media":{"id":77}}}"#)])
        let sync = AniListSync(client: AniListClient(transport: transport), token: "tok", kitsuToAniList: { $0 == 9 ? 5 : nil })
        let direct = await sync.mediaID(for: "anilist:12:3"), kitsu = await sync.mediaID(for: "kitsu:9"), unknown = await sync.mediaID(for: "kitsu:10")
        let mal = await sync.mediaID(for: "mal:30"), imdb = await sync.mediaID(for: "tt0001"), junk = await sync.mediaID(for: "anilist:x")
        XCTAssertEqual(direct, 12); XCTAssertEqual(kitsu, 5); XCTAssertNil(unknown); XCTAssertEqual(mal, 77); XCTAssertNil(imdb); XCTAssertNil(junk)
        XCTAssertEqual(transport.requests.count, 1, "Only the MyAnimeList id asks AniList")
    }

    func testAccountDropsATokenAniListRejectsAndRefreshesTheAvatar() async throws {
        let store = MemorySessions()
        let account = AniListAccount(owner: "owned-anilist", persistence: store)
        let session = AniListSession(accessToken: "tok", createdAt: 1, expiresAt: 2, userId: 7, userName: "Owned", avatar: nil)
        XCTAssertThrowsError(try account.set(session), "Nothing is saved before the account is loaded")
        try account.load(); XCTAssertNil(account.session)
        try account.set(session); XCTAssertEqual(store.stored, session)
        XCTAssertThrowsError(try account.set(AniListSession(accessToken: "", createdAt: 1, expiresAt: 2, userId: 7, userName: "Owned")))

        let viewer = #"{"data":{"Viewer":{"id":7,"name":"Owned","avatar":{"large":"https://s4.anilist.co/new.png"}}}}"#
        await account.validate(transport: ScriptedAniList([reply(viewer)]))
        XCTAssertEqual(account.session?.avatar, "https://s4.anilist.co/new.png"); XCTAssertEqual(store.stored?.avatar, "https://s4.anilist.co/new.png")
        await account.validate(transport: ScriptedAniList([reply("Something went wrong", status: 500)]))
        XCTAssertNotNil(account.session, "A server error does not sign anyone out")
        await account.validate(transport: ScriptedAniList([reply(#"{"errors":[{"message":"Invalid token"}]}"#, status: 400)]))
        XCTAssertNil(account.session); XCTAssertNil(store.stored)
    }
}
