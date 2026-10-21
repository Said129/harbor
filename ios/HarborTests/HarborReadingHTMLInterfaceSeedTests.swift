import XCTest
@testable import Harbor

final class HarborReadingHTMLInterfaceSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedManualSourcesForTheOrdinaryPhoneAndTabletReaders() async throws {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else { XCTFail("Refuse to seed an account"); return }
        let context = AppProfileContext.shared; try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil,
              context.profiles.active?.desktop.isKid == false, context.configuration?.account == nil else { XCTFail("Refuse configured profiles"); return }
        if context.configuration?.guestAddons == nil { try context.save(HouseholdSourceAccount(account: nil, guestAddons: [])) }
        let store = try HarborReadingPluginStore(), document = try await store.load()
        guard document.plugins.isEmpty, document.repositories.isEmpty else { XCTFail("Refuse configured sources"); return }
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "reading-html-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        let scope = PluginExecutionScope(owner: "owned-html-ui", activation: UUID())
        let manager = HarborReadingPluginManager(scope: scope, currentScope: { scope }, store: store)
        defer { manager.dispose() }; try await manager.load()
        for kind in HarborReadingPluginKind.allCases {
            var config = try XCTUnwrap(fixture["fixtures"].array.first { $0["kind"].string == kind.rawValue })["config"].objectValue
            config["baseUrl"] = .string("http://127.0.0.1:18734")
            config["popularPath"] = .string("/html/popular?page={page}"); config["searchPath"] = .string("/html/search?q={query}&page={page}")
            var detail = config["detail"]?.objectValue ?? [:]; detail["cover"] = .string("img.poster@src"); config["detail"] = .object(detail)
            config["headers"] = .object(["Referer": .string("http://127.0.0.1:18734/")])
            let raw = String(decoding: try JSONEncoder().encode(JSONValue.object(config)), as: UTF8.self)
            try await manager.saveHTML(kind: kind, raw: raw, name: kind == .manga ? "Owned manual Manga" : "Owned manual Books", language: "en")
        }
        XCTAssertEqual(manager.document.plugins.count, 2)
        UserDefaults.standard.set("es", forKey: "uiLanguage")
        UserDefaults.standard.set(true, forKey: "nativeGuide.initialized.v1"); UserDefaults.standard.set(true, forKey: "nativeGuide.completed.v1")
        UserDefaults.standard.set(false, forKey: "interface.autoRotateBanners")
    }
}
