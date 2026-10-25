import XCTest
@testable import Harbor

@MainActor final class LayoutEditProvenanceTests: XCTestCase {
    func testLegacyObjectLayoutsRemainReadableAndTheEditorIsStoredWithTheSameAtomicRecord() throws {
        let prefix = "owned-layout-origin-" + UUID().uuidString, navKey = prefix + "-nav", pageKey = prefix + "-page"
        defer { try? KeychainStore().remove(navKey); try? KeychainStore().remove(pageKey) }
        let nav = NativeNavigationLayout(order: ["anime"], hidden: ["sports"], renamed: ["anime": "Owned"])
        var page = PageLayout(); page.order = ["discovery-cm-drama"]
        try KeychainStore().write(nav, key: navKey); try KeychainStore().write(page, key: pageKey)
        XCTAssertNil(try LayoutEditStorage.object(navKey, as: NativeNavigationLayout.self)?.editor)
        XCTAssertNil(try LayoutEditStorage.object(pageKey, as: PageLayout.self)?.editor)
        try LayoutEditStorage.writeObject(.init(value: nav, editor: "profile-A"), key: navKey)
        try LayoutEditStorage.writeObject(.init(value: page, editor: "profile-A"), key: pageKey)
        XCTAssertEqual(try LayoutEditStorage.object(navKey, as: NativeNavigationLayout.self)?.editor, "profile-A")
        XCTAssertEqual(try LayoutEditStorage.object(pageKey, as: PageLayout.self)?.editor, "profile-A")
        XCTAssertEqual(try KeychainStore().read(navKey, as: NativeNavigationLayout.self), nav)
        XCTAssertEqual(try KeychainStore().read(pageKey, as: PageLayout.self), page)
        let raw = try XCTUnwrap(KeychainStore().read(pageKey, as: JSONValue.self))
        XCTAssertEqual(raw["_nativeLocalLayoutEditor"].string, "profile-A")
        XCTAssertEqual(raw["order"].array.first?.string, "discovery-cm-drama")
    }
    func testLegacyServiceDictionariesMigrateWithoutLosingUnknownValuesAndKeepTheirActualEditingProfile() throws {
        let owner = "owned-stream-origin-" + UUID().uuidString
        let local = "native-streaming-" + EBookShelf.hash(owner)
        let scope = NavigationScope.harbor(owner: owner, account: "owned-account", profile: "profile-A", linked: true)
        let scoped = "scoped-streaming-" + EBookShelf.hash(scope.key)
        defer { try? KeychainStore().remove(local); try? KeychainStore().remove(scoped) }
        try KeychainStore().write(["future-local-choice": true, "netflix": true], key: local)
        XCTAssertNil(try LayoutEditStorage.dictionary(local)?.editor)
        let preferences = StreamingPreferences(owner: owner); preferences.bind(scope)
        XCTAssertTrue(preferences.setEnabled(false, for: "netflix"))
        let restored = StreamingPreferences(owner: owner); restored.bind(scope)
        XCTAssertEqual(restored.lastEditor, "profile-A")
        XCTAssertEqual(restored.values["future-local-choice"], true); XCTAssertFalse(restored.isEnabled("netflix"))
        try restored.apply(restored.selection, to: scope)
        XCTAssertEqual(try LayoutEditStorage.dictionary(scoped)?.editor, "")
        let wire = try DesktopStreamingSelection(.object([:])).applying(restored.selection).raw
        XCTAssertEqual(wire["_nativeLocalLayoutEditor"], .null); XCTAssertEqual(wire["future-local-choice"], .null)
    }
    func testMalformedEditorMetadataBlocksLoadingAndAnInvalidWriteCannotReplaceThePreviousLayout() throws {
        let owner = "owned-invalid-origin-" + UUID().uuidString, scope = NavigationScope.local(owner: owner)
        defer { try? KeychainStore().remove(scope.key) }
        let nav = NativeNavigationLayout(order: ["anime"])
        try LayoutEditStorage.writeObject(.init(value: nav, editor: "profile-A"), key: scope.key)
        let before = try KeychainStore().read(scope.key, as: JSONValue.self)
        XCTAssertThrowsError(try LayoutEditStorage.writeObject(.init(value: nav, editor: String(repeating: "x", count: 257)), key: scope.key))
        XCTAssertEqual(try KeychainStore().read(scope.key, as: JSONValue.self), before)
        var malformed = try JSONValue.encoded(nav).objectValue; malformed["_nativeLocalLayoutEditor"] = .integer(7)
        try KeychainStore().write(JSONValue.object(malformed), key: scope.key)
        let preferences = ScopedNavigationPreferences(); preferences.bind(scope)
        XCTAssertFalse(preferences.ready); XCTAssertNotNil(preferences.error)
        XCTAssertEqual(try KeychainStore().read(scope.key, as: JSONValue.self), .object(malformed))
    }
}
