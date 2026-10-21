import XCTest
@testable import Harbor

private actor ActivitySecrets: HarborPluginSecrets {
    private var values: [String: [String: String]] = [:]
    func stage(plugin: String, values: [String: String]) -> String { let revision = UUID().uuidString; self.values[revision] = values; return revision }
    func read(plugin: String, revision: String) throws -> [String: String] {
        guard let value = values[revision] else { throw HarborPluginRepositoryError("plugin-secrets-missing") }; return value
    }
    func remove(plugin: String, revision: String) { values[revision] = nil }
}
private actor ActivityNetwork: HarborNativeNetworkCalling {
    private var held: CheckedContinuation<Void, Never>?
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        await withCheckedContinuation { held = $0 }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data("owned".utf8).base64EncodedString(), url: request.url)
    }
    func waitUntilHeld() async throws {
        // Wait for the real bridge request, including the unchanged host/worker startup
        // allowance. The cancellation under test begins only after that request is held.
        for _ in 0..<900 { if held != nil { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw HarborPluginRepositoryError("owned-activity-timeout")
    }
    func release() { held?.resume(); held = nil }
}
@MainActor private final class ActivityOptions { var value = HarborPluginStreamOptions() }

@MainActor final class HarborPluginActivityTests: XCTestCase {
    private func prepared(source: String, paused: Bool = false) async throws
        -> (HarborPluginActivityModel, ActivityNetwork, ActivityOptions, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("owned-activity-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("catalog.json"), scope = PluginExecutionScope(owner: "owned-activity", activation: UUID())
        let store = try HarborPluginCatalogStore(namespace: scope.owner, file: file)
        try await store.load()
        let url = "https://example.org/activity/manifest.json"
        let manifest = try HarborPluginManifest.parse(.object(["plugins": .array([.object([
            "id": .string("owned.activity"), "name": .string("Owned activity"), "entry": .string("activity.js")])])]), url: url)
        try await store.saveRepository(.init(url: url, manifest: manifest, checkedAt: 1), revision: 0)
        let before = try await store.snapshot()
        try await store.install(repository: url, entry: XCTUnwrap(manifest.entries.first), code: source, etag: nil, methods: ["streams"], time: 1, revision: before.revision)
        if paused {
            // Seed an already-paused installation; the existing pool failure-threshold contract is retained.
            for _ in 0..<3 {
                let current = try await store.snapshot()
                try await store.recordRuntimeOutcome(XCTUnwrap(current.plugins.first?.id), expected: XCTUnwrap(current.plugins.first), succeeded: false, revision: current.revision)
            }
        }
        let network = ActivityNetwork(), options = ActivityOptions()
        let manager = HarborStreamPluginManager(namespace: scope.owner, scope: scope, currentScope: { scope }, store: store,
            client: .init(network: network), secrets: ActivitySecrets())
        try await manager.load()
        let runtime = HarborStreamPluginPool(manager: manager, currentScope: { scope }, gate: HarborPluginCallGate())
        manager.invalidateRuntime = { [weak runtime] id in runtime?.invalidate(id) }
        let model = HarborPluginActivityModel(id: try XCTUnwrap(manager.document.plugins.first?.id), manager: manager, runtime: runtime, options: { options.value })
        return (model, network, options, file)
    }

    func testRealCheckUsesDesktopSampleFreshConfigurationAndLastTitleWithVisibleActivity() async throws {
        let source = #"var plugin={id:'owned.activity',name:'Owned',streams:function(r){if(r.type!=='movie'||r.id!=='tt0137523'||JSON.stringify(r.ids)!=='[\"tt0137523\"]'||r.imdbId!=='tt0137523'||r.tmdb.id!==550||r.tmdb.kind!=='movie'||r.year!==1999||r.season!==null||r.episode!==null||r.absoluteEpisode!==null||!r.settings.token)throw new Error('contract');console.log('checked '+r.title);return Array(r.settings.token==='second'?2:1).fill({url:'https://files.example.org/owned.m3u8'});}};"#
        let (model, _, _, _) = try await prepared(source: source)
        defer { model.runtime.dispose(); model.manager.dispose() }
        try await model.manager.saveSettings(model.id, values: ["token": .string("first")], passwordKeys: ["token"])
        await model.check()
        XCTAssertEqual(model.result?.count, 1); XCTAssertFalse(model.checking); XCTAssertNil(model.error)
        XCTAssertEqual(model.health?.title, "Fight Club"); XCTAssertEqual(model.result?.requests, 0)
        XCTAssertTrue(model.logs.contains { $0.text == "log: checked Fight Club" }, model.logs.map(\.text).joined(separator: "\n"))
        model.runtime.recordSkip(model.id, title: "Owned last title", reason: "owned")
        try await model.manager.saveSettings(model.id, values: ["token": .string("second")], passwordKeys: ["token"])
        await model.check()
        XCTAssertEqual(model.result?.count, 2); XCTAssertEqual(model.health?.title, "Owned last title")
        XCTAssertTrue(model.logs.contains { $0.text == "log: checked Owned last title" }, model.logs.map(\.text).joined(separator: "\n"))
    }

    func testExplicitActivityCheckRecoversAnAlreadyPausedInstallationAndPersistsIt() async throws {
        let (model, _, _, file) = try await prepared(source: #"var plugin={id:'owned.activity',name:'Owned',streams:function(){return {streams:[{url:'https://files.example.org/owned.m3u8'}]};}};"#, paused: true)
        defer { model.runtime.dispose(); model.manager.dispose() }
        XCTAssertTrue(model.canCheck); XCTAssertEqual(model.plugin?.autoPaused, true)
        await model.check()
        XCTAssertEqual(model.result?.count, 1); XCTAssertNil(model.error)
        XCTAssertEqual(model.plugin?.autoPaused, false); XCTAssertEqual(model.plugin?.failures, 0)
        let disk = try JSONDecoder().decode(HarborPluginCatalogDocument.self, from: Data(contentsOf: file))
        XCTAssertEqual(disk.plugins.first?.autoPaused, false); XCTAssertEqual(disk.plugins.first?.failures, 0)
    }

    func testPausedMasterBlocksChecksAndFailedCheckShowsOnlySafeRuntimeCode() async throws {
        let (model, _, options, _) = try await prepared(source: #"var plugin={id:'owned.activity',name:'Owned',streams:function(){throw new Error('owned-private-token');}};"#)
        defer { model.runtime.dispose(); model.manager.dispose() }
        options.value.enabled = false
        XCTAssertFalse(model.canCheck); await model.check()
        XCTAssertNil(model.result); XCTAssertNil(model.error); XCTAssertEqual(model.runtime.residentWorkerCount, 0)
        options.value.enabled = true; await model.check()
        XCTAssertNil(model.result); XCTAssertFalse(model.checking); XCTAssertNotNil(model.error)
        XCTAssertTrue(model.error?.contains("plugin-call") == true); XCTAssertFalse(model.error?.contains("owned-private-token") == true)
        XCTAssertEqual(model.plugin?.failures, 1)
    }

    func testClosingActivityCancelsRealRequestWithoutLateResultOrFailure() async throws {
        let (model, network, _, _) = try await prepared(source: #"var plugin={id:'owned.activity',name:'Owned',streams:async function(){await harbor.http('https://files.example.org/hold');return [];}};"#)
        defer { model.runtime.dispose(); model.manager.dispose(); Task { await network.release() } }
        let task = Task { await model.check() }
        try await network.waitUntilHeld(); task.cancel(); model.clear(); await network.release(); await task.value
        XCTAssertFalse(model.checking); XCTAssertNil(model.result); XCTAssertNil(model.error)
        XCTAssertEqual(model.plugin?.failures, 0); XCTAssertNil(model.health?.lastAt)
    }
}
