import Foundation
import Security

struct KeychainStore {
    private let service = "site.harbor.iphone"
    func read<T: Decodable>(_ key: String, as: T.Type) throws -> T? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw HarborError(code: "keychain-read-\(status)") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func write<T: Encodable>(_ value: T, key: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = base(key)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(insertion as CFDictionary, nil)
            guard added == errSecSuccess else { throw HarborError(code: "keychain-write-\(added)") }
        } else if status != errSecSuccess { throw HarborError(code: "keychain-write-\(status)") }
    }

    private func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
}
