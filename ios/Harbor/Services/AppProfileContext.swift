import Foundation
import Observation

struct LegacyProfileConfiguration: Sendable {
    let configuration: HouseholdSourceAccount
    var appearance: MobileProfile? = nil
    var owner: String { configuration.account?.session.user.id ?? "guest" }
}
@MainActor protocol LegacyProfileLoading {
    func loadLegacyProfile() throws -> LegacyProfileConfiguration
}
@MainActor private struct KeychainLegacyProfile: LegacyProfileLoading {
    func loadLegacyProfile() throws -> LegacyProfileConfiguration {
        let keychain = KeychainStore()
        let account = try keychain.read("account.v1", as: SavedAccount.self)
        guard account == nil || account?.version == 1 else { throw HarborError(code: "invalid-account-store") }
        let addons = try keychain.read("addons.v1", as: [Addon].self)
        let owner = account?.session.user.id ?? "guest"
        let appearance = try keychain.read("mobile-profile-" + EBookShelf.hash(owner), as: MobileProfile.self)
        guard appearance?.valid ?? true else { throw HarborError(code: "profile-data") }
        return LegacyProfileConfiguration(configuration: HouseholdSourceAccount(account: account, guestAddons: addons), appearance: appearance)
    }
}

struct ActiveProfileBinding: Equatable, Sendable {
    let profileID: String
    let personalOwner: String
    let settingsOwner: String
    let sharedSettingsOwner: String
    let stremioSourceID: String
    let progressOwner: String
    let identityOwner: String
    let accountID: String?
}

/// Coordinates real account storage and personal data routing. The UI never infers
/// a personal owner from Stremio's user ID: two profiles can share that account.
@MainActor @Observable final class AppProfileContext {
    static let shared = AppProfileContext()
    let profiles: HouseholdProfileStore
    let sessions: HouseholdSessionVault
    let playback = ProfilePlaybackRegistry()
    private let legacy: any LegacyProfileLoading
    private(set) var binding: ActiveProfileBinding?
    private(set) var activationID = UUID()
    private(set) var busy = false
    var requiresSelection: Bool {
        profiles.ready && profiles.active == nil
            && (!profiles.profiles.isEmpty || profiles.state.serverRevision != nil || !profiles.state.tombstones.isEmpty)
    }
    var ready: Bool {
        guard profiles.ready, sessions.ready, let binding, let active = profiles.active, active.id == binding.profileID else { return false }
        let source = active.shareStremioWith.flatMap { id in profiles.profiles.contains(where: { $0.id == id }) ? id : nil } ?? active.id
        return binding.stremioSourceID == source
            && binding.settingsOwner == (active.desktop.settingsLinked ? sharedSettingsOwner(identityOwner: binding.identityOwner) : binding.personalOwner)
    }
    var configuration: HouseholdSourceAccount? { ready ? sessions.current : nil }

    init(profiles: HouseholdProfileStore? = nil, sessions: HouseholdSessionVault? = nil, legacy: (any LegacyProfileLoading)? = nil) {
        self.profiles = profiles ?? HouseholdProfileStore(scope: .local(owner: "device-v1"))
        self.sessions = sessions ?? HouseholdSessionVault()
        self.legacy = legacy ?? KeychainLegacyProfile()
    }
    func prepare() throws {
        guard profiles.ready, sessions.ready else { throw HarborError(code: "household-unavailable") }
        let mayMigrateLegacy: Bool
        switch profiles.scope { case .local: mayMigrateLegacy = true; case .harbor: mayMigrateLegacy = false }
        guard mayMigrateLegacy || profiles.profiles.allSatisfy({ $0.legacyOwner == nil }) else { throw HarborError(code: "profile-account-migration") }
        var loadedLegacy: LegacyProfileConfiguration?
        if profiles.profiles.isEmpty && profiles.state.tombstones.isEmpty && profiles.state.serverRevision == nil {
            guard mayMigrateLegacy else { try refreshBinding(); return }
            let previous = try legacy.loadLegacyProfile()
            loadedLegacy = previous
            let appearance = previous.appearance
            let name = appearance?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = previous.configuration.account?.session.user.fullname?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = name.flatMap { $0.isEmpty ? nil : $0 } ?? fallback.flatMap { $0.isEmpty ? nil : $0 } ?? "Guest \(Int.random(in: 1000...9999))"
            _ = try profiles.create(name: title, avatar: "/avatars/\(appearance?.avatar ?? "harbor_animal_01").webp",
                                    color: "#" + (appearance?.color ?? "7dd3fc"), legacyOwner: previous.owner)
        }
        // Recover a failed first copy without creating another profile or claiming
        // a different account. Once claimed, legacy account.v1 is never read again.
        for profile in profiles.profiles where profile.legacyOwner != nil {
            if try sessions.needsLegacyMigration(profile, scope: profiles.scope) {
                guard mayMigrateLegacy else { throw HarborError(code: "profile-account-migration") }
                let previous: LegacyProfileConfiguration
                if let loadedLegacy { previous = loadedLegacy } else { previous = try legacy.loadLegacyProfile() }
                guard previous.owner == profile.legacyOwner,
                      try sessions.migrateLegacy(previous.configuration, to: profile, scope: profiles.scope) else { throw HarborError(code: "profile-account-migration") }
            }
        }
        if sessions.identityOwner == nil, let original = profiles.profiles.first(where: { $0.legacyOwner != nil }) {
            try sessions.preserveIdentityOwner(from: original, scope: profiles.scope)
        }
        try refreshBinding()
    }
    private func sharedSettingsOwner(identityOwner: String) -> String {
        switch profiles.scope {
        case .local: identityOwner
        case .harbor: "settings-shared-" + profiles.scope.key
        }
    }
    private func refreshBinding() throws {
        guard let profile = profiles.active else {
            sessions.unbind()
            if binding != nil { playback.stopForProfileChange(); activationID = UUID() }
            binding = nil; return
        }
        let lease = try sessions.bind(profile: profile, profiles: profiles.profiles, scope: profiles.scope)
        let routing = HouseholdProfileRouting(profile: profile, profiles: profiles.profiles, scope: profiles.scope, cwPerProfile: false)
        let identityOwner = sessions.identityOwner ?? profiles.profiles.compactMap(\.legacyOwner).first ?? "identity-" + profiles.scope.key
        let sharedOwner = sharedSettingsOwner(identityOwner: identityOwner)
        let accountID = lease.configuration?.account?.session.user.id
        let source = profiles.profiles.first { $0.id == routing.stremioSourceID }
        let progressOwner: String
        if let old = source?.legacyOwner, old == (accountID ?? "guest") { progressOwner = old }
        else { progressOwner = "source-progress-" + HouseholdProfileScope.hash([profiles.scope.key, routing.stremioSourceID, accountID ?? "guest"]) }
        let next = ActiveProfileBinding(profileID: profile.id, personalOwner: routing.personal,
            settingsOwner: profile.desktop.settingsLinked ? sharedOwner : routing.personal, sharedSettingsOwner: sharedOwner,
            stremioSourceID: routing.stremioSourceID, progressOwner: progressOwner,
            identityOwner: identityOwner, accountID: accountID)
        if binding != next { playback.stopForProfileChange(); activationID = UUID(); binding = next }
    }
    /// Addon ordering/configuration and source refresh intentionally affect profiles
    /// sharing Stremio. Explicit sign-in/out instead prepares and detaches this one.
    func save(_ configuration: HouseholdSourceAccount, explicitAuthenticationChange: Bool = false) throws {
        guard !busy, ready, let profile = profiles.active else { throw HarborError(code: "profile-account-scope") }
        let lease = try sessions.bind(profile: profile, profiles: profiles.profiles, scope: profiles.scope)
        if explicitAuthenticationChange && profile.shareStremioWith != nil {
            try sessions.prepareOwnAccount(configuration, profile: profile, profiles: profiles.profiles, scope: profiles.scope, using: lease)
            try profiles.shareStremio(profile.id, with: nil)
        } else { try sessions.save(configuration, using: lease) }
        try refreshBinding()
    }
    @discardableResult func select(_ id: String, password: String? = nil, parentPassword: String? = nil) async throws -> Bool {
        guard !busy else { throw HarborError(code: "profile-selection") }
        busy = true; defer { busy = false }
        guard try await profiles.select(id, password: password, parentPassword: parentPassword) else { return false }
        try refreshBinding(); return true
    }
    func refreshRouting() throws { try refreshBinding() }
    func reload() {
        playback.stopForProfileChange(); profiles.reload(); sessions.reload(); binding = nil; activationID = UUID()
    }
}
