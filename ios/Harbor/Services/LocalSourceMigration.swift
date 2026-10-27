import Foundation

/// Contains configuration and non-secret ownership aliases, never an account
/// session. The alias keeps files from earlier IPAs readable in the same profile.
struct LocalSourceArchive: Codable, Sendable {
    let owner: String
    var collection: AccountCollection
    var previousGuestAddons: [Addon]? = nil
    var valid: Bool { !owner.isEmpty && owner.utf8.count <= 1_024 }
}

actor LocalSourceMigration {
    private let cache: LibraryCache
    private let queue: LibraryWriteQueue
    init(cache: LibraryCache = .init(), queue: LibraryWriteQueue = .init()) { self.cache = cache; self.queue = queue }
    func prepare(_ owner: String) async throws {
        let saved = try await cache.read(owner: owner), pending = try await queue.pending(owner: owner)
        try await cache.save(LibraryWriteQueue.merging(saved, pending: pending), owner: owner)
        try await queue.retire(pending, owner: owner)
    }
}

@MainActor protocol LegacySourceRetirementPersistence {
    func readLegacy() throws -> SavedAccount?
    func archive(_ value: LocalSourceArchive) throws
    func removeLegacySession() throws
}

@MainActor struct KeychainLegacySourceRetirement: LegacySourceRetirementPersistence {
    var legacyKey = "account.v1"
    var archivePrefix = "native-local-source-archive-v1-"
    func readLegacy() throws -> SavedAccount? { try KeychainStore().read(legacyKey, as: SavedAccount.self) }
    func archive(_ value: LocalSourceArchive) throws { try KeychainStore().write(value, key: archivePrefix + EBookShelf.hash(value.owner)) }
    func removeLegacySession() throws { try KeychainStore().remove(legacyKey) }
}

@MainActor enum LegacySourceRetirement {
    static func run(_ supplied: (any LegacySourceRetirementPersistence)? = nil) throws {
        let persistence = supplied ?? KeychainLegacySourceRetirement()
        guard let account = try persistence.readLegacy() else { return }
        guard account.version == 1 else { throw HarborError(code: "invalid-account-store") }
        let archive = LocalSourceArchive(owner: account.session.user.id, collection: account.collection)
        guard archive.valid else { throw HarborError(code: "profile-account-migration") }
        try persistence.archive(archive)
        try persistence.removeLegacySession()
    }
}
