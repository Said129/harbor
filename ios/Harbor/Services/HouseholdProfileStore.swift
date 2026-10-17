import Foundation
import Observation

struct HouseholdProfileState: Codable, Equatable, Sendable {
    var version = 1
    var profiles: [DeviceHouseholdProfile] = []
    var selectedID: String?
    var tombstones: [DesktopHouseholdProfile] = []
    var serverValue: JSONValue?
    var serverRevision: Int64?

    func validated() throws -> Self {
        guard version == 1, Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map(\.syncID)).count == profiles.count,
              profiles.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 256 && !$0.desktop.deleted
                  && ($0.credential?.valid ?? true) && ($0.parentCredential?.valid ?? true)
                  && ($0.legacyOwner.map { !$0.isEmpty && $0.utf8.count <= 512 } ?? true) }),
              Set(profiles.compactMap(\.legacyOwner)).count == profiles.compactMap(\.legacyOwner).count,
              tombstones.count <= 64, tombstones.allSatisfy(\.deleted),
              selectedID == nil || profiles.contains(where: { $0.id == selectedID }),
              serverRevision == nil || (serverRevision! >= 0 && serverRevision! <= 9_007_199_254_740_991),
              try JSONEncoder().encode(self).count <= 384 * 1_024 else { throw HarborError(code: "household-store") }
        // Revalidate injected persistence implementations as well as decoded data.
        for row in profiles { _ = try DesktopHouseholdProfile(row.desktop.raw) }
        for row in tombstones { _ = try DesktopHouseholdProfile(row.raw) }
        if let serverValue { _ = try DesktopHouseholdRoster(serverValue) }
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
    private(set) var state = HouseholdProfileState()
    private(set) var ready = false
    private(set) var error: String?
    private(set) var verifying = false
    private var generation = 0
    private var unlocked: Set<String> = []
    private var parentUnlocked: Set<String> = []
    var profiles: [DeviceHouseholdProfile] { ready ? state.profiles : [] }
    var requestedProfile: DeviceHouseholdProfile? { profiles.first { $0.id == state.selectedID } }
    var active: DeviceHouseholdProfile? {
        guard let profile = requestedProfile, profile.credential == nil || unlocked.contains(profile.id) else { return nil }
        return profile
    }
    var needsUpload: Bool { ready && !profiles.isEmpty && state.wireValue != state.serverValue }

    init(scope: HouseholdProfileScope, persistence: (any HouseholdProfilePersistence)? = nil, credentials: any ProfileCredentialChecking = DeviceProfileCredentialChecker()) {
        self.scope = scope; self.persistence = persistence ?? KeychainHouseholdProfiles(); self.credentials = credentials; reload()
    }
    func reload() {
        generation += 1; ready = false; verifying = false; unlocked = []; parentUnlocked = []
        do { state = try (persistence.readHousehold(scope.key) ?? HouseholdProfileState()).validated(); ready = true; error = nil }
        catch { self.error = "Could not load profiles. Saved profiles are kept." }
    }
    private func commit(_ next: HouseholdProfileState) throws {
        guard ready else { throw HarborError(code: "household-unavailable") }
        let value = try next.validated()
        if value != state { try persistence.writeHousehold(value, key: scope.key); state = value; generation += 1; verifying = false }
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
    @discardableResult func create(name: String, avatar: String? = nil, color: String = "#7dd3fc", kid: JSONValue = .null, legacyOwner: String? = nil) throws -> DeviceHouseholdProfile {
        try requireEdit()
        guard legacyOwner == nil || profiles.isEmpty else { throw HarborError(code: "profile-migration-target") }
        guard !profiles.isEmpty || kid == .null else { throw HarborError(code: "profile-primary-target") }
        let now = Date().timeIntervalSince1970 * 1_000
        let fields: JSONValue = .object(["syncId": .string("s_" + UUID().uuidString.lowercased()), "name": .string(name),
            "avatar": avatar.map(JSONValue.string) ?? .null, "color": .string(color), "isPrimary": .bool(profiles.isEmpty),
            "kid": kid, "hideContent": .null, "lockedTabs": .null, "settingsLinked": .bool(true),
            "createdAt": .number(now), "updatedAt": .number(now), "deletedAt": .null])
        let desktop = try DesktopHouseholdProfile(fields).editing(["name": .string(name)], at: now)
        let profile = DeviceHouseholdProfile(id: "p_" + UUID().uuidString.lowercased(), desktop: desktop,
            shareStremioWith: profiles.first(where: { $0.desktop.isPrimary })?.id, legacyOwner: legacyOwner)
        var next = state; next.profiles.append(profile)
        if next.selectedID == nil { next.selectedID = profile.id }
        try commit(next); return profile
    }
    func edit(_ id: String, fields: [String: JSONValue]) throws {
        try requireEdit(id)
        guard let index = state.profiles.firstIndex(where: { $0.id == id }), fields["isPrimary"] == nil else { throw HarborError(code: "household-profile-edit") }
        var next = state; next.profiles[index].desktop = try next.profiles[index].desktop.editing(fields, at: Date().timeIntervalSince1970 * 1_000)
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
    func adopt(_ roster: DesktopHouseholdRoster, revision: Int64) throws {
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
            if var previous = local[remote.syncID] { previous.desktop = remote; adopted.append(previous) }
            else { adopted.append(DeviceHouseholdProfile(id: "p_" + UUID().uuidString.lowercased(), desktop: remote)) }
        }
        let adoptedIDs = Set(adopted.map(\.syncID))
        for var previous in profiles where !adoptedIDs.contains(previous.syncID) && !removed.contains(previous.syncID) {
            if state.serverRevision == nil && previous.desktop.isPrimary && adopted.contains(where: { $0.desktop.isPrimary }) {
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
        try commit(next)
        unlocked.formIntersection(localIDs); parentUnlocked.formIntersection(localIDs)
    }
}
