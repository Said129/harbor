import Foundation

/// Portable Desktop fields and device credentials have separate representations.
struct DesktopHouseholdProfile: Codable, Equatable, Sendable {
    private(set) var raw: JSONValue
    var syncID: String { raw["syncId"].string ?? "" }
    var name: String { raw["name"].string ?? "" }
    var isPrimary: Bool { raw["isPrimary"] == .bool(true) }
    var deleted: Bool { raw["deletedAt"] != .null }
    var settingsLinked: Bool { raw["settingsLinked"] != .bool(false) }
    var isKid: Bool { if case .object = raw["kid"] { return true }; return false }
    var age: Int? { raw["kid"]["age"].numericValue.flatMap { Int(exactly: $0) } }
    var curfewMinutes: Int? { raw["kid"]["curfewMinutes"].numericValue.flatMap { Int(exactly: $0) } }

    init(_ input: JSONValue) throws {
        guard case .object(var fields) = input,
              let id = fields["syncId"]?.string, !id.isEmpty, id.utf8.count <= 256,
              let name = fields["name"]?.string, name.utf8.count <= 1_024,
              try JSONEncoder().encode(input).count <= 96 * 1_024 else { throw HarborError(code: "household-profile-value") }
        for key in ["isPrimary", "settingsLinked"] {
            if let value = fields[key], case .bool = value { continue }
            guard fields[key] == nil else { throw HarborError(code: "household-profile-value") }
        }
        for key in ["createdAt", "updatedAt", "deletedAt"] {
            if let value = fields[key], value != .null {
                guard let number = value.numericValue, number.isFinite, number >= 0 else { throw HarborError(code: "household-profile-value") }
            }
        }
        if let kid = fields["kid"], kid != .null {
            guard case .object(var details) = kid else { throw HarborError(code: "household-profile-value") }
            if let value = details["age"] {
                guard let age = value.numericValue, age.isFinite, age >= 0, age <= 18, age.rounded() == age else { throw HarborError(code: "household-profile-value") }
            }
            if let value = details["curfewMinutes"], value != .null {
                guard let minutes = value.numericValue, minutes.isFinite, minutes > 0, minutes <= 1_440, minutes.rounded() == minutes else { throw HarborError(code: "household-profile-value") }
            }
            details.removeValue(forKey: "parentPinHash")
            fields["kid"] = .object(details)
        }
        for key in ["id", "passwordHash", "shareStremioWith"] { fields.removeValue(forKey: key) }
        // JSON decoding normalizes integral numbers. Use the same representation
        // before persistence and POST comparison so an acknowledged write is not
        // mistaken for another local edit after a restart.
        raw = try JSONValue.encoded(JSONValue.object(fields))
    }
    init(from decoder: Decoder) throws { try self.init(JSONValue(from: decoder)) }
    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }

    func editing(_ patch: [String: JSONValue], at milliseconds: Double) throws -> Self {
        let editable: Set<String> = ["name", "avatar", "color", "isPrimary", "kid", "hideContent", "lockedTabs", "settingsLinked"]
        guard Set(patch.keys).isSubset(of: editable), milliseconds.isFinite, milliseconds >= 0 else { throw HarborError(code: "household-profile-edit") }
        var fields = raw.objectValue
        for (key, value) in patch { fields[key] = value }
        if let name = patch["name"]?.string {
            let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
            guard !trimmed.isEmpty else { throw HarborError(code: "household-profile-edit") }
            fields["name"] = .string(trimmed)
        }
        // No-op reads and edits retain the timestamp; otherwise every pull re-uploads.
        if .object(fields) != raw { fields["updatedAt"] = .number(milliseconds) }
        return try Self(.object(fields))
    }

    static func portableAvatar(_ input: JSONValue) -> JSONValue {
        guard let path = input.string, path.utf8.count <= 512, !path.contains(".."), !path.contains("\\"),
              path.hasPrefix("/avatars/") || path.hasPrefix("/kids/avatars/"),
              let parts = URLComponents(string: path), parts.scheme == nil, parts.host == nil,
              parts.query == nil, parts.fragment == nil else { return .null }
        return .string(path)
    }

    var portable: JSONValue {
        var fields = raw.objectValue; fields["avatar"] = Self.portableAvatar(raw["avatar"])
        return .object(fields)
    }
}

struct DesktopHouseholdRoster: Equatable, Sendable {
    let profiles: [DesktopHouseholdProfile]
    let raw: JSONValue
    init(_ input: JSONValue) throws {
        guard case .object(var fields) = input, case .array(let rows) = input["profiles"],
              try JSONEncoder().encode(input).count <= 96 * 1_024 else { throw HarborError(code: "household-roster-value") }
        let profiles = try rows.map(DesktopHouseholdProfile.init)
        guard Set(profiles.map(\.syncID)).count == profiles.count else { throw HarborError(code: "household-roster-value") }
        fields["profiles"] = .array(profiles.map(\.portable))
        self.profiles = profiles; raw = try JSONValue.encoded(JSONValue.object(fields))
    }
}

struct DeviceHouseholdProfile: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var desktop: DesktopHouseholdProfile
    var shareStremioWith: String?
    var credential: DeviceProfileCredential?
    var parentCredential: DeviceProfileCredential?
    /// Set only for an explicit, transactional migration of an existing iOS owner.
    var legacyOwner: String?
    var localPhotoID: String? = nil
    var appearanceInitialized: Bool? = nil
    /// One-time native import aliases are device-local and never part of desktop.raw.
    var localDataOwner: String? = nil
    var localProgressOwner: String? = nil
    var localProgressAccount: String? = nil
    var syncID: String { desktop.syncID }
}

enum HouseholdProfileScope: Equatable, Sendable {
    case local(owner: String)
    case harbor(account: String)
    var key: String {
        let parts: [String]
        switch self { case .local(let owner): parts = ["local", owner]; case .harbor(let account): parts = ["harbor", account] }
        return "native-household-" + Self.hash(parts)
    }
    static func hash(_ parts: [String]) -> String {
        EBookShelf.hash(String(decoding: try! JSONEncoder().encode(parts), as: UTF8.self))
    }
}

struct HouseholdProfileRouting: Equatable, Sendable {
    let personal: String
    let settings: String
    let stremioSourceID: String
    let continuing: String
    let privateContinuing: Bool
    init(profile: DeviceHouseholdProfile, profiles: [DeviceHouseholdProfile], scope: HouseholdProfileScope, cwPerProfile: Bool) {
        func source(_ row: DeviceHouseholdProfile) -> String {
            profiles.contains { $0.id == row.shareStremioWith } ? row.shareStremioWith! : row.id
        }
        // Existing iOS shelves, favourites and trackers keep their namespace. Only
        // the explicitly migrated profile can hold this device-local alias.
        personal = profile.localDataOwner ?? profile.legacyOwner ?? "profile-" + HouseholdProfileScope.hash([scope.key, profile.id])
        settings = profile.desktop.settingsLinked ? "settings-shared-" + scope.key : personal
        let sourceID = source(profile)
        let isPrivate = cwPerProfile && profiles.contains { $0.id != profile.id && source($0) == sourceID }
        stremioSourceID = sourceID; privateContinuing = isPrivate
        let sourceOwner = profiles.first(where: { $0.id == sourceID })?.legacyOwner
        continuing = isPrivate ? personal : sourceOwner ?? "continuing-" + HouseholdProfileScope.hash([scope.key, sourceID])
    }
}
