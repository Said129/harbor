import XCTest
@testable import Harbor

private actor OwnedRepositoryNetwork: HarborNativeNetworkCalling {
    let responses: [String: HarborNetworkResponse]
    let waitingURL: String?
    private var requests: [HarborNetworkRequest] = []
    init(_ responses: [String: HarborNetworkResponse], waitingURL: String? = nil) {
        self.responses = responses; self.waitingURL = waitingURL
    }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        if request.url == waitingURL { try await Task.sleep(for: .seconds(30)) }
        guard let response = responses[request.url] else { throw HarborError(code: "owned-unavailable") }
        return response
    }
    func captured() -> [HarborNetworkRequest] { requests }
}

final class HarborPluginRepositoryClientTests: XCTestCase {
    private func response(_ url: String, _ text: String, headers: [String: String] = [:]) -> HarborNetworkResponse {
        .init(status: 200, ok: true, headers: headers, bodyBase64: Data(text.utf8).base64EncodedString(), url: url)
    }
    private func entry(_ codeURL: String) throws -> HarborStreamPluginEntry {
        let manifest: JSONValue = .object(["plugins": .array([.object(["id": .string("owned"), "name": .string("Owned"), "entry": .string(codeURL)])])])
        return try XCTUnwrap(HarborPluginManifest.parse(manifest, url: "https://example.org/manifest.json").entries.first)
    }

    func testGitHubFallbackAndDuplicateDetectionPrecedeAnyInstallation() async throws {
        let main = "https://raw.githubusercontent.com/owned/catalog/main/manifest.json"
        let master = "https://raw.githubusercontent.com/owned/catalog/master/manifest.json"
        let network = OwnedRepositoryNetwork([
            main: response(main, #"{"plugins":[]}"#),
            master: response(master, #"{"name":"Owned catalog","plugins":[{"id":"one","name":"One","entry":"./one.js"}]}"#)
        ])
        let client = HarborPluginRepositoryClient(network: network, blockedHosts: ["tracker.invalid"])
        do { _ = try await client.add("https://github.com/owned/catalog", existingURLs: [master]); XCTFail("Duplicate accepted") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "already-added") }
        let empty = await network.captured(); XCTAssertTrue(empty.isEmpty)
        let record = try await client.add("https://github.com/owned/catalog", existingURLs: [])
        XCTAssertEqual(record.url, master); XCTAssertEqual(record.manifest.name, "Owned catalog")
        XCTAssertEqual(record.manifest.entries.first?.entry, "https://raw.githubusercontent.com/owned/catalog/master/one.js")
        let requests = await network.captured(); XCTAssertEqual(requests.map(\.url), [main, master])
        XCTAssertTrue(requests.allSatisfy { $0.blockedHosts == ["tracker.invalid"] && $0.timeoutMs == 20_000 })
    }

    func testChildListsKeepOrderDeduplicateAndRetainUsableEntriesAfterAFailedList() async throws {
        let url = "https://example.org/manifest.json", first = "https://example.org/one.json", last = "https://example.org/two.json"
        let network = OwnedRepositoryNetwork([
            url: response(url, #"{"pluginLists":["one.json","unavailable.json","two.json"]}"#),
            first: response(first, #"[{"internalName":"same","name":"First","url":"first.cs3","apiVersion":1}]"#),
            last: response(last, #"[{"internalName":"same","name":"Duplicate","url":"duplicate.cs3","apiVersion":1},{"internalName":"other","name":"Other","url":"other.cs3","apiVersion":1}]"#)
        ])
        let client = HarborPluginRepositoryClient(network: network)
        let manifest = try await client.fetchManifest(url)
        XCTAssertEqual(manifest.format, .androidExtension); XCTAssertEqual(manifest.entries.map(\.id), ["same", "other"])
        XCTAssertEqual(manifest.entries.first?.name, "First")
        do { _ = try await client.fetchSource(XCTUnwrap(manifest.entries.first)); XCTFail("Android downloaded for execution") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "android-extensions") }
        let requests = await network.captured(); XCTAssertEqual(requests.map(\.url), [url, first, "https://example.org/unavailable.json", last])
    }

    func testSourceLengthUsesDesktopUTF16AndIconsPreserveOriginalBinaryBytes() async throws {
        let url = "https://example.org/source.js", large = "https://example.org/large.js", icon = "https://example.org/cover.png"
        let bytes = Data([137,80,78,71,0,255,1])
        let network = OwnedRepositoryNetwork([
            url: response(url, "\u{feff}var owned = true;", headers: ["etag": "owned-tag"]),
            large: response(large, String(repeating: "😀", count: 1024 * 1024 + 1)),
            icon: .init(status: 200, ok: true, headers: ["content-type":"image/png; charset=binary"], bodyBase64: bytes.base64EncodedString(), url: icon)
        ])
        let client = HarborPluginRepositoryClient(network: network)
        let source = try await client.fetchSource(entry(url))
        XCTAssertEqual(source.code, "var owned = true;"); XCTAssertEqual(source.etag, "owned-tag")
        do { _ = try await client.fetchSource(entry(large)); XCTFail("Oversized UTF-16 source accepted") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "too-large") }
        let image = try await client.fetchIcon(icon); XCTAssertEqual(image, "data:image/png;base64," + bytes.base64EncodedString())
        let missing = try await client.fetchIcon("https://example.org/missing.png"); XCTAssertNil(missing)
        let requests = await network.captured()
        XCTAssertEqual(requests[2].timeoutMs, 8_000); XCTAssertEqual(requests[2].maxResponseBytes, 512 * 1024); XCTAssertTrue(requests[2].strictLimit)
    }

    func testCancellationDoesNotBecomeAnErrorOrStartAnotherGitHubCandidate() async throws {
        let main = "https://raw.githubusercontent.com/owned/catalog/main/manifest.json"
        let network = OwnedRepositoryNetwork([:], waitingURL: main)
        let client = HarborPluginRepositoryClient(network: network)
        let task = Task { try await client.add("https://github.com/owned/catalog", existingURLs: []) }
        let deadline = Date().addingTimeInterval(2)
        while await network.captured().isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let started = await network.captured(); XCTAssertEqual(started.count, 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request returned a repository") }
        catch { XCTAssertTrue(error is CancellationError) }
        let requests = await network.captured(); XCTAssertEqual(requests.map(\.url), [main])
    }
}
