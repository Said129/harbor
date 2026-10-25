import Foundation
import Observation

struct HouseholdRosterAttempt: Codable, Equatable, Sendable {
    let version: UUID
    let baseRevision: Int64
    let value: JSONValue
}

struct HouseholdProfileState: Codable, Equatable, Sendable {
    var version = 1
    var profiles: [DeviceHouseholdProfile] = []
    var selectedID: String?
    var tombstones: [DesktopHouseholdProfile] = []
    var serverValue: JSONValue?
    var serverRevision: Int64?
    var synchronizationAccount: String?
    var rosterAttempt: HouseholdRosterAttempt?
    var sharedSettingsOwner: String?
    var artworkServer: HarborIdentityServer?

    func validated() throws -> Self {
        guard version == 1, Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map(\.syncID)).count == profiles.count,
              profiles.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 256 && !$0.desktop.deleted
                  && ($0.credential?.valid ?? true) && ($0.parentCredential?.valid ?? true)
                  && ($0.localPhotoID.map(ProfilePhotoStore.validDigest) ?? true)
                  && ($0.localPhotoID == nil || $0.appearanceInitialized == true)
                  && [$0.localDataOwner, $0.localProgressOwner, $0.localProgressAccount].allSatisfy({ $0 == nil || (!$0!.isEmpty && $0!.utf8.count <= 512) })
                  && ($0.legacyOwner.map { !$0.isEmpty && $0.utf8.count <= 512 } ?? true) }),
              Set(profiles.compactMap(\.legacyOwner)).count == profiles.compactMap(\.legacyOwner).count,
              Set(profiles.compactMap(\.localDataOwner)).count == profiles.compactMap(\.localDataOwner).count,
              sharedSettingsOwner == nil || (!sharedSettingsOwner!.isEmpty && sharedSettingsOwner!.utf8.count <= 512),
              artworkServer?.retired != true,
              tombstones.count <= 64, tombstones.allSatisfy(\.deleted),
              selectedID == nil || profiles.contains(where: { $0.id == selectedID }),
              serverRevision == nil || (serverRevision! >= 0 && serverRevision! <= 9_007_199_254_740_991),
              synchronizationAccount == nil || (!synchronizationAccount!.isEmpty && synchronizationAccount!.utf8.count <= 256),
              try JSONEncoder().encode(self).count <= 384 * 1_024 else { throw HarborError(code: "household-store") }
        // Revalidate injected persistence implementations as well as decoded data.
        for row in profiles { _ = try DesktopHouseholdProfile(row.desktop.raw) }
        for row in tombstones { _ = try DesktopHouseholdProfile(row.raw) }
        if let serverValue { _ = try DesktopHouseholdRoster(serverValue) }
        if let attempt = rosterAttempt {
            guard synchronizationAccount != nil, serverRevision == attempt.baseRevision,
                  attempt.baseRevision >= 0, attempt.baseRevision <= HarborLayoutDocument.maximumRevision,
                  try DesktopHouseholdRoster(attempt.value).raw == attempt.value else { throw HarborError(code: "household-sync-store") }
        }
        _ = try DesktopHouseholdRoster(wireValue)
        return self
    }
    var wireValue: JSONValue {
        var fields = serverValue?.objectValue ?? [:]
        let liveIDs = Set(profiles.map(\.syncID))
        fields["profiles"] = .array(profiles.map { $0.desktop.portable } + tombstones.filter { !liveIDs.contains($0.syncID) }.map(\.portable))
        return .object(fields)
    }
}

@MainActor protocol HouseholdProfilePersistence {
    func readHousehold(_ key: String) throws -> HouseholdProfileState?
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws
}
@MainActor private struct KeychainHouseholdProfiles: HouseholdProfilePersistence {
    func readHousehold(_ key: String) throws -> HouseholdProfileState? { try KeychainStore().read(key, as: HouseholdProfileState.self) }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws { try KeychainStore().write(value, key: key) }
}

/// One atomic Keychain record owns the roster, routing, selection and device locks.
/// The application must bind its data stores before exposing a selected profile.
@MainActor @Observable final class HouseholdProfileStore {
    let scope: HouseholdProfileScope
    private let persistence: any HouseholdProfilePersistence
    private let credentials: any ProfileCredentialChecking
    private let derivation: any ProfileCredentialDeriving
    private let photos: ProfilePhotoStore
    private(set) var state = HouseholdProfileState()
    private(set) var ready = false
    private(set) var error: String?
    private(set) var verifying = false
    private var generation = 0
    var mutationVersion: Int { generation }
    private var unlocked: Set<String> = []
    private var parentUnlocked: Set<String> = []
    @ObservationIgnored var didCommit: (() -> Void)?
    var profiles: [DeviceHouseholdProfile] { ready ? state.profiles : [] }
    var requestedProfile: DeviceHouseholdProfile? { profiles.first { $0.id == state.selectedID } }
    var active: DeviceHouseholdProfile? {
        guard let profile = requestedProfile, profile.credential == nil || unlocked.contains(profile.id) else { return nil }
        return profile
    }
    func requiresPIN(_ id: String) -> Bool {
        profiles.contains { $0.id == id && $0.credential != nil && !unlocked.contains(id) }
    }
    /// Editing another protected profile must verify its credential without
    /// selecting it or changing the primary editor's permissions.
    @discardableResult func verifyForEditing(_ id: String, password: String) async throws -> Bool {
        guard ready, !verifying, let current = active, current.desktop.isPrimary || current.id == id,
              let target = profiles.first(where: { $0.id == id && !$0.desktop.isKid }),
              let credential = target.credential else { return false }
        verifying = true; let expected = generation
        defer { if expected == generation { verifying = false } }
        guard try await credentials.verifies(password, credential: credential) else { return false }
        try Task.checkCancellation()
        guard generation == expected, profiles.contains(target) else { throw HarborError(code: "profile-selection-changed") }
        unlocked.insert(id); return true
    }
    var needsUpload: Bool { ready && (!profiles.isEmpty || !state.tombstones.isEmpty) && state.wireValue != state.serverValue }

    init(scope: HouseholdProfileScope, persistence: (any HouseholdProfilePersistence)? = nil, credentials: any ProfileCredentialChecking = DeviceProfileCredentialChecker(), derivation: any ProfileCredentialDeriving = DeviceProfileCredentialDeriver(), photos: ProfilePhotoStore? = nil) {
        self.scope = scope; self.persistence = persistence ?? KeychainHouseholdProfiles(); self.credentials = credentials; self.derivation = derivation; self.photos = photos ?? .shared; reload()
    }
    func reload() {
        generation += 1; ready = false; verifying = false; unlocked = []; parentUnlocked = []
        do { state = try (persistence.readHousehold(scope.key) ?? HouseholdProfileState()).validated(); ready = true; error = nil }
        catch { self.error = "Could not load profiles. Saved profiles are kept." }
    }
    private func commit(_ next: HouseholdProfileState) throws {
        guard ready else { throw HarborError(code: "household-unavailable") }
        let value = try next.validated()
        if value != state { try persistence.writeHousehold(value, key: scope.key); state = value; generation += 1; verifying = false; didCommit?() }
        error = nil
    }
    private func requireEdit(_ id: String? = nil) throws {
        guard ready, !verifying else { throw HarborError(code: "household-unavailable") }
        if let current = requestedProfile {
            guard active != nil else { throw HarborError(code: "profile-locked") }
            if current.desktop.isKid && !parentUnlocked.contains(current.id) { throw HarborError(code: "profile-parent-locked") }
        }
        if let id, let target = profiles.first(where: { $0.id == id }) {
            guard target.credential == nil || unlocked.contains(id) else { throw HarborError(code: "profile-locked") }
            guard target.parentCredential == nil || parentUnlocked.contains(id) else { throw HarborError(code: "profile-parent-locked") }
        }
    }
    func bindArtworkServer(_ server: HarborIdentityServer?, account: String) throws {
        guard let server else { return }
        guard ready, scope == .harbor(account: account), !server.retired else { throw HarborError(code: "profile-account-scope") }
        var next = state; next.artworkServer = server; try commit(next)
    }
    /// The context stages private source sessions first. An interrupted activation
    /// can retry this atomic roster install without renaming personal data folders.
    func installDeviceProfiles(_ imported: [DeviceHouseholdProfile], selectedID: String?, sharedOwner: String, account: String) throws {
        guard ready, scope == .harbor(account: account), state.profiles.isEmpty,
              state.serverRevision == nil, state.synchronizationAccount == nil,
              imported.allSatisfy({ $0.legacyOwner == nil && $0.localDataOwner != nil }) else { throw HarborError(code: "household-import-target") }
        var next = state; next.profiles = imported; next.selectedID = selectedID; next.sharedSettingsOwner = sharedOwner
        try commit(next)
    }
    @discardableResult func create(name: String, avatar: String? = nil, color: String = "#7dd3fc", kid: JSONValue = .null, legacyOwner: String? = nil) throws -> DeviceHouseholdProfile {
        try requireEdit()
        let profile = try newProfile(name: name, avatar: avatar, color: color, kid: kid, legacyOwner: legacyOwner)
        var next = state; next.profiles.append(profile)
        if next.selectedID == nil { next.selectedID = profile.id }
        try commit(next); return profile
    }
    private func newProfile(name: String, avatar: String?, color: String, kid: JSONValue, legacyOwner: String? = nil) throws -> DeviceHouseholdProfile {
        guard legacyOwner == nil || profiles.isEmpty else { throw HarborError(code: "profile-migration-target") }
        guard !profiles.isEmpty || kid == .null else { throw HarborError(code: "profile-primary-target") }
        let now = Date().timeIntervalSince1970 * 1_000
        let fields: JSONValue = .object(["syncId": .string("s_" + UUID().uuidString.lowercased()), "name": .string(name),
            "avatar": avatar.map(JSONValue.string) ?? .null, "color": .string(color), "isPrimary": .bool(profiles.isEmpty),
            "kid": kid, "hideContent": .null, "lockedTabs": .null, "settingsLinked": .bool(true),
            "createdAt": .number(now), "updatedAt": .number(now), "deletedAt": .null])
        let desktop = try DesktopHouseholdProfile(fields).editing(["name": .string(name)], at: now)
        return DeviceHouseholdProfile(id: "p_" + UUID().uuidString.lowercased(), desktop: desktop,
            shareStremioWith: profiles.first(where: { $0.desktop.isPrimary })?.id, legacyOwner: legacyOwner,
            appearanceInitialized: legacyOwner == nil ? true : nil)
    }
    /// Commit an editor form, both locks and the initial selection together. A
    /// failed PIN derivation or write cannot leave a newly created profile open.
    @discardableResult func saveEditor(_ draft: HouseholdProfileDraft) async throws -> DeviceHouseholdProfile {
        try requireEdit(draft.original?.id)
        if let original = draft.original {
            guard profiles.contains(original) else { throw HarborError(code: "profile-editor-changed") }
            guard let current = active, current.desktop.isPrimary || current.id == original.id else { throw HarborError(code: "profile-editor-permission") }
            let parentEditing = current.desktop.isKid && parentUnlocked.contains(current.id) && current.id == original.id
            guard !draft.changesAdvancedSettings || current.desktop.isPrimary || parentEditing else { throw HarborError(code: "profile-editor-permission") }
        } else {
            guard profiles.isEmpty || active != nil else { throw HarborError(code: "profile-editor-permission") }
        }
        for change in [draft.pin, draft.parentPIN] {
            if case .set(let pin) = change, !DeviceProfileCredential.validPIN(pin) { throw HarborError(code: "profile-password-format") }
        }
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
              draft.avatar == .null || draft.avatar.string != nil,
              draft.kid != .null || draft.parentPIN == .keep || draft.parentPIN == .remove else { throw HarborError(code: "household-profile-edit") }
        let original = draft.original
        var result: DeviceHouseholdProfile
        if let original { result = original }
        else { result = try newProfile(name: draft.name, avatar: draft.avatar.string, color: draft.color, kid: draft.kid) }
        result.desktop = try result.desktop.editing(draft.portableChanges, at: Date().timeIntervalSince1970 * 1_000)
        if let original, draft.avatar != original.desktop.raw["avatar"] { result.localPhotoID = nil; result.appearanceInitialized = true }
        guard !result.desktop.isPrimary || (draft.sharingWith == nil && !result.desktop.isKid),
              draft.sharingWith == nil || profiles.contains(where: { $0.desktop.isPrimary && $0.id == draft.sharingWith && $0.id != result.id }) else { throw HarborError(code: "profile-sharing-target") }
        result.shareStremioWith = draft.sharingWith
        verifying = true; let expected = generation
        defer { if generation == expected { verifying = false } }
        func credential(_ change: HouseholdProfileDraft.PINChange, previous: DeviceProfileCredential?) async throws -> DeviceProfileCredential? {
            switch change { case .keep: return previous; case .remove: return nil; case .set(let pin): return try await derivation.derive(pin) }
        }
        result.credential = try await credential(draft.pin, previous: original?.credential)
        if result.desktop.isKid { result.parentCredential = try await credential(draft.parentPIN, previous: original?.parentCredential) }
        else { result.parentCredential = nil }
        try Task.checkCancellation()
        guard generation == expected else { throw HarborError(code: "profile-editor-changed") }
        switch draft.photo {
        case .keep: break
        case .remove: result.localPhotoID = nil; result.appearanceInitialized = true
        case .replace(let data, let account):
            result.localPhotoID = try photos.stage(data, account: account); result.appearanceInitialized = true
        }
        var next = state
        if let original {
            guard let index = next.profiles.firstIndex(of: original) else { throw HarborError(code: "profile-editor-changed") }
            next.profiles[index] = result
        } else { next.profiles.append(result); next.selectedID = result.id }
        try commit(next)
        if original == nil || draft.pin != .keep { unlocked.insert(result.id) }
        if original != nil && result.desktop.isKid && draft.parentPIN != .keep { parentUnlocked.insert(result.id) }
        if original == nil { parentUnlocked.remove(result.id) }
        verifying = false
        return result
    }
    func edit(_ id: String, fields: [String: JSONValue]) throws {
        try requireEdit(id)
        guard let index = state.profiles.firstIndex(where: { $0.id == id }), fields["isPrimary"] == nil else { throw HarborError(code: "household-profile-edit") }
        var next = state; next.profiles[index].desktop = try next.profiles[index].desktop.editing(fields, at: Date().timeIntervalSince1970 * 1_000)
        if let avatar = fields["avatar"], avatar != state.profiles[index].desktop.raw["avatar"] {
            next.profiles[index].localPhotoID = nil; next.profiles[index].appearanceInitialized = true
        }
        try commit(next)
    }
    func appearanceOwner(_ profile: DeviceHouseholdProfile) -> String {
        HouseholdProfileRouting(profile: profile, profiles: profiles, scope: scope, cwPerProfile: false).personal
    }
    func initializeAppearance(_ original: DeviceHouseholdProfile, avatar: JSONValue, photoID: String?) throws {
        guard ready, !verifying, original.appearanceInitialized != true, original.localPhotoID == nil else { throw HarborError(code: "profile-appearance-migration") }
        try commitAppearance(original, fields: avatar == original.desktop.raw["avatar"] ? [:] : ["avatar": avatar], photoID: photoID)
    }
    func updateAppearance(_ original: DeviceHouseholdProfile, fields: [String: JSONValue], photoID: String?) throws {
        try requireEdit(original.id)
        guard active?.id == original.id else { throw HarborError(code: "profile-editor-changed") }
        try commitAppearance(original, fields: fields, photoID: photoID)
    }
    /// Called only after the existing Harbor transport has validated its session.
    /// The local migration anchor retains that account's original appearance;
    /// other local people cannot receive an identity from this legacy bridge.
    func adoptIdentityAppearance(_ original: DeviceHouseholdProfile, account: String, fields: [String: JSONValue], photoID: String?) throws {
        guard ready, !verifying, !account.isEmpty, account.utf8.count <= 256 else { throw HarborError(code: "profile-account-scope") }
        switch scope {
        case .harbor(let owner): guard owner == account else { throw HarborError(code: "profile-account-scope") }
        case .local: guard original.legacyOwner != nil else { throw HarborError(code: "profile-account-scope") }
        }
        try commitAppearance(original, fields: fields, photoID: photoID)
    }
    private func commitAppearance(_ original: DeviceHouseholdProfile, fields: [String: JSONValue], photoID: String?) throws {
        guard !original.desktop.isKid, Set(fields.keys).isSubset(of: ["name", "avatar", "color"]),
              photoID.map(ProfilePhotoStore.validDigest) ?? true,
              let index = profiles.firstIndex(of: original) else { throw HarborError(code: "profile-editor-changed") }
        var next = state
        next.profiles[index].desktop = try original.desktop.editing(fields, at: Date().timeIntervalSince1970 * 1_000)
        next.profiles[index].localPhotoID = photoID; next.profiles[index].appearanceInitialized = true
        try commit(next)
    }
    func shareStremio(_ id: String, with sourceID: String?) throws {
        try requireEdit(id)
        guard let index = state.profiles.firstIndex(where: { $0.id == id }), sourceID != id,
              sourceID == nil || profiles.contains(where: { $0.id == sourceID }),
              !state.profiles[index].desktop.isPrimary || sourceID == nil else { throw HarborError(code: "profile-sharing-target") }
        var next = state; next.profiles[index].shareStremioWith = sourceID; try commit(next)
    }
    /// No caller can bypass the gate with a Boolean claiming the PIN was checked.
    @discardableResult func select(_ id: String, password: String? = nil, parentPassword: String? = nil) async throws -> Bool {
        guard ready, !verifying, let target = profiles.first(where: { $0.id == id }) else { throw HarborError(code: "profile-selection") }
        verifying = true; let currentGeneration = generation
        defer { if currentGeneration == generation { verifying = false } }
        let leaving = requestedProfile.flatMap { $0.id != id && $0.desktop.isKid ? $0 : nil }
        if let leaving, let credential = leaving.parentCredential, !parentUnlocked.contains(leaving.id) {
            guard let parentPassword, try await credentials.verifies(parentPassword, credential: credential) else { return false }
        }
        var newlyUnlocked = false
        if let credential = target.credential, !unlocked.contains(id) {
            guard let password, try await credentials.verifies(password, credential: credential) else { return false }
            newlyUnlocked = true
        }
        try Task.checkCancellation()
        guard currentGeneration == generation, profiles.first(where: { $0.id == id }) == target else { throw HarborError(code: "profile-selection-changed") }
        let previousID = state.selectedID
        var next = state; next.selectedID = id
        try commit(next)
        if newlyUnlocked { unlocked.insert(id) }
        if target.desktop.isKid && previousID != id { parentUnlocked.remove(id) }
        verifying = false; return true
    }
    @discardableResult func unlockParent(_ id: String, password: String) async throws -> Bool {
        guard ready, !verifying, let target = profiles.first(where: { $0.id == id }), let credential = target.parentCredential else { return false }
        verifying = true; let currentGeneration = generation
        defer { if currentGeneration == generation { verifying = false } }
        guard try await credentials.verifies(password, credential: credential) else { return false }
        try Task.checkCancellation()
        guard currentGeneration == generation, profiles.first(where: { $0.id == id }) == target else { throw HarborError(code: "profile-selection-changed") }
        parentUnlocked.insert(id); return true
    }
    func setCredential(_ id: String, password: String?, parent: Bool = false) async throws {
        try requireEdit(id)
        guard let target = profiles.first(where: { $0.id == id }), !parent || target.desktop.isKid,
              password == nil || DeviceProfileCredential.validPIN(password!) else { throw HarborError(code: "profile-password-format") }
        verifying = true; let currentGeneration = generation
        defer { if currentGeneration == generation { verifying = false } }
        let credential: DeviceProfileCredential?
        if let password { credential = try await DeviceProfileCredential.create(password) } else { credential = nil }
        try Task.checkCancellation()
        guard currentGeneration == generation, let index = profiles.firstIndex(where: { $0 == target }) else { throw HarborError(code: "profile-selection-changed") }
        var next = state
        if parent { next.profiles[index].parentCredential = credential }
        else { next.profiles[index].credential = credential }
        try commit(next)
        if parent { parentUnlocked.insert(id) } else { unlocked.insert(id) }
        verifying = false
    }
    func lockSession() { generation += 1; unlocked = []; parentUnlocked = []; verifying = false }

    func makePrimary(_ id: String) throws {
        try requireEdit(id)
        guard profiles.contains(where: { $0.id == id && !$0.desktop.isKid }) else { throw HarborError(code: "profile-primary-target") }
        let now = Date().timeIntervalSince1970 * 1_000
        var next = state
        for index in next.profiles.indices {
            let selected = next.profiles[index].id == id
            next.profiles[index].desktop = try next.profiles[index].desktop.editing(["isPrimary": .bool(selected)], at: now)
            if selected { next.profiles[index].shareStremioWith = nil }
        }
        try commit(next)
    }
    /// Data files can be cleaned after this atomic tombstone has been committed.
    func remove(_ id: String) throws {
        try requireEdit(id)
        guard let target = profiles.first(where: { $0.id == id }), !target.desktop.isPrimary else { throw HarborError(code: "profile-delete-target") }
        var fields = target.desktop.raw.objectValue
        let now = Date().timeIntervalSince1970 * 1_000
        fields["deletedAt"] = .number(now); fields["updatedAt"] = .number(now)
        let tombstone = try DesktopHouseholdProfile(.object(fields))
        var next = state; next.profiles.removeAll { $0.id == id }
        next.tombstones = Array((next.tombstones.filter { $0.syncID != tombstone.syncID } + [tombstone]).suffix(64))
        for index in next.profiles.indices where next.profiles[index].shareStremioWith == id { next.profiles[index].shareStremioWith = nil }
        if next.selectedID == id { next.selectedID = next.profiles.first(where: { $0.desktop.isPrimary })?.id ?? next.profiles.first?.id }
        try commit(next); unlocked.remove(id); parentUnlocked.remove(id)
    }

    /// A missing server row is never a deletion. Only explicit tombstones retire it.
    func adopt(_ roster: DesktopHouseholdRoster, revision: Int64, clearingAttempt: Bool = false) throws {
        guard ready, revision >= 0, revision <= 9_007_199_254_740_991,
              state.serverRevision == nil || revision >= state.serverRevision! else { throw HarborError(code: "household-roster-revision") }
        if state.serverRevision == revision {
            guard state.serverValue == roster.raw else { throw HarborError(code: "household-roster-revision") }
            return
        }
        let local = Dictionary(uniqueKeysWithValues: profiles.map { ($0.syncID, $0) })
        // A concurrent remote edit must not resurrect an unacknowledged local delete.
        let locallyDeleted = Set(state.tombstones.map(\.syncID))
        let removed = Set(roster.profiles.filter(\.deleted).map(\.syncID))
        var adopted: [DeviceHouseholdProfile] = []
        for remote in roster.profiles where !remote.deleted && !locallyDeleted.contains(remote.syncID) {
            if var previous = local[remote.syncID] {
                if remote.raw["avatar"] != .null && remote.raw["avatar"] != previous.desktop.raw["avatar"] {
                    previous.localPhotoID = nil; previous.appearanceInitialized = true
                }
                previous.desktop = remote; adopted.append(previous)
            }
            else { adopted.append(DeviceHouseholdProfile(id: "p_" + UUID().uuidString.lowercased(), desktop: remote, appearanceInitialized: true)) }
        }
        let adoptedIDs = Set(adopted.map(\.syncID))
        for var previous in profiles where !adoptedIDs.contains(previous.syncID) && !removed.contains(previous.syncID) {
            if previous.desktop.isPrimary && adopted.contains(where: { $0.desktop.isPrimary }) {
                previous.desktop = try previous.desktop.editing(["isPrimary": .bool(false)], at: Date().timeIntervalSince1970 * 1_000)
            }
            adopted.append(previous)
        }
        let localIDs = Set(adopted.map(\.id))
        for index in adopted.indices where !localIDs.contains(adopted[index].shareStremioWith ?? "") { adopted[index].shareStremioWith = nil }
        var next = state; next.profiles = adopted
        let serverStones = roster.profiles.filter(\.deleted)
        let serverIDs = Set(serverStones.map(\.syncID))
        next.tombstones = Array((serverStones + state.tombstones.filter { !serverIDs.contains($0.syncID) }).suffix(64))
        if !localIDs.contains(next.selectedID ?? "") { next.selectedID = adopted.first(where: { $0.desktop.isPrimary })?.id ?? adopted.first?.id }
        next.serverValue = roster.raw; next.serverRevision = revision
        if clearingAttempt { next.rosterAttempt = nil }
        try commit(next)
        unlocked.formIntersection(localIDs); parentUnlocked.formIntersection(localIDs)
    }
    /// A server account is explicit; a local device roster cannot accidentally be
    /// uploaded while the coordinator is still choosing the household to bind.
    func bindSynchronization(account: String) throws {
        guard ready, case .harbor(let expected) = scope, expected == account,
              !account.isEmpty, account.utf8.count <= 256 else { throw HarborError(code: "household-sync-account") }
        if let bound = state.synchronizationAccount {
            guard bound == account else { throw HarborError(code: "household-sync-account") }; return
        }
        guard state.serverRevision == nil, state.serverValue == nil else { throw HarborError(code: "household-sync-account") }
        var next = state; next.synchronizationAccount = account; try commit(next)
    }
    func noteMissingServerRoster(account: String) throws {
        guard ready, state.synchronizationAccount == account else { throw HarborError(code: "household-sync-account") }
        var next = state
        next.serverRevision = 0; next.serverValue = .object(["profiles": .array([])])
        if next.rosterAttempt?.baseRevision != 0 { next.rosterAttempt = nil }
        try commit(next)
    }
    func prepareRosterAttempt(account: String) throws -> HouseholdRosterAttempt? {
        guard ready, state.synchronizationAccount == account, let revision = state.serverRevision else { throw HarborError(code: "household-sync-unhydrated") }
        if !needsUpload {
            if state.rosterAttempt != nil { var next = state; next.rosterAttempt = nil; try commit(next) }
            return nil
        }
        let value = try DesktopHouseholdRoster(state.wireValue).raw
        if let pending = state.rosterAttempt, pending.baseRevision == revision, pending.value == value { return pending }
        let pending = HouseholdRosterAttempt(version: UUID(), baseRevision: revision, value: value)
        var next = state; next.rosterAttempt = pending; try commit(next); return pending
    }
    func acknowledgeRosterAttempt(_ sent: HouseholdRosterAttempt, revision: Int64, account: String) throws {
        guard ready, state.synchronizationAccount == account, state.rosterAttempt == sent,
              revision > sent.baseRevision, revision <= HarborLayoutDocument.maximumRevision else { throw HarborError(code: "household-sync-response") }
        var next = state
        next.serverValue = sent.value; next.serverRevision = revision; next.rosterAttempt = nil
        // Current profiles may contain an edit made while POST was suspended.
        // Updating only the shadow leaves that edit durably different and queued.
        try commit(next)
    }
}
