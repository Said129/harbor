import XCTest
@testable import Harbor

final class HarborPluginInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedPluginInTheOrdinaryLocalInstallation() async throws {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else {
            XCTFail("Refuse to seed a configured account"); return
        }
        let context = AppProfileContext.shared
        try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil,
              context.profiles.active?.desktop.isKid == false, context.configuration?.account == nil else {
            XCTFail("Refuse to seed configured or locked profiles"); return
        }
        if context.configuration?.guestAddons == nil {
            try context.save(HouseholdSourceAccount(account: nil, guestAddons: []))
        }
        let store = try HarborPluginCatalogStore(namespace: "device-stream-plugins-v1")
        try await store.load()
        var current = try await store.snapshot()
        let url = "https://example.org/owned-ui/manifest.json"
        guard current.repositories.allSatisfy({ $0.url == url }), current.plugins.allSatisfy({ $0.entry.id == "owned.ui.form" }) else {
            XCTFail("Refuse to replace configured plugins"); return
        }
        let manifest = try HarborPluginManifest.parse(.object(["name": .string("Owned UI repository"), "plugins": .array([
            .object(["id": .string("owned.ui.form"), "name": .string("Owned UI plugin"), "entry": .string("form.js"),
                "version": .string("1"), "settings": .bool(true), "description": .string("Owned offline interface fixture")])])]), url: url)
        try await store.saveRepository(.init(url: url, manifest: manifest, checkedAt: 1), revision: current.revision)
        current = try await store.snapshot()
        let source = #"var plugin={id:'owned.ui.form',name:'Owned UI plugin',streams:function(){return [];},settings:function(){return [{type:'header',label:'Account'},{type:'text',key:'token',label:'Token',isPassword:true},{type:'select',key:'quality',label:'Quality',options:[{value:'1080',label:'FHD'},{value:'720',label:'HD'}]},{type:'checkbox',key:'enabled',label:'Enabled',defaultValue:true},{type:'text',key:'name',label:'Name',defaultValue:'reader'}];}};"#
        try await store.install(repository: url, entry: XCTUnwrap(manifest.entries.first), code: source, etag: nil, methods: ["streams", "settings"], time: 1, revision: current.revision)
        let prepared = try await store.snapshot()
        XCTAssertEqual(prepared.plugins.count, 1); XCTAssertEqual(prepared.plugins.first?.runnable, true)
        let defaults = UserDefaults.standard
        defaults.set("es", forKey: "uiLanguage")
        defaults.set(true, forKey: "nativeGuide.initialized.v1"); defaults.set(true, forKey: "nativeGuide.completed.v1")
    }
}
