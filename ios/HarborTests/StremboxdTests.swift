import XCTest
@testable import Harbor

/// Desktop's Letterboxd (Stremboxd) bridge: configuration, URLs, response mapping, rail naming and ordering (`lib/stremboxd/*`).
/// Canned JSON and a fake transport only; no request leaves the test.
final class StremboxdTests: XCTestCase {
    private struct FakeTransport: StremboxdTransport {
        let respond: @Sendable (URLRequest) -> StremboxdReply
        func send(_ request: URLRequest) async throws -> StremboxdReply { respond(request) }
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private let userID = "0123456789abcdef0123456789abcdef"

    // MARK: Settings and configuration

    func testSettingsDefaultsMatchDesktopWhenNothingIsStored() throws {
        let settings = try JSONDecoder().decode(StremboxdSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings, StremboxdSettings())
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.mode, .publicMode)
        XCTAssertEqual(settings.selectedCatalogs, ["letterboxd-watchlist", "letterboxd-liked", "letterboxd-popular", "letterboxd-top250"])
        XCTAssertTrue(settings.showRatingsOnPosters)
    }

    func testPublicConfigCarriesUsernameCatalogsAndLists() throws {
        var settings = StremboxdSettings()
        settings.username = " demo-user "
        settings.selectedCatalogs = [StremboxdCatalogID.watchlist, StremboxdCatalogID.popular, StremboxdCatalogID.list("77")]
        settings.listRefs = [StremboxdListRef(id: "77", name: "Favourites", owner: "demo-user", filmCount: 12)]
        settings.showRatingsOnPosters = false

        let config = StremboxdConfigCodec.publicConfig(settings)
        XCTAssertEqual(config.u, "demo-user")
        XCTAssertEqual(config.c.watchlist, true)
        XCTAssertNil(config.c.likedFilms)
        XCTAssertTrue(config.c.popular)
        XCTAssertFalse(config.c.top250)
        XCTAssertEqual(config.l, ["77"])
        XCTAssertFalse(config.r)
    }

    func testConfigSegmentIsBase64URLAndRoundTrips() throws {
        var settings = StremboxdSettings()
        settings.username = "demo-user"
        let config = StremboxdConfigCodec.publicConfig(settings)
        let segment = try StremboxdConfigCodec.encode(config)
        XCTAssertFalse(segment.contains("+"))
        XCTAssertFalse(segment.contains("/"))
        XCTAssertFalse(segment.contains("="))
        XCTAssertEqual(StremboxdConfigCodec.decode(segment), config)
        XCTAssertNil(StremboxdConfigCodec.decode("%%%"))
    }

    func testSettingsRoundTripThroughJSON() throws {
        var settings = StremboxdSettings()
        settings.enabled = true
        settings.mode = .full
        settings.username = "demo-user"
        settings.listRefs = [StremboxdListRef(id: "9", name: "Cult", owner: nil, filmCount: nil)]
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(StremboxdSettings.self, from: data), settings)
    }

    // MARK: Rails

    func testRowsAreOrderedByExplicitOrderThenPriority() {
        let selected = [StremboxdCatalogID.top250, StremboxdCatalogID.popular, StremboxdCatalogID.watchlist, StremboxdCatalogID.diary]
        XCTAssertEqual(
            StremboxdRails.orderedVisible(selected: selected, hidden: [StremboxdCatalogID.diary], order: []),
            [StremboxdCatalogID.watchlist, StremboxdCatalogID.popular, StremboxdCatalogID.top250]
        )
        XCTAssertEqual(
            StremboxdRails.orderedVisible(selected: selected, hidden: [], order: [StremboxdCatalogID.top250, StremboxdCatalogID.watchlist]),
            [StremboxdCatalogID.top250, StremboxdCatalogID.watchlist, StremboxdCatalogID.diary, StremboxdCatalogID.popular]
        )
    }

    func testRowNeedsFourFilms() {
        XCTAssertFalse(StremboxdRails.keepsRow(metaCount: 3))
        XCTAssertTrue(StremboxdRails.keepsRow(metaCount: 4))
    }

    func testFullModeReadsLikedFilmsUnderItsOwnID() {
        XCTAssertEqual(StremboxdRails.realCatalogID(StremboxdCatalogID.liked, full: true), StremboxdCatalogID.likedFilms)
        XCTAssertEqual(StremboxdRails.realCatalogID(StremboxdCatalogID.liked, full: false), StremboxdCatalogID.liked)
    }

    func testRowNamesUseServerNameThenTemplateThenDefault() {
        XCTAssertEqual(
            StremboxdRails.rowName(catalogID: StremboxdCatalogID.watchlist, realID: StremboxdCatalogID.watchlist, full: true, displayName: "karsten", manifestName: "karsten's Watchlist", list: nil),
            .server("karsten's Watchlist")
        )
        XCTAssertEqual(
            StremboxdRails.rowName(catalogID: StremboxdCatalogID.watchlist, realID: StremboxdCatalogID.watchlist, full: true, displayName: "karsten", manifestName: nil, list: nil),
            .template("{name}'s Watchlist", name: "karsten")
        )
        XCTAssertEqual(
            StremboxdRails.rowName(catalogID: StremboxdCatalogID.watchlist, realID: StremboxdCatalogID.watchlist, full: false, displayName: "", manifestName: nil, list: nil),
            .fallback("Letterboxd Watchlist")
        )
        let ref = StremboxdListRef(id: "77", name: "Favourites", owner: "demo-user", filmCount: 12)
        XCTAssertEqual(
            StremboxdRails.rowName(catalogID: StremboxdCatalogID.list("77"), realID: StremboxdCatalogID.list("77"), full: false, displayName: "", manifestName: nil, list: ref),
            .list(name: "Favourites", owner: "demo-user")
        )
        XCTAssertEqual(
            StremboxdRails.rowName(catalogID: "letterboxd-unknown", realID: "letterboxd-unknown", full: false, displayName: "", manifestName: nil, list: nil),
            .unnamed("letterboxd-unknown")
        )
    }

    func testListRowTitleAddsOwner() {
        XCTAssertEqual(StremboxdRails.RowName.list(name: "Favourites", owner: "demo-user").title, "Favourites · demo-user")
        XCTAssertEqual(StremboxdRails.RowName.list(name: "Favourites", owner: nil).title, "Favourites")
    }

    // MARK: URLs

    func testCatalogURLsFollowStremboxdRoutes() throws {
        let first = StremboxdURL.catalog(.config("abc_-"), catalogID: StremboxdCatalogID.popular, skip: 0)
        XCTAssertEqual(first?.absoluteString, "https://api.stremboxd.com/abc_-/catalog/movie/letterboxd-popular.json")
        let second = StremboxdURL.catalog(.config("abc_-"), catalogID: StremboxdCatalogID.popular, skip: 100)
        XCTAssertEqual(second?.absoluteString, "https://api.stremboxd.com/abc_-/catalog/movie/letterboxd-popular/skip=100.json")
        let full = StremboxdURL.catalog(.full(userID), catalogID: StremboxdCatalogID.diary, skip: 0)
        XCTAssertEqual(full?.absoluteString, "https://api.stremboxd.com/stremio/\(userID)/catalog/movie/letterboxd-diary.json")
        XCTAssertEqual(StremboxdURL.manifest(.full(userID))?.absoluteString, "https://api.stremboxd.com/stremio/\(userID)/manifest.json")
    }

    func testMixedCaseListIdStillBuildsItsCatalogURL() {
        let url = StremboxdURL.catalog(.config("abc"), catalogID: StremboxdCatalogID.list("AbC_9-x"), skip: 0)
        XCTAssertEqual(url?.absoluteString, "https://api.stremboxd.com/abc/catalog/movie/letterboxd-list-AbC_9-x.json")
    }

    func testURLsRejectValuesThatChangeTheRoute() {
        XCTAssertNil(StremboxdURL.catalog(.config("../x"), catalogID: StremboxdCatalogID.popular, skip: 0))
        XCTAssertNil(StremboxdURL.catalog(.config("abc"), catalogID: "letterboxd-popular/../x", skip: 0))
        XCTAssertNil(StremboxdURL.catalog(.config("abc"), catalogID: StremboxdCatalogID.popular, skip: -1))
    }

    func testOnlyHTTPSStremboxdHostIsAllowed() throws {
        XCTAssertTrue(StremboxdURL.allowed(try XCTUnwrap(URL(string: "https://api.stremboxd.com/abc/manifest.json"))))
        XCTAssertFalse(StremboxdURL.allowed(try XCTUnwrap(URL(string: "http://api.stremboxd.com/abc/manifest.json"))))
        XCTAssertFalse(StremboxdURL.allowed(try XCTUnwrap(URL(string: "https://evil.example/abc/manifest.json"))))
    }

    // MARK: Mapping

    func testCatalogItemBecomesMovieMedia() throws {
        let meta = try json("""
        {"id":"tt0111161","type":"series","name":"The Shawshank Redemption","poster":"https://img.example/p.jpg","description":"Two prisoners.","year":1994,"imdbRating":"9.3","genres":["Drama"],"runtime":"142 min"}
        """)
        let media = try XCTUnwrap(StremboxdMapping.media(meta))
        XCTAssertEqual(media.id, "tt0111161")
        XCTAssertEqual(media.type, "movie")
        XCTAssertEqual(media.name, "The Shawshank Redemption")
        XCTAssertEqual(media.releaseInfo, "1994")
        XCTAssertEqual(media.imdbRating, "9.3")
        XCTAssertEqual(media.genres, ["Drama"])
    }

    func testCatalogPageKeepsServerOrderAndSkipsBrokenItems() throws {
        let page = try json("""
        {"metas":[{"id":"tt0000001","name":"First"},{"name":"No id"},{"id":"tt0000002","name":"Second"}]}
        """)
        XCTAssertEqual(StremboxdMapping.catalog(page).map(\.id), ["tt0000001", "tt0000002"])
    }

    func testManifestChecksMatchDesktopMessages() throws {
        let good = try json("""
        {"id":"community.stremboxd","catalogs":[{"type":"movie","id":"letterboxd-watchlist","name":"Watchlist"},{"type":"movie","id":"letterboxd-popular","name":"Popular"}]}
        """)
        XCTAssertEqual(StremboxdMapping.check(manifest: good, expectWatchlist: true), .valid(catalogs: 2, hasWatchlist: true))

        let noWatchlist = try json("""
        {"id":"community.stremboxd","catalogs":[{"type":"movie","id":"letterboxd-popular","name":"Popular"}]}
        """)
        XCTAssertEqual(
            StremboxdMapping.check(manifest: noWatchlist, expectWatchlist: true),
            .invalid("Letterboxd did not return a watchlist for this username. Check the username is correct and public.")
        )
        XCTAssertEqual(StremboxdMapping.check(manifest: noWatchlist, expectWatchlist: false), .valid(catalogs: 1, hasWatchlist: false))

        let other = try json(#"{"id":"org.other","catalogs":[{"type":"movie","id":"x","name":"x"}]}"#)
        XCTAssertEqual(StremboxdMapping.check(manifest: other, expectWatchlist: false), .invalid("Unexpected manifest from Stremboxd."))

        let empty = try json(#"{"id":"community.stremboxd","catalogs":[]}"#)
        XCTAssertEqual(StremboxdMapping.check(manifest: empty, expectWatchlist: false), .invalid("No catalogs returned for this configuration."))
    }

    func testPreferencesSendTheSelectedCatalogsAndLists() throws {
        let prefs = StremboxdMapping.preferences(
            selected: [StremboxdCatalogID.liked, StremboxdCatalogID.popular],
            listRefs: [StremboxdListRef(id: "77", name: "Favourites", owner: nil, filmCount: nil)]
        )
        XCTAssertEqual(prefs["catalogs"]["likedFilms"], .bool(true))
        XCTAssertEqual(prefs["catalogs"]["watchlist"], .bool(false))
        XCTAssertEqual(prefs["catalogs"]["popular"], .bool(true))
        XCTAssertEqual(prefs["ownLists"], .array([.string("77")]))
    }

    func testLoginResponseBecomesSessionWithoutPassword() throws {
        let login = try json("""
        {"userToken":"test-token-not-real","manifestUrl":"https://api.stremboxd.com/x/manifest.json","user":{"id":"\(userID)","username":"demo-user","displayName":null},"lists":[{"id":77,"name":"Favourites","owner":"demo-user","filmCount":12}]}
        """)
        let session = try XCTUnwrap(StremboxdMapping.session(fromLogin: login, loginAt: 1_000))
        XCTAssertEqual(session.userToken, "test-token-not-real")
        XCTAssertEqual(session.userId, userID)
        XCTAssertEqual(session.username, "demo-user")
        XCTAssertNil(session.displayName)
        XCTAssertEqual(session.rowName, "demo-user")
        XCTAssertEqual(session.lists, [StremboxdListRef(id: "77", name: "Favourites", owner: "demo-user", filmCount: 12)])
        XCTAssertNil(StremboxdMapping.session(fromLogin: try json(#"{"user":{"id":"1","username":"x"}}"#), loginAt: 0))
    }

    // MARK: Client through a fake transport

    func testManifestIsReadThroughTheTransport() async throws {
        let data = Data(#"{"id":"community.stremboxd","catalogs":[{"type":"movie","id":"letterboxd-watchlist","name":"Watchlist"}]}"#.utf8)
        let client = StremboxdClient(transport: FakeTransport(respond: { (_: URLRequest) -> StremboxdReply in StremboxdReply(status: 200, data: data) }))
        let manifest = try await client.manifest(.config("abc"))
        XCTAssertEqual(StremboxdMapping.check(manifest: manifest, expectWatchlist: true), .valid(catalogs: 1, hasWatchlist: true))
    }

    func testCatalogPageMapsToMedia() async throws {
        let data = Data(#"{"metas":[{"id":"tt0000001","name":"First"},{"id":"tt0000002","name":"Second"}]}"#.utf8)
        let client = StremboxdClient(transport: FakeTransport(respond: { (_: URLRequest) -> StremboxdReply in StremboxdReply(status: 200, data: data) }))
        let media = try await client.catalog(.full(userID), catalogID: StremboxdCatalogID.watchlist, skip: 0)
        XCTAssertEqual(media.map(\.name), ["First", "Second"])
    }

    func testTwoFactorLoginReportsItsCode() async {
        let data = Data(#"{"error":"Two-factor code required","code":"2FA_REQUIRED"}"#.utf8)
        let client = StremboxdClient(transport: FakeTransport(respond: { (_: URLRequest) -> StremboxdReply in StremboxdReply(status: 401, data: data) }))
        do {
            _ = try await client.login(username: "demo-user", password: "test-password", totp: nil, loginAt: 0)
            XCTFail("Expected the two-factor step")
        } catch let error as StremboxdError {
            XCTAssertEqual(error.code, "2FA_REQUIRED")
            XCTAssertEqual(error.status, 401)
            XCTAssertEqual(error.message, "Two-factor code required")
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testServerErrorKeepsItsStatus() async {
        let client = StremboxdClient(transport: FakeTransport(respond: { (_: URLRequest) -> StremboxdReply in StremboxdReply(status: 400, data: Data()) }))
        do {
            _ = try await client.manifest(.config("abc"))
            XCTFail("Expected a failure")
        } catch let error as StremboxdError {
            XCTAssertEqual(StremboxdVerification.forError(error), .failed("Invalid configuration."))
            XCTAssertEqual(StremboxdVerification.forError(StremboxdError(status: 503, code: nil, message: "x")), .httpFailed(503))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}
