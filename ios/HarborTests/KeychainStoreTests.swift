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
    }
}
