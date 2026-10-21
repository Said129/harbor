import XCTest
@testable import Harbor

private actor PoolSecrets: HarborPluginSecrets {
    private var values: [String: [String: String]] = [:]
    func stage(plugin: String, values: [String: String]) -> String { let id = UUID().uuidString; self.values[id] = values; return id }
    func read(plugin: String, revision: String) throws -> [String: String] {
        guard let result = values[revision] else { throw HarborPluginRepositoryError("plugin-secrets-missing") }; return result
    }
    func remove(plugin: String, revision: String) { values[revision] = nil }
}
private actor PoolNetwork: HarborNativeNetworkCalling {
    private var holding = true
    private var held: [CheckedContinuation<Void, Never>] = []
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        if holding && request.url.contains("/hold") { await withCheckedContinuation { held.append($0) } }
        return .init(status: 200, ok: true, headers: [:], bodyBase64: Data("owned".utf8).base64EncodedString(), url: request.url)
    }
    func release() { holding = false; let all = held; held = []; all.forEach { $0.resume() } }
    func hold() { holding = true }
    func waitUntilHeld() async throws {
        for _ in 0..<150 { if !held.isEmpty { return }; try await Task.sleep(for: .milliseconds(20)) }
        throw HarborPluginRepositoryError("owned-timeout")
    }
}
@MainActor private final class PoolContext {
    var scope = PluginExecutionScope(owner: "owned-plugin-pool", activation: UUID())
    var time: TimeInterval = 0
}
@MainActor private final class GateWork {
    var began: [Int] = []
    private var held: [Int: CheckedContinuation<Void, Never>] = [:]
    func wait(_ id: Int) async { began.append(id); await withCheckedContinuation { held[id] = $0 } }
    func release(_ id: Int) { held.removeValue(forKey: id)?.resume() }
    func releaseAll() { let all = Array(held.values); held = [:]; all.forEach { $0.resume() } }
    func waitForCount(_ count: Int) async throws {
        for _ in 0..<150 { if began.count >= count { return }; try await Task.sleep(for: .milliseconds(20)) }
        throw HarborPluginRepositoryError("owned-timeout")
    }
}

@MainActor final class HarborStreamPluginPoolTests: XCTestCase {
    private func prepared(count: Int = 1, source: @escaping (String) -> String) async throws
        -> (HarborStreamPluginManager, HarborStreamPluginPool, PoolNetwork, URL, PoolContext) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("owned-pool-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("catalog.json"), context = PoolContext(), network = PoolNetwork()
        let store = try HarborPluginCatalogStore(namespace: context.scope.owner, file: file)
        try await store.load()
        let url = "https://example.org/pool/manifest.json"
        let rows: [JSONValue] = (0..<count).map { index in .object(["id": .string("owned.\(index)"), "name": .string("Owned \(index)"), "entry": .string("\(index).js")]) }
        let manifest = try HarborPluginManifest.parse(.object(["plugins": .array(rows)]), url: url)
        try await store.saveRepository(.init(url: url, manifest: manifest, checkedAt: 1), revision: 0)
        for entry in manifest.entries {
            let before = try await store.snapshot()
            try await store.install(repository: url, entry: entry, code: source(entry.id), etag: nil, methods: ["streams"], time: 1, revision: before.revision)
        }
        let manager = HarborStreamPluginManager(namespace: context.scope.owner, scope: context.scope, currentScope: { context.scope }, store: store,
            client: .init(network: network), secrets: PoolSecrets())
        try await manager.load()
        let pool = HarborStreamPluginPool(manager: manager, currentScope: { context.scope }, gate: HarborPluginCallGate(), now: { context.time })
        manager.invalidateRuntime = { [weak pool] id in pool?.invalidate(id) }
        return (manager, pool, network, file, context)
    }
    private let counter = #"var count=0;var plugin={id:'owned',name:'Owned',streams:function(req){return [{count:++count,token:req.settings.token||''}];}};"#

    func testActualWorkerIsReusedAndChangedSettingsStartAFreshConfiguredInstance() async throws {
        let source = counter
        let (manager, pool, _, _, _) = try await prepared { _ in source }
        defer { pool.dispose(); manager.dispose() }
        let id = try XCTUnwrap(manager.document.plugins.first?.id)
        let first = try await pool.run(id, request: .object([:])), second = try await pool.run(id, request: .object([:]))
        XCTAssertEqual(first.array.first?["count"].integer, 1); XCTAssertEqual(second.array.first?["count"].integer, 2)
        XCTAssertEqual(pool.residentWorkerCount, 1)
        try await manager.saveSettings(id, values: ["token": .string("owned-new")], passwordKeys: ["token"])
        XCTAssertEqual(pool.residentWorkerCount, 0)
        let configured = try await pool.run(id, request: .object([:]))
        XCTAssertEqual(configured.array.first?["count"].integer, 1); XCTAssertEqual(configured.array.first?["token"].string, "owned-new")
        XCTAssertEqual(manager.document.plugins.first?.failures, 0)
    }

    func testFourIdleBudgetAndFiveMinuteExpiryNeverDisposeAnActiveRequest() async throws {
        let (manager, pool, network, _, context) = try await prepared(count: 6) { id in
            id == "owned.0" ? #"var plugin={id:'held',name:'Held',streams:async function(){await harbor.http('https://files.example.org/hold');return [];}};"#
                : #"var plugin={id:'quick',name:'Quick',streams:function(){return [];}};"#
        }
        defer { pool.dispose(); manager.dispose(); Task { await network.release() } }
        let heldID = try XCTUnwrap(manager.document.plugins.first(where: { $0.entry.id == "owned.0" })?.id)
        let held = Task { try await pool.run(heldID, request: .object([:])) }
        try await network.waitUntilHeld()
        for plugin in manager.document.plugins where plugin.id != heldID { _ = try await pool.run(plugin.id, request: .object([:])) }
        XCTAssertEqual(pool.residentWorkerCount, 5)
        pool.sweep(trimIdle: true); XCTAssertEqual(pool.residentWorkerCount, 1)
        await network.release(); _ = try await held.value
        context.time = 301; pool.sweep(); XCTAssertEqual(pool.residentWorkerCount, 0)
    }

    func testGlobalEightOperationGateCancelsAQueuedCallerWithoutLeakingItsPermit() async throws {
        let gate = HarborPluginCallGate(), work = GateWork()
        var tasks: [Task<Void, Error>] = []
        defer { work.releaseAll(); tasks.forEach { $0.cancel() } }
        for id in 0..<8 {
            tasks.append(Task { try await gate.acquire(); defer { gate.release() }; try Task.checkCancellation(); await work.wait(id) })
        }
        try await work.waitForCount(8)
        let cancelled = Task { try await gate.acquire(); defer { gate.release() }; try Task.checkCancellation(); await work.wait(8) }
        tasks.append(cancelled)
        let final = Task { try await gate.acquire(); defer { gate.release() }; try Task.checkCancellation(); await work.wait(9) }
        tasks.append(final); await Task.yield()
        XCTAssertEqual(work.began.count, 8)
        cancelled.cancel()
        do { try await cancelled.value; XCTFail("Queued cancellation succeeded") } catch { XCTAssertTrue(error is CancellationError) }
        work.release(0); try await work.waitForCount(9)
        XCTAssertFalse(work.began.contains(8)); XCTAssertTrue(work.began.contains(9))
        work.releaseAll()
        for (index, task) in tasks.enumerated() where index != 8 { try await task.value }
        try await gate.acquire(); gate.release()
    }

    func testThreeRealFailuresPersistAutomaticPauseAndExplicitSuccessfulCheckRecoversIt() async throws {
        let (manager, pool, _, file, _) = try await prepared { _ in
            #"var plugin={id:'owned',name:'Owned',streams:function(req){if(req.title!=='recover')throw new Error('owned failure');return [{url:'https://files.example.org/owned.m3u8'}];}};"#
        }
        defer { pool.dispose(); manager.dispose() }
        let id = try XCTUnwrap(manager.document.plugins.first?.id)
        for expected in 1...3 {
            do { _ = try await pool.run(id, request: .object([:])); XCTFail("Broken provider succeeded") }
            catch { XCTAssertEqual((error as? HarborPluginRuntimeError)?.code, "plugin-call") }
            XCTAssertEqual(manager.document.plugins.first?.failures, expected)
        }
        XCTAssertEqual(manager.document.plugins.first?.autoPaused, true)
        let disk = try JSONDecoder().decode(HarborPluginCatalogDocument.self, from: Data(contentsOf: file))
        XCTAssertEqual(disk.plugins.first?.failures, 3); XCTAssertEqual(disk.plugins.first?.autoPaused, true)
        do { _ = try await pool.run(id, request: .object([:])); XCTFail("Paused provider ran") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "plugin-unavailable") }
        let recovered = try await pool.run(id, request: .object(["title": .string("recover")]), checking: true)
        XCTAssertEqual(recovered.array.count, 1); XCTAssertEqual(manager.document.plugins.first?.failures, 0)
        XCTAssertEqual(manager.document.plugins.first?.autoPaused, false); XCTAssertNil(pool.health[id]?.error)
    }

    func testCancellationAndRetiredActivationNeverCountAsFailuresOrPublishLateHealth() async throws {
        let (manager, pool, network, file, context) = try await prepared { _ in
            #"var plugin={id:'owned',name:'Owned',streams:async function(){await harbor.http('https://files.example.org/hold');return [];}};"#
        }
        defer { pool.dispose(); manager.dispose(); Task { await network.release() } }
        let id = try XCTUnwrap(manager.document.plugins.first?.id), before = try Data(contentsOf: file)
        let cancelled = Task { try await pool.run(id, request: .object([:])) }
        try await network.waitUntilHeld(); cancelled.cancel(); await network.release()
        do { _ = try await cancelled.value; XCTFail("Cancelled call returned") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(manager.document.plugins.first?.failures, 0); XCTAssertNil(pool.health[id]?.lastAt)
        await network.hold()
        let retiring = Task { try await pool.run(id, request: .object([:])) }
        try await network.waitUntilHeld()
        context.scope = .init(owner: "other-owner", activation: UUID()); pool.dispose(); manager.dispose(); await network.release()
        do { _ = try await retiring.value; XCTFail("Retired owner returned") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(pool.health.isEmpty); XCTAssertTrue(pool.logs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testBoundedRealWorkerLogsRedactLongPasswordsBeforeTruncationAndCountHTTPRequests() async throws {
        let (manager, pool, _, _, _) = try await prepared { _ in
            #"var plugin={id:'owned',name:'Owned',streams:async function(req){for(var i=0;i<210;i++)console.warn('owned '+i);console.log('token '+req.settings.token);await harbor.http('https://files.example.org/owned');return [];}};"#
        }
        defer { pool.dispose(); manager.dispose() }
        let id = try XCTUnwrap(manager.document.plugins.first?.id), secret = String(repeating: "owned-secret-", count: 60)
        try await manager.saveSettings(id, values: ["token": .string(secret)], passwordKeys: ["token"])
        _ = try await pool.run(id, request: .object(["title": .string("Owned title")]))
        let lines = pool.logs[id] ?? []
        XCTAssertEqual(lines.count, 200); XCTAssertTrue(lines.allSatisfy { $0.text.count <= 600 })
        XCTAssertTrue(lines.contains(where: { $0.text.contains("[redacted]") }))
        XCTAssertFalse(lines.contains(where: { $0.text.contains(String(secret.prefix(80))) }))
        XCTAssertEqual(pool.health[id]?.requests, 1); XCTAssertEqual(pool.health[id]?.seenHosts, ["files.example.org"])
        XCTAssertEqual(pool.health[id]?.title, "Owned title"); XCTAssertEqual(pool.health[id]?.count, 0)
    }
}
