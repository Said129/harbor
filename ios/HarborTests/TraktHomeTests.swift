import XCTest
@testable import Harbor

@MainActor final class TraktHomeTests: XCTestCase {
    private let configuration = MetadataConfiguration(tmdbKey: "owned-tmdb-key", region: "US", language: "en-US", translateTitles: true)
    static func reference() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: TraktHomeTests.self).url(forResource: "trakt-home-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    static func account() throws -> TraktAccountStore {
        let account = TraktAccountStore(owner: "owned-trakt-home-" + UUID().uuidString, persistence: OwnedTraktPersistence())
        try account.load()
        try account.set(.init(accessToken: "owned-access", refreshToken: "owned-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000))
        return account
    }
    static func transport(_ scenario: JSONValue) -> OwnedTraktTransport {
        OwnedTraktTransport(fallback: { request in
            let url = try XCTUnwrap(request.url), path = url.path + (url.query.map { "?" + $0 } ?? "")
            let name = try XCTUnwrap(scenario["paths"].objectValue.first { $0.value.string == path }?.key)
            let failed = scenario["failed"].array.contains(.string(name))
            return .init(status: failed ? 503 : 200, data: try JSONEncoder().encode(failed ? .null : scenario["input"][name]))
        })
    }
    static func hydrator(_ scenario: JSONValue) -> TraktHomeHydrator {
        .init(tmdb: { media, _ in
            let id = try XCTUnwrap(media.id.split(separator: ":").last.flatMap { Int($0) })
            if scenario["tmdbFailures"].array.contains(.integer(Int64(id))) { throw HarborError(code: "owned-metadata-error") }
            return scenario["tmdbRaw"][String(id)]
        }, cinemeta: { id, kind in
            let number = try XCTUnwrap(Int(id.dropFirst(2))).subtractingReportingOverflow(1_000_000).partialValue
            if scenario["cinemetaFailures"].array.contains(.integer(Int64(number))) { throw HarborError(code: "owned-metadata-error") }
            return Media.parse(scenario["cinemetaRaw"][id], kind: kind)
        })
    }
    static func project(_ media: Media) -> JSONValue {
        .object(["id": .string(media.id), "type": .string(media.type), "name": .string(media.name),
                 "poster": media.poster.map(JSONValue.string) ?? .null, "background": media.background.map(JSONValue.string) ?? .null,
                 "description": media.description.map(JSONValue.string) ?? .null, "releaseInfo": media.releaseInfo.map(JSONValue.string) ?? .null,
                 "imdbRating": media.imdbRating.map(JSONValue.string) ?? .null])
    }
    func testTenExecutedDesktopHomeBuildsMatchRowsArtFallbacksRawPagesAndAuthenticatedEndpoints() async throws {
        let reference = try Self.reference()
        XCTAssertEqual(reference["actual_original_typescript_executed"], .bool(true))
        XCTAssertEqual(reference["executed_module_hashes"].objectValue.count, 8)
        XCTAssertEqual(reference["languages"].array.count, 16)
        for language in reference["languages"].array {
            for (key, expected) in language["expected"].objectValue {
                XCTAssertEqual(DesktopInterfaceText.value(key, language: language["code"].string), expected.string)
            }
        }
        let scenarios = reference["cases"].array; XCTAssertEqual(scenarios.count, 10)
        for scenario in scenarios {
            let account = try Self.account(), transport = Self.transport(scenario)
            let model = TraktHomeModel(account: account, client: .init(transport: { try await transport.send($0) }), hydrator: Self.hydrator(scenario), active: { true })
            var config = configuration; config.tmdbKey = scenario["key"].string ?? ""
            await model.load(configuration: config, date: Date(timeIntervalSince1970: 1_793_230_800))
            let expected = scenario["expected"].array
            XCTAssertEqual(model.rows.map(\.id), expected.compactMap { $0["id"].string }, scenario["name"].string ?? "")
            XCTAssertEqual(model.rows.map(\.kind), expected.compactMap { $0["kind"].string })
            for (row, expected) in zip(model.rows, expected) {
                XCTAssertEqual(row.title, DesktopInterfaceText.value(expected["title"].string ?? ""))
                XCTAssertEqual(.array(row.metas.map(Self.project)), expected["metas"])
                XCTAssertGreaterThanOrEqual(row.metas.count, 4)
                let personal = try XCTUnwrap(row.personal); XCTAssertTrue(personal.available())
                for page in expected["pages"].array {
                    let actual = try await personal.page(try XCTUnwrap(page["page"].integer))
                    XCTAssertEqual(.array(actual.map(Self.project)), page["metas"], row.id)
                }
            }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 4)
            XCTAssertEqual(Set(requests.compactMap { request -> String? in
                guard let url = request.url else { return nil }; return url.path + (url.query.map { "?" + $0 } ?? "")
            }), Set(scenario["requests"].array.compactMap(\.string)))
            XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.host == "api.trakt.tv" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer owned-access" })
            await model.load(configuration: config)
            let cachedRequests = await transport.requests; XCTAssertEqual(cachedRequests.count, 4)
            XCTAssertFalse(model.loading)
        }
        XCTAssertEqual(TraktHomeEndpoint.utcDay(Date(timeIntervalSince1970: 1_793_230_800)), "2026-10-28")
        XCTAssertThrowsError(try TraktEndpoint.home(.upcoming("2026-10-28/../other")).request(token: "owned-access"))
        XCTAssertThrowsError(try TraktEndpoint.home(.recommendations(.movie)).request())
    }
    func testLateReplyCannotPublishAfterDisconnectProfileDepartureOrAReplacementAccount() async throws {
        let scenario = try XCTUnwrap(Self.reference()["cases"].array.first)
        let disconnected = try Self.account(), unused = Self.transport(scenario)
        try disconnected.set(nil)
        let disconnectedModel = TraktHomeModel(account: disconnected, client: .init(transport: { try await unused.send($0) }), hydrator: Self.hydrator(scenario), active: { true })
        await disconnectedModel.load(configuration: configuration)
        let unusedRequests = await unused.requests
        XCTAssertTrue(unusedRequests.isEmpty); XCTAssertTrue(disconnectedModel.rows.isEmpty)
        for replacement in [false, true] {
            let account = try Self.account(), transport = Self.transport(scenario)
            let gate = OwnedTraktHomeHeldReply()
            let model = TraktHomeModel(account: account, client: .init(transport: { request in await gate.wait(); return try await transport.send(request) }), hydrator: Self.hydrator(scenario), active: { true })
            let loading = Task { await model.load(configuration: configuration) }
            for _ in 0..<100 { if await gate.isHolding { break }; try await Task.sleep(for: .milliseconds(10)) }
            let holding = await gate.isHolding; XCTAssertTrue(holding)
            try account.set(replacement ? .init(accessToken: "owned-second", refreshToken: "owned-second-refresh", createdAt: 1_700_000_000, expiresIn: 7_776_000) : nil)
            await gate.release(); await loading.value
            XCTAssertTrue(model.rows.isEmpty); XCTAssertFalse(model.loading)
            let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
        }
        let account = try Self.account(), transport = Self.transport(scenario), activation = OwnedTraktHomeActivation()
        let model = TraktHomeModel(account: account, client: .init(transport: { try await transport.send($0) }), hydrator: Self.hydrator(scenario), active: { activation.current })
        await model.load(configuration: configuration)
        let oldPager = try XCTUnwrap(model.rows.first?.personal)
        activation.current = false
        XCTAssertTrue(model.rows.isEmpty); XCTAssertFalse(oldPager.available())
        do { _ = try await oldPager.page(2); XCTFail("A departed profile must not reopen its private list") } catch is CancellationError { }
        let count = await transport.requests.count; XCTAssertEqual(count, 4)
    }
    func testHydrationBoundsConcurrentRequestsAndPreservesInputOrderDespiteOutOfOrderReplies() async throws {
        let tracker = OwnedTraktHomeHydrationCounter()
        let items = (1...24).map { TraktLibraryItem(type: .movie, title: "Owned \($0)", year: 2024, ids: .init(.object(["tmdb": .integer(Int64($0))]))) }
        let hydrator = TraktHomeHydrator(tmdb: { media, _ in
            let id = try XCTUnwrap(Int(media.id.split(separator: ":").last ?? ""))
            await tracker.begin()
            try await Task.sleep(for: .milliseconds(id % 2 == 0 ? 5 : 25))
            await tracker.end()
            return .object(["poster_path": .string("/owned-\(id).jpg")])
        }, cinemeta: { _, _ in XCTFail("No IMDb fallback is needed"); return nil })
        let values = try await hydrator.hydrate(items, configuration: configuration)
        XCTAssertEqual(values.map(\.id), items.compactMap { $0.media?.id })
        let maximum = await tracker.maximum, current = await tracker.current
        XCTAssertEqual(maximum, 4); XCTAssertEqual(current, 0)
    }
    func testTraktRowsParticipateInExistingHomeLayoutWithoutExposingCredentialOrLosingOtherRows() async throws {
        let scenario = try XCTUnwrap(Self.reference()["cases"].array.first), account = try Self.account()
        let transport = Self.transport(scenario), model = TraktHomeModel(account: account, client: .init(transport: { try await transport.send($0) }), hydrator: Self.hydrator(scenario), active: { true })
        await model.load(configuration: configuration)
        let owner = "owned-trakt-home-layout-" + UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "page-layout-" + EBookShelf.hash(owner + "|home")) }
        let customization = PageCustomization(owner: owner, page: "home")
        let rows = model.rows.map(PageRail.discovery); XCTAssertEqual(rows.count, 4)
        customization.setEditingRails(rows)
        let first = try XCTUnwrap(rows.first), last = try XCTUnwrap(rows.last)
        customization.rename(first, to: "Owned Trakt picks"); customization.move(last, toward: first)
        customization.change { $0.heroSource = first.id; $0.hidden.insert(last.id); $0.numerals.insert(first.id) }
        XCTAssertEqual(customization.title(first, among: rows), "Owned Trakt picks")
        XCTAssertFalse(customization.ordered(rows).contains { $0.id == last.id })
        XCTAssertEqual(customization.layout.heroSource, first.id)
        let mapping = DesktopPageRowMap(page: "home", rails: rows)
        let raw = try DesktopPageLayout(page: "home", raw: .object([:])).applying(customization.layout, mapping: mapping).raw
        XCTAssertEqual(raw["heroSource"].string, "trakt-watchlist")
        XCTAssertTrue(raw["hidden"].array.contains(.string("trakt-recs-shows")))
        XCTAssertEqual(raw["renamed"]["trakt-watchlist"].string, "Owned Trakt picks")
        let encoded = String(decoding: try JSONEncoder().encode(raw), as: UTF8.self)
        XCTAssertFalse(encoded.contains("owned-access")); XCTAssertFalse(encoded.contains("owned-tmdb-key"))
        let restored = PageCustomization(owner: owner, page: "home")
        XCTAssertEqual(restored.layout, customization.layout)
        try account.set(nil)
        XCTAssertTrue(model.rows.isEmpty)
    }
}
@MainActor final class OwnedTraktHomeActivation { var current = true }
private actor OwnedTraktHomeHydrationCounter {
    private(set) var current = 0, maximum = 0
    func begin() { current += 1; maximum = max(maximum, current) }
    func end() { current -= 1 }
}
private actor OwnedTraktHomeHeldReply {
    private var continuation: CheckedContinuation<Void, Never>?
    private var first = true
    var isHolding: Bool { continuation != nil }
    func wait() async {
        guard first else { return }; first = false
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
