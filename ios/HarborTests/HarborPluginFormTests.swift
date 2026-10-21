import XCTest
@testable import Harbor

@MainActor private final class PluginFormScope {
    var value = PluginExecutionScope(owner: "owned-plugin-form", activation: UUID())
}

@MainActor final class HarborPluginFormTests: XCTestCase {
    private let source = #"var plugin={id:'form',name:'Owned form',streams:function(){return [];},settings:function(){return [{type:'header',label:'Account'},{type:'text',key:'token',label:'Token',isPassword:true},{type:'select',key:'quality',label:'Quality',options:[{value:'1080',label:'FHD'},{value:'720',label:'HD'}]},{type:'checkbox',key:'enabled',label:'Enabled',defaultValue:true},{type:'text',key:'name',label:'Name',defaultValue:'reader'}];}};"#

    private func prepared() async throws -> (HarborStreamPluginManager, HarborPluginCatalogStore, HarborPluginSecretVault, URL, String) {
        let namespace = "owned-form-" + UUID().uuidString
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(namespace, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("catalog.json")
        let store = try HarborPluginCatalogStore(namespace: namespace, file: file)
        try await store.load()
        let url = "https://example.org/owned/manifest.json"
        let manifest = try HarborPluginManifest.parse(.object(["name": .string("Owned"), "plugins": .array([
            .object(["id": .string("form"), "name": .string("Owned form"), "entry": .string("form.js"), "settings": .bool(true)])])]), url: url)
        try await store.saveRepository(.init(url: url, manifest: manifest, checkedAt: 1), revision: 0)
        let entry = try XCTUnwrap(manifest.entries.first)
        try await store.install(repository: url, entry: entry, code: source, etag: nil, methods: ["streams", "settings"], time: 1, revision: 1)
        let id = HarborPluginManifest.pluginID(repository: url, entry: "form")
        let scope = PluginExecutionScope(owner: namespace, activation: UUID()), vault = HarborPluginSecretVault(namespace: namespace)
        let revision = try await vault.stage(plugin: id, values: ["unlistedPassword": "owned-unlisted-password"])
        addTeardownBlock { try? await vault.remove(plugin: id, revision: revision) }
        try await store.saveSettings(id, values: ["retained": .string("owned-existing")], secretKeys: ["unlistedPassword"], secretRevision: revision, revision: 2)
        let manager = HarborStreamPluginManager(namespace: namespace, scope: scope, currentScope: { scope }, store: store, secrets: vault)
        addTeardownBlock {
            if let bytes = try? Data(contentsOf: file), let document = try? JSONDecoder().decode(HarborPluginCatalogDocument.self, from: bytes) {
                for plugin in document.plugins {
                    if let revision = plugin.secretRevision { try? await vault.remove(plugin: plugin.id, revision: revision) }
                }
            }
            try? FileManager.default.removeItem(at: folder)
        }
        try await manager.load()
        return (manager, store, vault, file, namespace)
    }

    func testActualFormDefaultsAndSecureSaveKeepUnknownValuesAndClearTheClosedDraft() async throws {
        let (manager, _, _, file, _) = try await prepared(); defer { manager.dispose() }
        let plugin = try XCTUnwrap(manager.document.plugins.first), draft = HarborPluginSettingsDraft(manager: manager, plugin: plugin)
        await draft.load()
        XCTAssertTrue(draft.ready); XCTAssertNil(draft.failure)
        XCTAssertEqual(draft.values["quality"], .string("1080")); XCTAssertEqual(draft.values["enabled"], .bool(true))
        XCTAssertEqual(draft.values["name"], .string("reader")); XCTAssertEqual(draft.values["retained"], .string("owned-existing"))
        draft.values["token"] = .string("owned-form-password"); draft.values["enabled"] = .bool(false)
        let saved = await draft.save(); XCTAssertTrue(saved)
        let configuration = try await manager.configuration(plugin.id)
        XCTAssertEqual(configuration["token"], .string("owned-form-password")); XCTAssertEqual(configuration["enabled"], .bool(false))
        XCTAssertEqual(configuration["retained"], .string("owned-existing"))
        XCTAssertEqual(configuration["unlistedPassword"], .string("owned-unlisted-password"))
        XCTAssertFalse(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("owned-form-password"))
        XCTAssertFalse(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("owned-unlisted-password"))
        XCTAssertNotNil(manager.document.plugins.first?.secretRevision)
        XCTAssertFalse(draft.ready); XCTAssertTrue(draft.values.isEmpty); XCTAssertTrue(draft.fields.isEmpty)
    }

    func testAnOpenFormCannotOverwriteNewerSavedSettingsOrTheirCredentials() async throws {
        let (manager, _, _, file, _) = try await prepared(); defer { manager.dispose() }
        let plugin = try XCTUnwrap(manager.document.plugins.first), draft = HarborPluginSettingsDraft(manager: manager, plugin: plugin)
        await draft.load(); XCTAssertTrue(draft.ready)
        try await manager.saveSettings(plugin.id, values: ["token": .string("owned-new-password")], passwordKeys: ["token"])
        let before = try Data(contentsOf: file)
        draft.values["token"] = .string("owned-stale-password")
        let saved = await draft.save(); XCTAssertFalse(saved); XCTAssertNotNil(draft.failure)
        XCTAssertEqual(try Data(contentsOf: file), before)
        let configuration = try await manager.configuration(plugin.id)
        XCTAssertEqual(configuration["token"], .string("owned-new-password"))
        XCTAssertEqual(draft.values["token"], .string("owned-stale-password"))
        draft.clear(); XCTAssertTrue(draft.values.isEmpty); XCTAssertNil(draft.failure)
    }

    func testTheDeviceLocalCatalogIsSharedButRetiredActivationCannotKeepItsManager() async throws {
        let (seed, _, _, file, namespace) = try await prepared(); seed.dispose()
        let session = HarborPluginSession(namespace: namespace, file: file), context = PluginFormScope()
        defer { session.invalidate() }
        let first = try await session.open(scope: context.value, currentScope: { context.value })
        let reopened = try await session.open(scope: context.value, currentScope: { context.value })
        XCTAssertTrue(first === reopened); XCTAssertEqual(first.document.plugins.count, 1)
        context.value = .init(owner: "owned-other-profile", activation: UUID()); session.invalidate()
        XCTAssertFalse(first.ready); XCTAssertTrue(first.document.plugins.isEmpty)
        let next = try await session.open(scope: context.value, currentScope: { context.value })
        XCTAssertFalse(first === next); XCTAssertEqual(next.document.plugins.count, 1)
        do {
            try await first.saveSettings("owned", values: [:], passwordKeys: [])
            XCTFail("Retired activation changed the catalog")
        } catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "plugin-scope") }
        let prior = context.value
        context.value = .init(owner: "locked", activation: UUID()); session.invalidate()
        do { _ = try await session.open(scope: prior, currentScope: { context.value }); XCTFail("Locked scope opened") }
        catch { XCTAssertEqual((error as? HarborPluginRepositoryError)?.code, "plugin-scope") }
    }
}
