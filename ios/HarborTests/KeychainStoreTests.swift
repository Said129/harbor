import Security
import XCTest
@testable import Harbor

final class KeychainStoreTests: XCTestCase {
    func testNativeKeychainRoundTripUpdateAndAccountIsolation() throws {
        let store = KeychainStore()
        let key = "tests.\(UUID().uuidString)"
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "site.harbor.iphone",
                kSecAttrAccount as String: key,
            ]
            let status = SecItemDelete(query as CFDictionary)
            XCTAssertTrue(status == errSecSuccess || status == errSecItemNotFound, "Keychain cleanup status=\(status)")
        }
        XCTAssertNil(try store.read(key, as: [String: String].self))
        try store.write(["credential": "test-private-value"], key: key)
        XCTAssertEqual(try store.read(key, as: [String: String].self), ["credential": "test-private-value"])
        try store.write(["credential": "test-updated-value"], key: key)
        XCTAssertEqual(try store.read(key, as: [String: String].self), ["credential": "test-updated-value"])
        XCTAssertNil(try store.read(key + ".other", as: [String: String].self))
        let owner = "tests-library-\(UUID().uuidString)"
        let presentationKey = LibraryPresentation.key(owner: owner)
        defer { try? store.remove(presentationKey) }
        var presentation = LibraryPresentation(); presentation.display.sort = .title
        let record = LibraryRecord(raw: .object(["_id": .string("test-title"), "type": .string("movie"), "name": .string("Test title"), "state": .object(["timeOffset": .integer(60_000), "duration": .integer(120_000)])]))
        presentation.dismissed[record.id] = ContinueDismissal(record)
        try store.write(presentation, key: presentationKey)
        let restored = try XCTUnwrap(store.read(presentationKey, as: LibraryPresentation.self))
        XCTAssertTrue(restored.valid)
        XCTAssertEqual(restored.display.sort, .title)
        XCTAssertTrue(try XCTUnwrap(restored.dismissed[record.id]).hides(record))
        XCTAssertNil(try store.read(LibraryPresentation.key(owner: owner + ".other"), as: LibraryPresentation.self))
    }
}
