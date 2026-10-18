import Foundation

/// Editor-only values. The UI clears plain PINs when the form closes;
/// persistence receives only the derived device credential.
struct HouseholdProfileDraft: Sendable {
    enum PINChange: Equatable, Sendable { case keep, remove, set(String) }
    enum PhotoChange: Equatable, Sendable { case keep, remove, replace(Data, account: String?) }
    let original: DeviceHouseholdProfile?
    var name: String
    var avatar: JSONValue
    var color: String
    var kid: JSONValue
    var hideContent: JSONValue
    var lockedTabs: JSONValue
    var settingsLinked: Bool
    var sharingWith: String?
    var pin: PINChange = .keep
    var parentPIN: PINChange = .keep
    var photo: PhotoChange = .keep

    init(profile: DeviceHouseholdProfile) {
        original = profile; name = profile.desktop.name; avatar = profile.desktop.raw["avatar"]
        color = profile.desktop.raw["color"].string ?? "#7dd3fc"; kid = profile.desktop.raw["kid"]
        hideContent = profile.desktop.raw["hideContent"]; lockedTabs = profile.desktop.raw["lockedTabs"]
        settingsLinked = profile.desktop.settingsLinked; sharingWith = profile.shareStremioWith
    }
    init(name: String = "", sharingWith: String? = nil) {
        original = nil; self.name = name; self.sharingWith = sharingWith
        avatar = .null; color = "#7dd3fc"; kid = .null; hideContent = .null; lockedTabs = .null; settingsLinked = true
    }
    var portableChanges: [String: JSONValue] {
        var fields: [String: JSONValue] = ["name": .string(name), "avatar": avatar, "color": .string(color),
            "kid": kid, "hideContent": hideContent, "lockedTabs": lockedTabs, "settingsLinked": .bool(settingsLinked)]
        if case .replace = photo { fields["avatar"] = .null }
        if let original {
            fields = fields.filter { key, value in
                if key == "settingsLinked" { return settingsLinked != original.desktop.settingsLinked }
                return value != original.desktop.raw[key]
            }
        }
        return fields
    }
    var changesAdvancedSettings: Bool {
        guard let original else { return true }
        return kid != original.desktop.raw["kid"] || hideContent != original.desktop.raw["hideContent"]
            || lockedTabs != original.desktop.raw["lockedTabs"] || settingsLinked != original.desktop.settingsLinked
            || sharingWith != original.shareStremioWith || pin != .keep || parentPIN != .keep
    }
}
