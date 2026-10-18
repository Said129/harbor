import Foundation
import Observation

/// Projects the authoritative roster identity into the existing appearance UI.
/// Image reads are cached; rendering never opens Keychain records.
@MainActor @Observable final class HouseholdAppearanceBinding {
    private let profiles: HouseholdProfileStore
    private let profileID: String
    private let owner: String
    private let photos: ProfilePhotoStore
    private(set) var error: String?
    private var profile: DeviceHouseholdProfile? { profiles.profiles.first { $0.id == profileID && !$0.desktop.isKid } }
    var exists: Bool { profile != nil }
    var needsLegacyAppearance: Bool { profile?.appearanceInitialized != true }
    var ready: Bool {
        guard error == nil, let profile, profiles.appearanceOwner(profile) == owner, profile.appearanceInitialized == true else { return false }
        return profile.localPhotoID == nil || photos.cachedPhoto(profile.localPhotoID!) != nil
    }
    init(profiles: HouseholdProfileStore, profileID: String, owner: String, photos: ProfilePhotoStore) {
        self.profiles = profiles; self.profileID = profileID; self.owner = owner; self.photos = photos
    }
    func matches(_ profiles: HouseholdProfileStore, id: String) -> Bool { self.profiles === profiles && profileID == id }
    var value: MobileProfile {
        guard let profile, profiles.appearanceOwner(profile) == owner else { return MobileProfile() }
        return Self.project(name: profile.desktop.name, color: profile.desktop.raw["color"].string,
                            avatar: profile.desktop.raw["avatar"], photo: profile.localPhotoID.flatMap(photos.cachedPhoto))
    }
    static func project(name: String, color: String?, avatar: JSONValue, photo: ProfilePhotoRecord? = nil) -> MobileProfile {
        var result = MobileProfile()
        result.name = name
        let hex = color?.replacingOccurrences(of: "#", with: "") ?? ""
        if hex.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) != nil { result.color = hex }
        if let photo {
            result.photo = photo.photo; result.photoAccountID = photo.account; result.initialsAvatar = false
        } else if let raw = avatar.string {
            let id = String(raw.split(separator: "/").last?.split(separator: ".").first ?? "")
            if DesktopHouseholdProfile.portableAvatar(.string(raw)) != .null {
                if DesktopAvatar.catalog.contains(where: { $0.id == id }) { result.avatar = id }
                else { result.remoteAvatar = "https://harbor.site" + raw }
            }
            else if Self.remoteAvatar(raw) { result.remoteAvatar = raw }
            else { result.initialsAvatar = true }
        } else { result.initialsAvatar = true }
        return result
    }
    func reload(legacy: MobileProfile?, legacyReady: Bool) {
        do {
            guard var profile, profiles.appearanceOwner(profile) == owner else { throw HarborError(code: "profile-account-scope") }
            if profile.appearanceInitialized != true {
                guard legacyReady else { throw HarborError(code: "profile-appearance-migration") }
                var avatar = profile.desktop.raw["avatar"], digest: String?
                if let photo = legacy?.photo { digest = try photos.stage(photo, account: legacy?.photoAccountID); avatar = .null }
                else if let remote = legacy?.remoteAvatar, Self.remoteAvatar(remote) { avatar = .string(remote) }
                else if legacy?.initialsAvatar == true { avatar = .null }
                try profiles.initializeAppearance(profile, avatar: avatar, photoID: digest)
                guard let initialized = self.profile else { throw HarborError(code: "profile-account-scope") }; profile = initialized
            }
            if let digest = profile.localPhotoID { _ = try photos.photo(digest) }
            error = nil
        } catch { self.error = "No se pudo recuperar la imagen del perfil. Los datos guardados se conservan." }
    }
    func update(_ next: MobileProfile) throws {
        guard ready, let profile, profiles.active?.id == profile.id,
              profiles.appearanceOwner(profile) == owner, next.valid else { throw HarborError(code: "profile-editor-changed") }
        let previous = value
        let avatar = try Self.avatar(next)
        var fields: [String: JSONValue] = [:]
        if next.name != previous.name { fields["name"] = .string(next.name) }
        if next.color != previous.color { fields["color"] = .string("#" + next.color) }
        if avatar != (try Self.avatar(previous)) { fields["avatar"] = avatar }
        let digest = try next.photo.map { try photos.stage($0, account: next.photoAccountID) }
        do { try profiles.updateAppearance(profile, fields: fields, photoID: digest); error = nil }
        catch { self.error = "No se pudo guardar el perfil. Los datos anteriores se conservan."; throw error }
    }
    func adopt(_ next: MobileProfile, avatar: JSONValue, account: String) throws {
        guard ready, let profile, next.valid, profiles.appearanceOwner(profile) == owner else { throw HarborError(code: "profile-account-scope") }
        let digest = try next.photo.map { try photos.stage($0, account: next.photoAccountID) }
        let fields: [String: JSONValue] = ["name": .string(next.name), "color": .string("#" + next.color), "avatar": DesktopHouseholdProfile.portableAvatar(avatar)]
        try profiles.adoptIdentityAppearance(profile, account: account, fields: fields, photoID: digest)
        error = nil
    }
    private static func avatar(_ value: MobileProfile) throws -> JSONValue {
        if value.photo != nil || value.initialsAvatar == true { return .null }
        if let remote = value.remoteAvatar {
            guard remoteAvatar(remote) else { throw HarborError(code: "profile-data") }; return .string(remote)
        }
        return .string("/avatars/\(value.avatar).webp")
    }
    static func remoteAvatar(_ value: String) -> Bool {
        guard value.utf8.count <= 8_192, let parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil else { return false }
        return true
    }
}
