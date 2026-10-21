import XCTest
@testable import Harbor

private actor ReadingBulkNetwork: HarborNativeNetworkCalling {
    private var version = "1"
    private var failures: Set<String> = ["bad"]
    private var holding: String?
    private var held: CheckedContinuation<Void, Never>?
    func configure(version: String = "1", failures: Set<String> = ["bad"], hold: String? = nil) {
        self.version = version; self.failures = failures; holding = hold
    }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        let url = try XCTUnwrap(URL(string: request.url))
        let component = url.lastPathComponent
        let bytes: Data
        if component == "repo.json" {
            let entries = ["bad", "a", "b"].map { ["id": $0, "name": "Owned " + $0, "entry": $0 + ".js", "version": version] }
            let manifest: [String: Any] = ["name": "Owned bulk", "type": "ebook", "plugins": entries]
            bytes = try JSONSerialization.data(withJSONObject: manifest)
        } else {
            let id = url.deletingPathExtension().lastPathComponent
            if component == holding { await withCheckedContinuation { held = $0 } }
            try Task.checkCancellation()
            if failures.contains(id) { throw HarborPluginRepositoryError("no-answer") }
            bytes = Data(("var plugin={id:'" + id + "',name:'Owned " + id + "',popular:function(){return [];}};").utf8)
        }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: bytes.base64EncodedString(), url: request.url)
    }
    func waitUntilHeld() async throws {
        for _ in 0..<900 { if held != nil { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw HarborPluginRepositoryError("owned-bulk-timeout")
    }
    func release() { holding = nil; let continuation = held; held = nil; continuation?.resume() }
}

@MainActor final class HarborReadingBulkTests: XCTestCase {
    private func prepare() async throws -> (HarborReadingPluginManager, ReadingBulkNetwork, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("reading-bulk-" + UUID().uuidString + ".json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let scope = PluginExecutionScope(owner: "owned-reading-bulk", activation: UUID()), network = ReadingBulkNetwork()
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: try HarborReadingPluginStore(file: file), network: network)
        try await manager.load(); try await manager.addRepository("https://example.org/bulk/repo.json", kind: .ebook)
        return (manager, network, file)
    }
    func testBulkContinuesAfterOneFailureReportsRealProgressUpdatesAndRemovesOnlyInstalledEntries() async throws {
        let (manager, network, file) = try await prepare()
        defer { manager.dispose(); Task { await network.release() } }
        let repo = try XCTUnwrap(manager.document.repositories.first)
        await network.configure(hold: "b.js")
        let installing = Task { try await manager.installAll(repo) }
        try await network.waitUntilHeld()
        XCTAssertTrue(manager.busy); XCTAssertEqual(manager.bulkProgress?.total, 3)
        XCTAssertEqual(manager.bulkProgress?.completed, 2); XCTAssertEqual(manager.bulkProgress?.installed, 1); XCTAssertEqual(manager.bulkProgress?.failed, 1)
        XCTAssertNotNil(manager.entryFailures[repo.id + "|bad"])
        let first = try XCTUnwrap(manager.installed(.ebook).first)
        do { try await manager.setEnabled(first, false); XCTFail("The bulk mutation must own its transaction") }
        catch let error as HarborPluginRepositoryError { XCTAssertEqual(error.code, "plugin-busy") }
        await network.release(); try await installing.value
        XCTAssertFalse(manager.busy); XCTAssertNil(manager.bulkProgress)
        XCTAssertEqual(Set(manager.installed(.ebook).map { $0.entry.id }), ["a", "b"])
        let disk = try await HarborReadingPluginStore(file: file).load(); XCTAssertEqual(disk.plugins.count, 2)
        await network.configure(version: "2")
        try await manager.refresh(repo)
        let refreshed = try XCTUnwrap(manager.document.repositories.first)
        try await manager.installAll(refreshed, updatesOnly: true)
        XCTAssertEqual(manager.document.plugins.count, 2)
        XCTAssertTrue(manager.document.plugins.allSatisfy { $0.entry.version == "2" })
        try await manager.removeInstalled(in: refreshed)
        XCTAssertTrue(manager.document.plugins.isEmpty); XCTAssertEqual(manager.document.repositories, [refreshed])
    }
    func testAllFailedBulkShowsFailureAndCanRetryWithoutDuplicatingSources() async throws {
        let (manager, network, _) = try await prepare()
        defer { manager.dispose() }
        let repo = try XCTUnwrap(manager.document.repositories.first)
        await network.configure(failures: ["bad", "a", "b"])
        do { try await manager.installAll(repo); XCTFail("A completely unsuccessful batch must report failure") }
        catch let error as HarborPluginRepositoryError { XCTAssertEqual(error.code, "no-answer") }
        XCTAssertFalse(manager.busy); XCTAssertNil(manager.bulkProgress); XCTAssertTrue(manager.document.plugins.isEmpty)
        XCTAssertEqual(manager.entryFailures.count, 3)
        await network.configure(failures: [])
        try await manager.installAll(repo)
        XCTAssertEqual(manager.document.plugins.count, 3); XCTAssertTrue(manager.entryFailures.isEmpty)
        try await manager.installAll(repo)
        XCTAssertEqual(manager.document.plugins.count, 3)
    }
    func testCancellingBulkRejectsTheHeldDownloadAndLeavesThePreviousCatalog() async throws {
        let (manager, network, file) = try await prepare()
        defer { manager.dispose(); Task { await network.release() } }
        await network.configure(failures: [], hold: "bad.js")
        let before = manager.document, repo = try XCTUnwrap(before.repositories.first)
        let installing = Task { try await manager.installAll(repo) }
        try await network.waitUntilHeld(); manager.cancelBulk(); await network.release()
        do { try await installing.value; XCTFail("Cancelled batch must not finish") } catch is CancellationError {}
        XCTAssertFalse(manager.busy); XCTAssertNil(manager.bulkProgress); XCTAssertEqual(manager.document, before)
        let disk = try await HarborReadingPluginStore(file: file).load(); XCTAssertEqual(disk, before)
    }
}
