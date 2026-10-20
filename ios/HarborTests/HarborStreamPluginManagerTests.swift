import XCTest
@testable import Harbor

private actor ManagedPluginNetwork: HarborNativeNetworkCalling {
    private var responses: [String: HarborNetworkResponse] = [:]
    private var waitingURL: String?
    private var held: CheckedContinuation<Void, Never>?
    func set(_ url: String, _ text: String, headers: [String: String] = [:]) {
        responses[url] = .init(status: 200, ok: true, headers: headers, bodyBase64: Data(text.utf8).base64EncodedString(), url: url)
    }
    func hold(_ url: String) { waitingURL = url }
    func remove(_ url: String) { responses.removeValue(forKey: url) }
    func waitUntilHeld() async throws {
        for _ in 0..<100 { if held != nil { return }; try await Task.sleep(for: .milliseconds(20)) }
        throw HarborPluginRepositoryError("owned-timeout")
    }
    func release() { waitingURL = nil; held?.resume(); held = nil }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        if request.url == waitingURL { await withCheckedContinuation { held = $0 } }
        guard let value = responses[request.url] else { throw HarborError(code: "owned-no-answer") }
        return value
    }
}

private actor ManagedPluginSecrets: HarborPluginSecrets {
    private var values: [String: [String: String]] = [:]
    func read(plugin: String, revision: String) throws -> [String: String] {
        guard let value = values[plugin + "/" + revision] else { throw HarborPluginRepositoryError("plugin-secrets-missing") }
        return value
    }
    func stage(plugin: String, values: [String: String]) -> String {
        let revision = UUID().uuidString; self.values[plugin + "/" + revision] = values; return revision
    }
    func remove(plugin: String, revision: String) { values.removeValue(forKey: plugin + "/" + revision) }
    func count() -> Int { values.count }
}

/// The actual catalog writer can change the owner immediately after its atomic write.
private final class ManagedCommitControl: @unchecked Sendable {
    private let lock = NSLock()
    private var scope = PluginExecutionScope(owner: "owned-manager", activation: UUID())
    private var next = "normal"
    func current() -> PluginExecutionScope { lock.lock(); defer { lock.unlock() }; return scope }
    func rotate() { lock.lock(); scope = .init(owner: "other-owner", activation: UUID()); lock.unlock() }
    func arm(_ mode: String) { lock.lock(); next = mode; lock.unlock() }
    func write(_ data: Data, _ url: URL) throws {
        lock.lock(); let mode = next; next = "normal"; lock.unlock()
        if mode == "fail" { throw HarborPluginRepositoryError("owned-write-failed") }
        try data.write(to: url, options: .atomic)
        if mode == "rotate" { rotate() }
    }
}

@MainActor private struct ManagedRejectingProbe: HarborStreamPluginProbing {
    func methods(id: String, entry: HarborStreamPluginEntry, source: String, settings: [String: JSONValue], scope: PluginExecutionScope,
        currentScope: @escaping @MainActor () -> PluginExecutionScope, transport: any HarborPluginHostTransport) async throws -> [String] {
        throw HarborPluginRuntimeError("owned-probe-failure")
    }
}

@MainActor final class HarborStreamPluginManagerTests: XCTestCase {
    private let url = "https://example.org/manifest.json", codeURL = "https://example.org/one.js"
    private let code = #"var plugin={id:'one',name:'One',streams:async function(){return [];}};"#

    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("owned-plugin-manager-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("catalog.json")
    }
    private func seed(_ network: ManagedPluginNetwork, version: String = "1", provider: Bool = false, source: String? = nil, sha: String? = nil) async throws {
        let row: JSONValue = .object(["id": .string("one"), "name": .string("One"), "version": .string(version),
            provider ? "filename" : "entry": .string("one.js"), "settings": .bool(true), "sha256": sha.map(JSONValue.string) ?? .null])
        let manifest: JSONValue = .object(["name": .string("Owned repository"), provider ? "scrapers" : "plugins": .array([row])])
        let text = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)
        await network.set(url, text); await network.set(codeURL, source ?? code, headers: ["etag": "owned-" + version])
    }
    private func makeManager(file: URL, network: ManagedPluginNetwork, secrets: ManagedPluginSecrets = .init(), control: ManagedCommitControl = .init(),
        probe: (any HarborStreamPluginProbing)? = nil) throws -> (HarborStreamPluginManager, HarborPluginCatalogStore) {
        let store = try HarborPluginCatalogStore(namespace: "owned-manager", file: file, write: { data, url in try control.write(data, url) })
        return (HarborStreamPluginManager(namespace: "owned-manager", scope: control.current(), currentScope: { control.current() }, store: store,
            client: .init(network: network), secrets: secrets, probe: probe), store)
    }

    func testActualWorkerProbeInstallsThenRefreshesUpdatesAndRollsBackWithoutLosingUserChoice() async throws {
        let network = ManagedPluginNetwork(), file = try location()
        try await seed(network)
        let (manager, _) = try makeManager(file: file, network: network); defer { manager.dispose() }
        try await manager.load(); try await manager.addRepository(url); try await manager.install(repository: url, entryID: "one")
        let installed = try XCTUnwrap(manager.document.plugins.first)
        XCTAssertEqual(installed.code, code); XCTAssertEqual(installed.etag, "owned-1")
        try await manager.setEnabled(installed.id, false)
        let nextCode = #"var plugin={id:'one',name:'One',streams:async function(){return [{url:'https://example.org/owned'}];}};"#
        try await seed(network, version: "2", source: nextCode)
        try await manager.refreshRepository(url)
        XCTAssertEqual(manager.document.plugins.first?.updateVersion, "2"); XCTAssertEqual(manager.document.plugins.first?.code, code)
        try await manager.install(repository: url, entryID: "one")
        XCTAssertEqual(manager.document.plugins.first?.code, nextCode); XCTAssertEqual(manager.document.plugins.first?.enabled, false)
        try await manager.revert(installed.id)
        XCTAssertEqual(manager.document.plugins.first?.code, code); XCTAssertEqual(manager.document.plugins.first?.etag, "owned-1")
        XCTAssertEqual(manager.document.plugins.first?.updateVersion, "2")
        try await manager.setEnabled(installed.id, true)
        XCTAssertEqual(manager.document.plugins.first?.runnable, true)
        await network.set(url, #"{"name":"Owned repository","plugins":[]}"#)
        try await manager.refreshRepository(url)
        XCTAssertEqual(manager.document.plugins.first?.listed, false); XCTAssertEqual(manager.document.plugins.first?.runnable, false)
        XCTAssertEqual(manager.document.plugins.first?.code, code)
        try await manager.removeRepository(url)
        XCTAssertTrue(manager.document.repositories.isEmpty); XCTAssertTrue(manager.document.plugins.isEmpty)
        let reloaded = try JSONDecoder().decode(HarborPluginCatalogDocument.self, from: Data(contentsOf: file))
        XCTAssertEqual(reloaded, manager.document)
    }

    func testChecksumAndActualWrongMethodOrProbeFailureLeaveNoInstalledCandidate() async throws {
        let network = ManagedPluginNetwork(), file = try location()
        try await seed(network, sha: String(repeating: "0", count: 64))
        let (manager, _) = try makeManager(file: file, network: network); defer { manager.dispose() }
        try await manager.load(); try await manager.addRepository(url)
        do { try await manager.install(repository: url, entryID: "one"); XCTFail("Checksum accepted") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "checksum") }
        try await seed(network, source: #"var plugin={id:'one',name:'One',search:async function(){return [];}};"#)
        try await manager.refreshRepository(url)
        do { try await manager.install(repository: url, entryID: "one"); XCTFail("Wrong method accepted") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "not-stream-plugin") }
        XCTAssertTrue(manager.document.plugins.isEmpty)
        try await seed(network, provider: true, source: "module.exports={};")
        try await manager.refreshRepository(url)
        do { try await manager.install(repository: url, entryID: "one"); XCTFail("Provider without getStreams accepted") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "not-stream-plugin") }
        manager.dispose()
        let (rejecting, _) = try makeManager(file: file, network: network, probe: ManagedRejectingProbe()); defer { rejecting.dispose() }
        try await rejecting.load()
        do { try await rejecting.install(repository: url, entryID: "one"); XCTFail("Failed probe installed") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "start-failed") }
        XCTAssertTrue(rejecting.document.plugins.isEmpty)
    }

    func testProviderEntryIdentityAndCommittedSecretsReachTheRealUpdateProbeWithoutEnteringCatalog() async throws {
        let network = ManagedPluginNetwork(), secrets = ManagedPluginSecrets(), file = try location()
        let source = #"if(SCRAPER_ID!=='one')throw new Error('wrong entry identity');module.exports.getStreams=async function(){return [];};"#
        try await seed(network, provider: true, source: source)
        let (manager, _) = try makeManager(file: file, network: network, secrets: secrets); defer { manager.dispose() }
        try await manager.load(); try await manager.addRepository(url); try await manager.install(repository: url, entryID: "one")
        let id = try XCTUnwrap(manager.document.plugins.first?.id)
        try await manager.saveSettings(id, values: ["token": .string("OWNED-PRIVATE-TOKEN"), "enabled": .bool(true)], passwordKeys: ["token"])
        let revision = try XCTUnwrap(manager.document.plugins.first?.secretRevision)
        XCTAssertEqual(manager.document.plugins.first?.settingsValues, ["enabled": .bool(true)])
        XCTAssertFalse(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("OWNED-PRIVATE-TOKEN"))
        let configuration = try await manager.configuration(id); XCTAssertEqual(configuration["token"], .string("OWNED-PRIVATE-TOKEN"))
        try await seed(network, version: "2", provider: true,
            source: source + #"if(SCRAPER_SETTINGS.token!=='OWNED-PRIVATE-TOKEN')throw new Error('settings missing');"#)
        try await manager.refreshRepository(url); try await manager.install(repository: url, entryID: "one")
        XCTAssertEqual(manager.document.plugins.first?.secretRevision, revision)
        try await manager.uninstall(id)
        let count = await secrets.count(); XCTAssertEqual(count, 0)
    }

    func testFailedSettingsWriteRetainsOldCredentialsAndRemovesOnlyTheUncommittedRevision() async throws {
        let network = ManagedPluginNetwork(), secrets = ManagedPluginSecrets(), control = ManagedCommitControl(), file = try location()
        try await seed(network)
        let (manager, _) = try makeManager(file: file, network: network, secrets: secrets, control: control); defer { manager.dispose() }
        try await manager.load(); try await manager.addRepository(url); try await manager.install(repository: url, entryID: "one")
        let id = try XCTUnwrap(manager.document.plugins.first?.id)
        try await manager.saveSettings(id, values: ["token": .string("owned-old")], passwordKeys: ["token"])
        let prior = manager.document, priorBytes = try Data(contentsOf: file)
        control.arm("fail")
        do { try await manager.saveSettings(id, values: ["token": .string("owned-next")], passwordKeys: ["token"]); XCTFail("Write failure ignored") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "owned-write-failed") }
        XCTAssertEqual(manager.document, prior); XCTAssertEqual(try Data(contentsOf: file), priorBytes)
        let configuration = try await manager.configuration(id), count = await secrets.count()
        XCTAssertEqual(configuration["token"], .string("owned-old")); XCTAssertEqual(count, 1)
    }

    func testScopeChangeAfterTheCatalogWriteNeverDeletesItsCommittedSecretRevision() async throws {
        let network = ManagedPluginNetwork(), secrets = ManagedPluginSecrets(), control = ManagedCommitControl(), file = try location()
        try await seed(network)
        let (manager, _) = try makeManager(file: file, network: network, secrets: secrets, control: control); defer { manager.dispose() }
        try await manager.load(); try await manager.addRepository(url); try await manager.install(repository: url, entryID: "one")
        let id = try XCTUnwrap(manager.document.plugins.first?.id)
        control.arm("rotate")
        do { try await manager.saveSettings(id, values: ["token": .string("owned-committed")], passwordKeys: ["token"]); XCTFail("Old owner published") }
        catch { XCTAssertTrue(error is CancellationError || (error as? HarborPluginRepositoryError)?.code == "plugin-scope") }
        XCTAssertFalse(manager.ready); XCTAssertTrue(manager.document.plugins.isEmpty)
        let disk = try JSONDecoder().decode(HarborPluginCatalogDocument.self, from: Data(contentsOf: file))
        let revision = try XCTUnwrap(disk.plugins.first?.secretRevision)
        let saved = try await secrets.read(plugin: id, revision: revision)
        XCTAssertEqual(saved["token"], "owned-committed")
    }

    func testChangedOwnerCancellationAndChangedManifestDiscardDownloadedCandidatesBeforeCommit() async throws {
        for outcome in 0..<3 {
            let network = ManagedPluginNetwork(), control = ManagedCommitControl(), file = try location()
            try await seed(network)
            let (manager, store) = try makeManager(file: file, network: network, control: control)
            try await manager.load(); try await manager.addRepository(url)
            var before = try await store.snapshot()
            await network.hold(codeURL)
            let task = Task { try await manager.install(repository: url, entryID: "one") }
            try await network.waitUntilHeld()
            if outcome == 0 { control.rotate() }
            else if outcome == 1 { task.cancel() }
            else {
                try await seed(network, version: "2"); try await manager.refreshRepository(url)
                before = try await store.snapshot()
            }
            await network.release()
            do { try await task.value; XCTFail("Late candidate installed") }
            catch {
                if outcome == 2 { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "plugin-candidate-changed") }
                else { XCTAssertTrue(error is CancellationError || (error as? HarborPluginRepositoryError)?.code == "plugin-scope") }
            }
            let retained = try await store.snapshot(); XCTAssertEqual(retained, before)
            manager.dispose()
        }
    }

    func testFailedRepositoryRefreshKeepsInstalledCodeAndRecordsItsSafeFailure() async throws {
        let network = ManagedPluginNetwork(), file = try location()
        try await seed(network)
        let (manager, _) = try makeManager(file: file, network: network); defer { manager.dispose() }
        try await manager.load(); try await manager.addRepository(url); try await manager.install(repository: url, entryID: "one")
        let prior = manager.document.plugins
        await network.remove(url)
        try await manager.refreshRepository(url)
        XCTAssertEqual(manager.document.repositories.first?.error, "no-answer")
        XCTAssertEqual(manager.document.plugins, prior); XCTAssertEqual(manager.document.plugins.first?.runnable, true)
        let disk = try JSONDecoder().decode(HarborPluginCatalogDocument.self, from: Data(contentsOf: file))
        XCTAssertEqual(disk, manager.document)
    }

    func testActualKeychainRevisionsRemainIsolatedByOwnerAndPlugin() async throws {
        let namespace = "owned-keychain-" + UUID().uuidString
        let vault = HarborPluginSecretVault(namespace: namespace), other = HarborPluginSecretVault(namespace: namespace + "-other")
        let first = try await vault.stage(plugin: "one", values: ["token":"owned-first"])
        addTeardownBlock { try? await vault.remove(plugin: "one", revision: first) }
        let second = try await vault.stage(plugin: "one", values: ["token":"owned-second"])
        addTeardownBlock { try? await vault.remove(plugin: "one", revision: second) }
        let old = try await vault.read(plugin: "one", revision: first), next = try await vault.read(plugin: "one", revision: second)
        XCTAssertEqual(old["token"], "owned-first"); XCTAssertEqual(next["token"], "owned-second")
        do { _ = try await other.read(plugin: "one", revision: first); XCTFail("Another owner read credentials") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "plugin-secrets-missing") }
        do { _ = try await vault.read(plugin: "two", revision: first); XCTFail("Another plugin read credentials") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "plugin-secrets-missing") }
        try await vault.remove(plugin: "one", revision: first)
        let kept = try await vault.read(plugin: "one", revision: second); XCTAssertEqual(kept, next)
    }
}
