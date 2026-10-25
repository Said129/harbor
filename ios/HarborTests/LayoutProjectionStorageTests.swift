import XCTest
@testable import Harbor

@MainActor final class LayoutProjectionStorageTests: XCTestCase {
    func testProjectionAndEditorRoundTripAtomicallyWithoutChangingLegacyNativeValuesOrWireCodecs() throws {
        let key = "owned-projection-" + UUID().uuidString, servicesKey = key + "-services"
        defer { try? KeychainStore().remove(key); try? KeychainStore().remove(servicesKey) }
        let layout = NativeNavigationLayout(order: ["anime"])
        let raw: JSONValue = .object(["future": .object(["desktop": .integer(7)]), "games": .bool(false)])
        try LayoutEditStorage.writeObject(.init(value: layout, editor: "profile-A", projection: raw), key: key)
        let snapshot = try XCTUnwrap(LayoutEditStorage.object(key, as: NativeNavigationLayout.self))
        XCTAssertEqual(snapshot.editor, "profile-A"); XCTAssertEqual(snapshot.projection, raw)
        XCTAssertEqual(try KeychainStore().read(key, as: NativeNavigationLayout.self), layout)
        try LayoutEditStorage.writeDictionary(.init(value: ["netflix": false], editor: "profile-A", projection: raw), key: servicesKey)
        XCTAssertEqual(try LayoutEditStorage.dictionary(servicesKey)?.projection, raw)
        XCTAssertEqual(try LayoutEditStorage.dictionary(servicesKey)?.value, ["netflix": false])
        let wire = try DesktopNavigationLayout(raw).applying(layout, knownIDs: ["anime"], defaultOrder: ["anime"]).raw
        XCTAssertEqual(wire["future"], raw["future"]); XCTAssertEqual(wire["_nativeLayoutProjection"], .null)
        XCTAssertEqual(wire["_nativeLocalLayoutEditor"], .null)
    }
    func testMalformedProjectionCannotReplaceOrExposeThePreviousPreferenceRecord() throws {
        let owner = "owned-invalid-projection-" + UUID().uuidString, scope = NavigationScope.local(owner: owner)
        defer { try? KeychainStore().remove(scope.key) }
        let value = NativeNavigationLayout(order: ["anime"])
        try LayoutEditStorage.writeObject(.init(value: value, editor: "profile-A", projection: .object([:])), key: scope.key)
        let before = try KeychainStore().read(scope.key, as: JSONValue.self)
        for raw: JSONValue in [.array([]), .string("bad"), .object(["large": .string(String(repeating: "x", count: 96 * 1_024))])] {
            XCTAssertThrowsError(try LayoutEditStorage.writeObject(.init(value: value, editor: "profile-B", projection: raw), key: scope.key))
            XCTAssertEqual(try KeychainStore().read(scope.key, as: JSONValue.self), before)
        }
        var malformed = try JSONValue.encoded(value).objectValue; malformed["_nativeLayoutProjection"] = .array([])
        try KeychainStore().write(JSONValue.object(malformed), key: scope.key)
        let preferences = ScopedNavigationPreferences(); preferences.bind(scope)
        XCTAssertFalse(preferences.ready); XCTAssertNotNil(preferences.error)
        XCTAssertEqual(try KeychainStore().read(scope.key, as: JSONValue.self), .object(malformed))
    }
}
