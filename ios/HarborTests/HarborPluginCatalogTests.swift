import XCTest
@testable import Harbor

final class HarborPluginCatalogTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "plugin-manifest-reference", withExtension: "json", subdirectory: "Fixtures"))
        let result = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(result["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        return result
    }

    func testRepositoryURLsMatchExecutedDesktopReference() throws {
        let cases = try fixture()["urls"].array
        XCTAssertEqual(cases.count, 14)
        for row in cases {
            let input = try XCTUnwrap(row["input"].string)
            if let error = row["error"].string {
                XCTAssertThrowsError(try HarborPluginManifest.normalizeURL(input)) { XCTAssertEqual(($0 as? HarborPluginRepositoryError)?.code, error) }
            } else {
                let normalized = try HarborPluginManifest.normalizeURL(input)
                XCTAssertEqual(normalized, row["expected"]["url"].string)
                XCTAssertEqual(HarborPluginManifest.candidates(normalized), row["expected"]["candidates"].array.compactMap(\.string))
                XCTAssertEqual(HarborPluginManifest.displayName(normalized), row["expected"]["name"].string)
            }
        }
        XCTAssertEqual(HarborPluginManifest.splitLinks("https://example.org,https://two.example.org\nhttps://example.org"), ["https://example.org", "https://two.example.org"])
    }

    func testManifestFormatsAndErrorRoutingMatchExecutedDesktopReference() throws {
        let cases = try fixture()["manifests"].array
        XCTAssertEqual(cases.count, 13)
        for row in cases {
            let url = try XCTUnwrap(row["url"].string)
            if let error = row["error"].string {
                XCTAssertThrowsError(try HarborPluginManifest.parse(row["input"], url: url)) { XCTAssertEqual(($0 as? HarborPluginRepositoryError)?.code, error) }
            } else {
                let parsed = try HarborPluginManifest.parse(row["input"], url: url)
                XCTAssertEqual(try JSONValue.encoded(parsed), row["expected"])
            }
        }
    }

    func testPluginIdentityPreservesDesktopUTF16Hash() throws {
        for row in try fixture()["ids"].array {
            XCTAssertEqual(HarborPluginManifest.pluginID(repository: try XCTUnwrap(row["repository"].string), entry: try XCTUnwrap(row["entry"].string)), row["expected"].string)
        }
    }

    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("owned-plugin-catalog-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("catalog.json")
    }

    private func repository(version: String = "1", enabled: Bool = true) throws -> HarborStreamRepositoryRecord {
        let data = Data(#"{"name":"Owned catalog","type":"stream","plugins":[{"id":"owned.source","name":"Owned source","version":"1","entry":"owned.js","settings":true}]}"#.utf8)
        let url = "https://example.invalid/manifest.json"
        var manifest = try HarborPluginManifest.parse(JSONDecoder().decode(JSONValue.self, from: data), url: url)
        manifest.entries[0].version = version; manifest.entries[0].enabled = enabled
        return .init(url: url, manifest: manifest, checkedAt: 100)
    }

    func testFailedWritePreservesCommittedCatalogOnDiskAndInMemory() async throws {
        let file = try location()
        let store = try HarborPluginCatalogStore(namespace: "owned", file: file)
        try await store.load(); try await store.saveRepository(repository(), revision: 0)
        let original = try await store.snapshot()
        let originalBytes = try Data(contentsOf: file)
        let failing = try HarborPluginCatalogStore(namespace: "owned", file: file, write: { _, _ in throw HarborPluginRepositoryError("owned-write-failure") })
        try await failing.load()
        do { try await failing.saveRepository(repository(version: "2"), revision: 1); XCTFail("A failed write must not publish") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "owned-write-failure") }
        let retained = try await failing.snapshot()
        XCTAssertEqual(retained, original); XCTAssertEqual(try Data(contentsOf: file), originalBytes)
    }

    func testInstallationRejectsChecksumWrongMethodAndAndroidBeforeChangingState() async throws {
        let store = try HarborPluginCatalogStore(namespace: "owned", file: location())
        try await store.load()
        let repo = try repository(); try await store.saveRepository(repo, revision: 0)
        var entry = try XCTUnwrap(repo.manifest.entries.first)
        entry.sha256 = String(repeating: "0", count: 64)
        do { try await store.install(repository: repo.url, entry: entry, code: "owned", etag: nil, methods: ["streams"], time: 200, revision: 1); XCTFail("Checksum mismatch accepted") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "checksum") }
        entry.sha256 = nil
        do { try await store.install(repository: repo.url, entry: entry, code: "owned", etag: nil, methods: ["search"], time: 200, revision: 1); XCTFail("Non-stream plugin accepted") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "not-stream-plugin") }
        entry.format = .androidExtension
        do { try await store.install(repository: repo.url, entry: entry, code: "owned", etag: nil, methods: ["streams"], time: 200, revision: 1); XCTFail("Android bytecode accepted") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "android-extensions") }
        let result = try await store.snapshot(); XCTAssertEqual(result.revision, 1); XCTAssertTrue(result.plugins.isEmpty)
    }

    func testUpdateRollbackAndRefreshKeepInstalledCodeAndUserChoice() async throws {
        let store = try HarborPluginCatalogStore(namespace: "owned", file: location())
        try await store.load()
        let repo = try repository(); let entry = try XCTUnwrap(repo.manifest.entries.first)
        try await store.saveRepository(repo, revision: 0)
        try await store.install(repository: repo.url, entry: entry, code: "owned-v1", etag: "etag-1", methods: ["streams"], time: 200, revision: 1)
        let first = try await store.snapshot(); let id = try XCTUnwrap(first.plugins.first?.id)
        try await store.setEnabled(id, enabled: false, revision: 2)
        let update = try repository(version: "2", enabled: false)
        try await store.saveRepository(update, revision: 3)
        let listed = try await store.snapshot()
        XCTAssertEqual(listed.plugins.first?.code, "owned-v1"); XCTAssertEqual(listed.plugins.first?.updateVersion, "2")
        XCTAssertEqual(listed.plugins.first?.repoDisabled, true)
        try await store.install(repository: repo.url, entry: update.manifest.entries[0], code: "owned-v2", etag: "etag-2", methods: ["streams"], time: 300, revision: 4)
        let installed = try await store.snapshot()
        XCTAssertEqual(installed.plugins.first?.enabled, false); XCTAssertEqual(installed.plugins.first?.previous?.code, "owned-v1")
        try await store.revert(id, time: 400, revision: 5)
        try await store.recordRepositoryFailure(repo.url, code: "no-answer", time: 500, revision: 6)
        let reverted = try await store.snapshot()
        XCTAssertEqual(reverted.plugins.first?.code, "owned-v1"); XCTAssertEqual(reverted.plugins.first?.entry.version, "1")
        XCTAssertEqual(reverted.plugins.first?.etag, "etag-1"); XCTAssertNil(reverted.plugins.first?.previous)
        XCTAssertEqual(reverted.plugins.first?.installedAt, 200); XCTAssertEqual(reverted.plugins.first?.enabled, false)
        XCTAssertEqual(reverted.repositories.first?.manifest.entries.first?.version, "2")
        XCTAssertEqual(reverted.repositories.first?.error, "no-answer")
    }

    func testStaleResultAndWrongNamespaceCannotReplaceCatalog() async throws {
        let file = try location()
        let store = try HarborPluginCatalogStore(namespace: "owned", file: file)
        try await store.load(); try await store.saveRepository(repository(), revision: 0)
        do { try await store.saveRepository(repository(version: "2"), revision: 0); XCTFail("Stale network result accepted") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "plugin-store-changed") }
        let other = try HarborPluginCatalogStore(namespace: "other-owner", file: file)
        do { try await other.load(); XCTFail("Another namespace read the catalog") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "plugin-store-invalid") }
        let result = try await store.snapshot(); XCTAssertEqual(result.revision, 1)
        try await store.removeRepository("https://example.invalid/manifest.json", revision: 1)
        let empty = try await store.snapshot(); XCTAssertTrue(empty.repositories.isEmpty); XCTAssertTrue(empty.plugins.isEmpty)
    }

    func testCorruptReadNeverInitializesAnEmptyWritableCatalog() async throws {
        let file = try location(); let corrupt = Data("owned-corrupt-document".utf8)
        try corrupt.write(to: file)
        let store = try HarborPluginCatalogStore(namespace: "owned", file: file)
        do { try await store.load(); XCTFail("Corruption became an empty catalog") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "plugin-store-read") }
        do { try await store.saveRepository(repository(), revision: 0); XCTFail("Unavailable catalog accepted a write") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "plugin-store-unavailable") }
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
}
