import XCTest
@testable import Harbor

private final class ScriptedMAL: MALTransport, @unchecked Sendable {
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

private struct UnreachableMAL: MALTransport {
    func send(_ request: URLRequest) async throws -> AniListReply { throw HarborError(code: "network") }
}

private func reply(_ json: String, status: Int = 200) -> AniListReply { AniListReply(status: status, data: Data(json.utf8), retryAfter: nil) }

@MainActor private final class EventLog { var events: [AniListSyncEvent] = [] }

@MainActor private final class MemorySessions: MALSessionPersistence {
    var stored: MALSession?
    func readMALSession(owner: String) throws -> MALSession? { stored }
    func writeMALSession(_ session: MALSession?, owner: String) throws { stored = session }
}

private func json(_ request: URLRequest) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(request.httpBody))
}

private let watching = #"{"id":5,"num_episodes":12,"my_list_status":{"status":"watching","num_episodes_watched":2,"is_rewatching":false}}"#
private let tokens = #"{"access_token":"a","refresh_token":"r","expires_in":3600}"#

/// Desktop's MyAnimeList tracker (`lib/mal`): sign-in by pasted code, token refresh, and progress sync while watching.
@MainActor final class MyAnimeListTests: XCTestCase {
    private func session(_ token: String = "old") -> MALSession {
        MALSession(accessToken: token, refreshToken: "refresh", createdAt: 1, expiresAt: 2, userName: "Owned")
    }

    func testAuthorizeAddressUsesAPlainChallengeAndFreshVerifiers() throws {
        let first = MALAuth.makeVerifier(), second = MALAuth.makeVerifier()
        XCTAssertEqual(first.count, 64); XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-._~".contains($0)) })
        let parts = try XCTUnwrap(MALAuth.authorizeURL(verifier: first).flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(parts.host, "myanimelist.net"); XCTAssertEqual(parts.path, "/v1/oauth2/authorize")
        let items = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items, ["response_type": "code", "client_id": "879be1ac300dc70611e5c828fec7bc18", "code_challenge": first, "code_challenge_method": "plain"])
        XCTAssertEqual(MALAuth.extractCode("https://harbor.site/mal/?code=ab%2Fcd&state=x"), "ab/cd")
    }

    func testPathsAndFormsAreBuiltLikeDesktop() {
        XCTAssertEqual(MALClient.resolve("/anime/1"), "https://api.myanimelist.net/v2/anime/1")
        XCTAssertEqual(MALClient.resolve("https://api.myanimelist.net/v2/anime/1"), "https://api.myanimelist.net/v2/anime/1")
        let form = String(decoding: MALClient.formBody([("num_watched_episodes", "5"), ("status", "plan to watch"), ("note", "a&b=c")]), as: UTF8.self)
        XCTAssertEqual(form, "num_watched_episodes=5&status=plan+to+watch&note=a%26b%3Dc")
    }

    func testSessionFromAPastedCodeExchangesItWithTheVerifier() async throws {
        let transport = ScriptedMAL([reply(tokens), reply(#"{"name":"Owned"}"#)])
        let now = Date(timeIntervalSince1970: 1_000)
        let made = try await MALAuth.session(from: "https://harbor.site/mal/?code=abc", verifier: "verifier", transport: transport, now: now)
        XCTAssertEqual(made, MALSession(accessToken: "a", refreshToken: "r", createdAt: 1_000_000, expiresAt: 1_000_000 + 3_600_000, userName: "Owned"))
        XCTAssertTrue(made.valid); XCTAssertTrue(made.isActive(at: now)); XCTAssertFalse(made.isActive(at: Date(timeIntervalSince1970: 5_000)))
        let exchange = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(exchange.url, MALAuth.tokenProxy)
        XCTAssertEqual(try json(exchange)["grant_type"].string, "authorization_code"); XCTAssertEqual(try json(exchange)["code"].string, "abc")
        XCTAssertEqual(try json(exchange)["code_verifier"].string, "verifier")
        XCTAssertEqual(transport.requests.last?.url?.absoluteString, "https://api.myanimelist.net/v2/users/@me")
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer a")

        let unnamed = try await MALAuth.session(from: "abc", verifier: "v", transport: ScriptedMAL([reply(tokens), reply("", status: 500)]))
        XCTAssertEqual(unnamed.userName, "unknown")

        let failures: [(String, String?, [AniListReply], String)] = [
            ("  ", "v", [], "Paste the code from MyAnimeList to continue"),
            ("abc", nil, [], "Session expired. Start over and authorize again."),
            ("abc", "v", [reply("nope", status: 400)], "MAL rejected that code (HTTP 400): nope"),
            ("abc", "v", [reply(#"{"error":"x"}"#)], "MAL did not return a token. Try authorizing again.")]
        for (paste, verifier, script, message) in failures {
            do { _ = try await MALAuth.session(from: paste, verifier: verifier, transport: ScriptedMAL(script)); XCTFail(message) }
            catch let error as TrackerUserError { XCTAssertEqual(error.message, message) }
        }
    }

    func testRefreshKeepsTheNameAndTellsRejectionFromAnUnreachableServer() async throws {
        let current = session()
        let renewed = try await MALAuth.refreshed(current, transport: ScriptedMAL([reply(#"{"access_token":"new","expires_in":60}"#)]), now: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(renewed?.accessToken, "new"); XCTAssertEqual(renewed?.refreshToken, "refresh", "A reply without a new refresh token keeps the old one")
        XCTAssertEqual(renewed?.userName, "Owned"); XCTAssertEqual(renewed?.expiresAt, 10_000 + 60_000)
        let rejected = try await MALAuth.refreshed(current, transport: ScriptedMAL([reply("{}", status: 400)]))
        XCTAssertNil(rejected)
        let empty = try await MALAuth.refreshed(MALSession(accessToken: "a", refreshToken: "", createdAt: 1, expiresAt: 2, userName: "Owned"), transport: ScriptedMAL([]))
        XCTAssertNil(empty)
        do { _ = try await MALAuth.refreshed(current, transport: UnreachableMAL()); XCTFail("An unreachable server is not a refusal") }
        catch let error as HarborError { XCTAssertEqual(error.code, "network") }
    }

    func testRequestsOutsideMyAnimeListAndHarborsProxyNeverLeave() async {
        for address in ["https://evil.example/v2/x", "http://api.myanimelist.net/v2/x", "https://api.myanimelist.net:8443/v2/x", "https://api.myanimelist.net/other",
                        "https://harbor.site/api/other", "https://user@api.myanimelist.net/v2/x", "https://myanimelist.net/v2/x"] {
            do { _ = try await HTTPClient().malReply(URLRequest(url: URL(string: address)!)); XCTFail(address) }
            catch let error as HarborError { XCTAssertEqual(error.code, "mal-request", address) }
            catch { XCTFail("\(address): \(error)") }
        }
    }

    func testSyncPlanMovesForwardOnlyAndCompletesTheLastEpisode() {
        XCTAssertEqual(MALSyncPlan.progress(status: "watching", isRewatching: false, current: 3, total: 12, target: 4), .save(watched: 4, status: "watching"))
        XCTAssertEqual(MALSyncPlan.progress(status: "watching", isRewatching: false, current: 3, total: 12, target: 12), .save(watched: 12, status: "completed"))
        XCTAssertEqual(MALSyncPlan.progress(status: "watching", isRewatching: false, current: 3, total: 12, target: 13), .skip)
        XCTAssertEqual(MALSyncPlan.progress(status: "watching", isRewatching: false, current: 3, total: 12, target: 2), .remember(3))
        XCTAssertEqual(MALSyncPlan.progress(status: "completed", isRewatching: false, current: 12, total: 12, target: 5), .skip)
        XCTAssertEqual(MALSyncPlan.progress(status: "watching", isRewatching: true, current: 2, total: 12, target: 5), .skip)
        XCTAssertEqual(MALSyncPlan.progress(status: nil, isRewatching: false, current: 0, total: 0, target: 3), .save(watched: 3, status: "watching"))
        XCTAssertTrue(MALSyncPlan.marksWatching(hasEntry: false, status: nil, watched: 0, total: 0))
        XCTAssertTrue(MALSyncPlan.marksWatching(hasEntry: true, status: "plan_to_watch", watched: 0, total: 12))
        XCTAssertFalse(MALSyncPlan.marksWatching(hasEntry: true, status: "on_hold", watched: 1, total: 12))
        XCTAssertFalse(MALSyncPlan.marksWatching(hasEntry: true, status: "plan_to_watch", watched: 12, total: 12))
    }

    func testSyncWritesTheEpisodeAsAFormOnceAndRemembersIt() async throws {
        let transport = ScriptedMAL([reply(watching), reply(#"{"status":"watching","num_episodes_watched":3}"#)])
        let log = EventLog()
        let sync = MALSync(client: MALClient(transport: transport), token: "tok", anilistToMAL: { _ in nil }, kitsuToMAL: { _ in nil }, emit: { log.events.append($0) })
        let settled = await sync.syncProgress("mal:5", episode: 3, title: "Owned Show")
        XCTAssertTrue(settled)
        XCTAssertEqual(log.events, [.syncing(title: "Owned Show", episode: 3), .ok(title: "Owned Show", episode: 3)])
        XCTAssertEqual(transport.requests[0].url?.absoluteString, "https://api.myanimelist.net/v2/anime/5?fields=num_episodes,my_list_status")
        let write = transport.requests[1]
        XCTAssertEqual(write.httpMethod, "PATCH"); XCTAssertEqual(write.url?.absoluteString, "https://api.myanimelist.net/v2/anime/5/my_list_status")
        XCTAssertEqual(write.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(decoding: try XCTUnwrap(write.httpBody), as: UTF8.self), "num_watched_episodes=3&status=watching")
        let again = await sync.syncProgress("mal:5", episode: 3, title: "Owned Show")
        XCTAssertTrue(again); XCTAssertEqual(transport.requests.count, 2)
    }

    func testAnUnconfirmedWriteStaysRetryableAndAnAheadListWritesNothing() async {
        let log = EventLog()
        let unconfirmed = ScriptedMAL([reply(watching), reply(#"{"status":"watching","num_episodes_watched":2}"#)])
        let first = MALSync(client: MALClient(transport: unconfirmed), token: "tok", anilistToMAL: { _ in nil }, kitsuToMAL: { _ in nil }, emit: { log.events.append($0) })
        let settled = await first.syncProgress("mal:5", episode: 3, title: "Owned Show")
        XCTAssertFalse(settled); XCTAssertEqual(log.events.last, .error(title: "Owned Show", reason: .updateNotConfirmed))

        let ahead = ScriptedMAL([reply(watching)])
        let second = MALSync(client: MALClient(transport: ahead), token: "tok", anilistToMAL: { _ in nil }, kitsuToMAL: { _ in nil })
        let done = await second.syncProgress("mal:5", episode: 1, title: "Owned Show")
        XCTAssertTrue(done); XCTAssertEqual(ahead.requests.count, 1)

        let completed = ScriptedMAL([reply(#"{"id":5,"num_episodes":12,"my_list_status":{"status":"completed","num_episodes_watched":12,"is_rewatching":false}}"#)])
        let third = MALSync(client: MALClient(transport: completed), token: "tok", anilistToMAL: { _ in nil }, kitsuToMAL: { _ in nil })
        let skipped = await third.syncProgress("mal:5", episode: 5, title: "Owned Show")
        XCTAssertTrue(skipped); XCTAssertEqual(completed.requests.count, 1, "A completed entry is never moved back")

        let unreachable = EventLog()
        let failing = MALSync(client: MALClient(transport: ScriptedMAL([])), token: "tok", anilistToMAL: { _ in nil }, kitsuToMAL: { _ in nil }, emit: { unreachable.events.append($0) })
        let result = await failing.syncProgress("mal:5", episode: 3, title: "Owned Show")
        XCTAssertFalse(result); XCTAssertEqual(unreachable.events, [.error(title: "Owned Show", reason: .unreachable)])
    }

    func testAnExpiredTokenIsRefreshedOnceAndTheRequestRepeated() async {
        let transport = ScriptedMAL([reply("{}", status: 401), reply(watching), reply(#"{"status":"watching","num_episodes_watched":3}"#)])
        let sync = MALSync(client: MALClient(transport: transport), token: "old", refresh: { "new" }, anilistToMAL: { _ in nil }, kitsuToMAL: { _ in nil })
        let settled = await sync.syncProgress("mal:5", episode: 3, title: "Owned Show")
        XCTAssertTrue(settled)
        XCTAssertEqual(transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer old", "Bearer new", "Bearer new"])

        let refused = ScriptedMAL([reply("{}", status: 401)])
        let log = EventLog()
        let signedOut = MALSync(client: MALClient(transport: refused), token: "old", refresh: { nil }, anilistToMAL: { _ in nil }, kitsuToMAL: { _ in nil }, emit: { log.events.append($0) })
        let result = await signedOut.syncProgress("mal:5", episode: 3, title: "Owned Show")
        XCTAssertFalse(result); XCTAssertTrue(log.events.isEmpty, "An unauthorised reply is not reported as an outage")
    }

    func testWatchingMovesAPlanToWatchEntryOnce() async throws {
        let planned = #"{"id":5,"num_episodes":12,"my_list_status":{"status":"plan_to_watch","num_episodes_watched":0,"is_rewatching":false}}"#
        let transport = ScriptedMAL([reply(planned), reply(#"{"status":"watching","num_episodes_watched":0}"#)])
        let log = EventLog()
        let sync = MALSync(client: MALClient(transport: transport), token: "tok", anilistToMAL: { _ in nil }, kitsuToMAL: { _ in nil }, emit: { log.events.append($0) })
        await sync.markWatching("mal:5", title: "Owned Show"); await sync.markWatching("mal:5", title: "Owned Show")
        XCTAssertEqual(transport.requests.count, 2); XCTAssertEqual(log.events, [.watching(title: "Owned Show")])
        XCTAssertEqual(String(decoding: try XCTUnwrap(transport.requests[1].httpBody), as: UTF8.self), "status=watching")

        let current = ScriptedMAL([reply(watching)])
        let untouched = MALSync(client: MALClient(transport: current), token: "tok", anilistToMAL: { _ in nil }, kitsuToMAL: { _ in nil })
        await untouched.markWatching("mal:5", title: "Owned Show")
        XCTAssertEqual(current.requests.count, 1)
    }

    func testMediaIdsResolveFromMalAnilistAndKitsuIds() async {
        let sync = MALSync(client: MALClient(transport: ScriptedMAL([])), token: "tok", anilistToMAL: { $0 == 7 ? 70 : nil }, kitsuToMAL: { $0 == 9 ? 90 : nil })
        let mal = await sync.mediaID(for: "mal:12:3"), anilist = await sync.mediaID(for: "anilist:7"), kitsu = await sync.mediaID(for: "kitsu:9")
        let unknown = await sync.mediaID(for: "kitsu:10"), imdb = await sync.mediaID(for: "tt0001"), junk = await sync.mediaID(for: "mal:x")
        XCTAssertEqual(mal, 12); XCTAssertEqual(anilist, 70); XCTAssertEqual(kitsu, 90); XCTAssertNil(unknown); XCTAssertNil(imdb); XCTAssertNil(junk)
    }

    func testAccountRefreshesOnceKeepsTheSessionOfAnUnreachableServerAndDropsARefusedOne() async throws {
        let store = MemorySessions()
        let account = MALAccount(owner: "owned-mal", persistence: store)
        XCTAssertThrowsError(try account.set(session()), "Nothing is saved before the account is loaded")
        try account.load(); try account.set(session()); XCTAssertEqual(store.stored, session())

        let offline = await account.refresh(transport: UnreachableMAL())
        XCTAssertNil(offline); XCTAssertEqual(account.session, session(), "An unreachable server does not sign anyone out")

        let renewed = await account.refresh(transport: ScriptedMAL([reply(#"{"access_token":"new","refresh_token":"next","expires_in":60}"#)]))
        XCTAssertEqual(renewed, "new"); XCTAssertEqual(account.session?.accessToken, "new"); XCTAssertEqual(store.stored?.refreshToken, "next")

        let refused = await account.refresh(transport: ScriptedMAL([reply("{}", status: 400)]))
        XCTAssertNil(refused); XCTAssertNil(account.session); XCTAssertNil(store.stored)
    }

    func testValidateRefreshesATokenMyAnimeListRejects() async throws {
        let store = MemorySessions()
        let account = MALAccount(owner: "owned-mal-validate", persistence: store)
        try account.load(); try account.set(session())
        let transport = ScriptedMAL([reply("{}", status: 401), reply(#"{"access_token":"fresh","refresh_token":"next","expires_in":60}"#)])
        await account.validate(transport: transport)
        XCTAssertEqual(account.session?.accessToken, "fresh")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer old")
        await account.validate(transport: ScriptedMAL([reply(#"{"name":"Owned"}"#)]))
        XCTAssertEqual(account.session?.accessToken, "fresh", "A good token is left as it is")
    }
}
