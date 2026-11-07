import Foundation
import Observation

/// The OMDb, MDBList and TheIntroDB keys of one profile, kept in the Keychain (Desktop's `omdbKey`, `mdblistKey` and `theIntroDbKey` settings).
@MainActor @Observable final class ProviderKeyStore {
    enum Provider: String, CaseIterable, Sendable { case omdb, mdblist, theIntroDb = "theintrodb" }

    private static var stores: [String: ProviderKeyStore] = [:]
    static func forOwner(_ owner: String) -> ProviderKeyStore {
        if let saved = stores[owner] { return saved }
        let store = ProviderKeyStore(owner: owner); stores[owner] = store; return store
    }

    let owner: String
    private(set) var keys: [String: String] = [:]
    private(set) var ready = false

    init(owner: String) { self.owner = owner }

    private func storageKey() throws -> String {
        guard !owner.isEmpty, owner.utf8.count <= 1_024 else { throw HarborError(code: "provider-keys-profile") }
        return "native-provider-keys-v1-" + EBookShelf.hash(owner)
    }

    func load() throws {
        keys = try KeychainStore().read(storageKey(), as: [String: String].self) ?? [:]
        ready = true
    }

    func key(_ provider: Provider) -> String { keys[provider.rawValue] ?? "" }

    /// An empty value removes the key. Keys are short single-line tokens.
    func set(_ value: String, for provider: Provider) throws {
        guard ready else { throw HarborError(code: "provider-keys-unavailable") }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 256, !trimmed.contains(where: \.isNewline) else { throw HarborError(code: "provider-key-invalid") }
        var next = keys
        next[provider.rawValue] = trimmed.isEmpty ? nil : trimmed
        // Commit before announcing: a failed Keychain write leaves the last saved keys in place.
        let key = try storageKey()
        if next.isEmpty { try KeychainStore().remove(key) } else { try KeychainStore().write(next, key: key) }
        keys = next
    }
}
