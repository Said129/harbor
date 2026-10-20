import CryptoKit
import Foundation

protocol HarborPluginSecrets: Sendable {
    func read(plugin: String, revision: String) async throws -> [String: String]
    func stage(plugin: String, values: [String: String]) async throws -> String
    func remove(plugin: String, revision: String) async throws
}

/// Immutable revisions let the catalog select a committed configuration atomically.
/// Staging a revision never overwrites the credentials of the installed version.
actor HarborPluginSecretVault: HarborPluginSecrets {
    private let namespace: String
    private let keychain = KeychainStore()
    init(namespace: String) { self.namespace = namespace }

    func read(plugin: String, revision: String) throws -> [String: String] {
        guard let values = try keychain.read(key(plugin, revision), as: [String: String].self) else {
            throw HarborPluginRepositoryError("plugin-secrets-missing")
        }
        return values
    }
    func stage(plugin: String, values: [String: String]) throws -> String {
        let revision = UUID().uuidString
        try keychain.write(values, key: key(plugin, revision))
        return revision
    }
    func remove(plugin: String, revision: String) throws { try keychain.remove(key(plugin, revision)) }

    private func key(_ plugin: String, _ revision: String) throws -> String {
        guard !namespace.isEmpty, !plugin.isEmpty, !revision.isEmpty else { throw HarborPluginRepositoryError("plugin-secrets-identity") }
        let data = try JSONEncoder().encode([namespace, plugin, revision])
        return "plugin-secret-v1-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
