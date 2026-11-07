import Foundation
import Observation

/// The RPDB and Fanart.tv keys of one profile, kept in the Keychain (Desktop's `rpdbKey` and `fanartKey` settings).
@MainActor @Observable final class ArtworkKeyStore {
    enum Provider: String, CaseIterable, Sendable { case rpdb, fanart }

    private static var stores: [String: ArtworkKeyStore] = [:]
    static func forOwner(_ owner: String) -> ArtworkKeyStore {
        if let saved = stores[owner] { return saved }
        let store = ArtworkKeyStore(owner: owner); stores[owner] = store; return store
    }

    let owner: String
    private(set) var keys: [String: String] = [:]
    private(set) var ready = false

    init(owner: String) { self.owner = owner }

    private func storageKey() throws -> String {
        guard !owner.isEmpty, owner.utf8.count <= 1_024 else { throw HarborError(code: "artwork-keys-profile") }
        return "native-artwork-keys-v1-" + EBookShelf.hash(owner)
    }

    func load() throws {
        keys = try KeychainStore().read(storageKey(), as: [String: String].self) ?? [:]
        ready = true
    }

    func key(_ provider: Provider) -> String { keys[provider.rawValue] ?? "" }

    /// An empty value removes the key. Keys are short single-line tokens.
    func set(_ value: String, for provider: Provider) throws {
        guard ready else { throw HarborError(code: "artwork-keys-unavailable") }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 256, !trimmed.contains(where: \.isNewline) else { throw HarborError(code: "artwork-key-invalid") }
        var next = keys
        next[provider.rawValue] = trimmed.isEmpty ? nil : trimmed
        // Commit before announcing: a failed Keychain write leaves the last saved keys in place.
        let key = try storageKey()
        if next.isEmpty { try KeychainStore().remove(key) } else { try KeychainStore().write(next, key: key) }
        keys = next
    }
}
