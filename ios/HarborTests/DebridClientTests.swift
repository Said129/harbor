import XCTest
@testable import Harbor

struct ScriptedResponse: Decodable { let status: Int; let body: JSONValue? }
struct DebridFixture: Decodable {
    struct Request: Decodable, Equatable { let method: String; let url: String; let body: String? }
    let reference: String
    let program_sha256: String
    let key: String
    let hash: String
    let account: DebridOutcome<DebridAccount>
    let playable: DebridOutcome<DebridLink>
    let unauthorized_code: String
    let not_cached_code: String
    let scripts: [String: [String: [ScriptedResponse]]]
    let requests: [Request]
}

actor DebridFixtureNetwork: HarborNativeNetworkCalling {
    struct Observation: Sendable { let method: String; let url: String; let body: String?; let authorization: String?; let publicOnly: Bool }
    private var queue: [String: [ScriptedResponse]]
    private(set) var observations: [Observation] = []
    init(script: [String: [ScriptedResponse]]) { queue = script }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        let body = request.bodyBase64.flatMap { Data(base64Encoded: $0) }.map { String(decoding: $0, as: UTF8.self) }
        observations.append(.init(method: request.method, url: request.url, body: body, authorization: request.headers.first { $0.key.lowercased() == "authorization" }?.value,
                                  publicOnly: request.publicNetworkOnly && !request.allowLocalNetwork))
        let key = request.method + " " + request.url
        guard var pending = queue[key], !pending.isEmpty else { return .init(status: 404, ok: false, headers: [:], bodyBase64: "", url: request.url) }
        let next = pending.removeFirst(); queue[key] = pending
        let text = try next.body.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) } ?? ""
        return .init(status: next.status, ok: (200..<300).contains(next.status), headers: ["content-length": String(text.utf8.count)],
                     bodyBase64: Data(text.utf8).base64EncodedString(), url: request.url)
    }
}

@MainActor final class DebridScope {
    var value = PluginExecutionScope(owner: "owned-debrid-" + UUID().uuidString, activation: UUID())
}

@MainActor final class DebridClientTests: XCTestCase {
    private func fixture() throws -> DebridFixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "debrid-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(DebridFixture.self, from: Data(contentsOf: url))
    }
    private func client(_ scope: DebridScope, _ network: DebridFixtureNetwork) -> DebridClient {
        DebridClient(scope: scope.value, currentScope: { scope.value }, transport: DebridTransport(network: network))
    }

    func testPinnedOriginalRealDebridFlowSelectsTheEpisodeFileAndReturnsADirectLinkWithoutLeakingTheKey() async throws {
        let fixture = try fixture(), scope = DebridScope(), network = DebridFixtureNetwork(script: try XCTUnwrap(fixture.scripts["flow"]))
        XCTAssertEqual(fixture.reference, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(try DebridAsset.read().program.sha256, fixture.program_sha256)
        let client = client(scope, network); defer { try? client.saveKey("", for: .rd); client.dispose() }
        try client.saveKey(fixture.key, for: .rd)
        XCTAssertEqual(client.providers, [.rd]); XCTAssertTrue(client.hasKey(.rd)); XCTAssertFalse(client.hasKey(.tb))
        let account = try await client.account(.rd)
        XCTAssertEqual(account.value, fixture.account.value)
        let link = try await client.playableURL(.rd, magnet: fixture.hash, fileIdx: nil, season: 1, episode: 1)
        XCTAssertEqual(link.value, fixture.playable.value)
        XCTAssertEqual(link.value?.url, "https://cdn.owned.example/Owned.Show.S01E01.mkv")
        let seen = await network.observations
        XCTAssertEqual(seen.map { DebridFixture.Request(method: $0.method, url: $0.url, body: $0.body) }, Array(fixture.requests.prefix(seen.count)))
        XCTAssertEqual(seen.count, 6, "Account, add, info, select, info and unrestrict")
        XCTAssertTrue(seen.allSatisfy { $0.authorization == "Bearer " + fixture.key && $0.publicOnly && URL(string: $0.url)?.host == "api.real-debrid.com" })
        XCTAssertEqual(seen.first { $0.url.hasSuffix("/selectFiles/RD1") }?.body, "files=1", "Only the matched episode file is selected")
        XCTAssertFalse(seen.contains { $0.url.contains(fixture.key) || ($0.body ?? "").contains(fixture.key) }, "The key travels only in the bearer header")
    }

    func testOriginalFailureCodesSurviveWithoutTheProvidersRawBody() async throws {
        let fixture = try fixture(), scope = DebridScope()
        let denied = client(scope, DebridFixtureNetwork(script: try XCTUnwrap(fixture.scripts["forbidden"])))
        defer { try? denied.saveKey("", for: .rd); denied.dispose() }
        try denied.saveKey(fixture.key, for: .rd)
        let rejected = try await denied.account(.rd)
        XCTAssertEqual(rejected.failureCode, fixture.unauthorized_code); XCTAssertNil(rejected.value)
        let uncachedNetwork = DebridFixtureNetwork(script: try XCTUnwrap(fixture.scripts["uncached"]))
        let second = client(scope, uncachedNetwork); defer { second.dispose() }
        let uncached = try await second.playableURL(.rd, magnet: fixture.hash, fileIdx: nil)
        XCTAssertEqual(uncached.failureCode, fixture.not_cached_code)
        let calls = await uncachedNetwork.observations.map { $0.method + " " + (URL(string: $0.url)?.path ?? "") }
        XCTAssertEqual(calls.last, "DELETE /rest/1.0/torrents/delete/RD2", "An uncached torrent is removed again, as in Desktop")
    }

    func testKeysAreIsolatedPerProfileValidatedAndRemovable() async throws {
        let first = DebridScope(), second = DebridScope()
        let one = client(first, DebridFixtureNetwork(script: [:])), two = client(second, DebridFixtureNetwork(script: [:]))
        defer { try? one.saveKey("", for: .tb); one.dispose(); two.dispose() }
        try one.saveKey("  owned-torbox-key  ", for: .tb)
        XCTAssertTrue(one.hasKey(.tb)); XCTAssertFalse(two.hasKey(.tb), "Another profile owner never sees the key")
        let reopened = client(first, DebridFixtureNetwork(script: [:])); XCTAssertTrue(reopened.hasKey(.tb)); reopened.dispose()
        for bad in ["owned key", "owned\nkey", String(repeating: "k", count: 201), "owned\u{0}key"] {
            XCTAssertThrowsError(try one.saveKey(bad, for: .ad), "Rejected: " + bad.prefix(12))
        }
        do { _ = try await two.account(.tb); XCTFail("A missing key must not reach the network") }
        catch let error as HarborError { XCTAssertEqual(error.code, "debrid-key-missing") }
        try one.saveKey("", for: .tb); XCTAssertFalse(one.hasKey(.tb))
        // Switching profile retires the client before it can use or reveal anything.
        first.value = PluginExecutionScope(owner: first.value.owner + "-retired", activation: UUID())
        do { _ = try await one.account(.tb); XCTFail("A retired profile cannot call") } catch is CancellationError { }
        XCTAssertThrowsError(try one.saveKey("owned-after-retirement", for: .tb), "A retired profile cannot store a key") { XCTAssertTrue($0 is CancellationError) }
    }

    func testTransportAdmitsOnlyTheFiveProviderApiHostsWithoutCredentialsPortsOrOtherMethods() async throws {
        let network = DebridFixtureNetwork(script: [:]), transport = DebridTransport(network: network)
        func attempt(_ url: String, method: String = "GET") async -> String? {
            do { _ = try await transport.perform(.http, payload: .object(["url": .string(url), "opts": .object(["method": .string(method)])])); return nil }
            catch let error as HarborError { return error.code } catch { return "other" }
        }
        for provider in DebridProvider.allCases {
            let allowed = await attempt("https://" + provider.host + "/v1/ping")
            XCTAssertNotEqual(allowed, "debrid-host", provider.host + " must reach the network layer")
        }
        for url in ["https://evil.example/x", "https://api.real-debrid.com.evil.example/x", "http://api.real-debrid.com/x", "https://api.real-debrid.com:8443/x",
                    "https://user:pass@api.real-debrid.com/x", "https://127.0.0.1/x", "https://real-debrid.com/x", ""] {
            let code = await attempt(url); XCTAssertEqual(code, "debrid-host", url)
        }
        for method in ["PUT", "PATCH", "OPTIONS", "HEAD"] {
            let code = await attempt("https://api.real-debrid.com/x", method: method); XCTAssertEqual(code, "debrid-host", method)
        }
        let observed = await network.observations.map(\.url)
        XCTAssertEqual(Set(observed.compactMap { URL(string: $0)?.host }), Set(DebridProvider.allCases.map(\.host)), "Only provider hosts were ever contacted")
    }

    func testProviderCatalogMatchesDesktopOrderLabelsAndKeyPages() {
        XCTAssertEqual(DebridProvider.allCases.map(\.rawValue), ["rd", "tb", "ad", "pm", "dl"])
        XCTAssertEqual(DebridProvider.allCases.map(\.name), ["Real-Debrid", "TorBox", "AllDebrid", "Premiumize", "Debrid-Link"])
        XCTAssertEqual(DebridProvider.rd.placeholder, "API token"); XCTAssertEqual(DebridProvider.tb.placeholder, "API key")
        XCTAssertEqual(DebridProvider.allCases.map(\.keyPage.url), ["https://real-debrid.com/apitoken", "https://torbox.app/settings", "https://alldebrid.com/apikeys/",
                                                                      "https://www.premiumize.me/account", "https://debrid-link.com/webapp/apikey"])
        for language in ["es", "ar", "fr", "ja"] {
            for key in ["Debrid services", "Real-Debrid API token", "Get yours at", "Active", "Expired"] {
                XCTAssertNotEqual(DesktopInterfaceText.value(key, language: language), key, key + " is translated in " + language)
            }
        }
    }

}
