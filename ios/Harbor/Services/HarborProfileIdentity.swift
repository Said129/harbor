import Foundation

@MainActor protocol HarborIdentityMigrationPersistence {
    func readIdentity(_ key: String) throws -> JSONValue?
    func writeIdentity(_ value: JSONValue, key: String) throws
}
@MainActor private struct KeychainIdentityMigration: HarborIdentityMigrationPersistence {
    func readIdentity(_ key: String) throws -> JSONValue? { try KeychainStore().read(key, as: JSONValue.self) }
    func writeIdentity(_ value: JSONValue, key: String) throws { try KeychainStore().write(value, key: key) }
}

/// Authentication belongs to the person, independently of shared settings and
/// Stremio routing. The alias survives an authenticated household activation.
enum HarborProfileIdentity {
    static let unboundOwner = "harbor-profile-unbound"
    static func owner(_ profile: DeviceHouseholdProfile, scope: HouseholdProfileScope) -> String {
        profile.localIdentityOwner ?? "harbor-profile-" + HouseholdProfileScope.hash([scope.key, profile.id])
    }
    static func validOwner(_ owner: String) -> Bool {
        owner.range(of: "^harbor-profile-[0-9a-f]{64}$", options: .regularExpression) != nil
    }
    static func key(_ owner: String) -> String { "harbor-identity-" + EBookShelf.hash(owner) }
    static func claimKey(_ legacyOwner: String) -> String { "harbor-profile-identity-claim-" + EBookShelf.hash(legacyOwner) }

    @MainActor static func migrateLegacy(context: AppProfileContext,
        persistence: (any HarborIdentityMigrationPersistence)? = nil) throws -> Bool {
        guard context.ready, let active = context.profiles.active, active.desktop.isPrimary, !active.desktop.isKid,
              let legacyOwner = context.binding?.identityOwner else { return false }
        let target = owner(active, scope: context.profiles.scope), storage = persistence ?? KeychainIdentityMigration()
        let destination = key(target), claim = claimKey(legacyOwner)
        let existing = try storage.readIdentity(destination)
        if let existing { _ = try HarborProfileSync.identityRecordAccount(existing) }
        if let record = try storage.readIdentity(claim) {
            guard let destinationOwner = record.string, validOwner(destinationOwner) else {
                if existing != nil { return false }
                throw HarborError(code: "profile-identity-migration")
            }
            if destinationOwner != target { return false }
        }
        guard let previous = try storage.readIdentity(key(legacyOwner)) else { return false }
        let account: String?
        do { account = try HarborProfileSync.identityRecordAccount(previous) }
        catch { if existing != nil { return false }; throw error }
        if case .harbor(let household) = context.profiles.scope, let account, account != household { return false }
        // Claim before copying: a failed copy can retry only for this original
        // destination. Explicit login/logout records always beat legacy state.
        if try storage.readIdentity(claim) == nil { try storage.writeIdentity(.string(target), key: claim) }
        guard existing == nil else { return false }
        try storage.writeIdentity(previous, key: destination)
        return true
    }
}
