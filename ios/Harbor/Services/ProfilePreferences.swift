import SwiftUI
import Observation

struct DesktopAvatar: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let asset: String
    let group: String?
    static let catalog: [DesktopAvatar] = {
        struct Document: Decodable { let avatars: [DesktopAvatar] }
        return Bundle.main.url(forResource: "DesktopAvatars", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Document.self, from: $0).avatars } ?? []
    }()
    static var groups: [String] {
        var seen = Set<String>()
        return catalog.compactMap(\.group).filter { seen.insert($0).inserted }
    }
}

struct MobileProfile: Codable, Sendable {
    var name = ""
    var avatar = "harbor_animal_01"
    var color = "7dd3fc"
    var photo: Data?
    var remoteAvatar: String?
    var initialsAvatar: Bool?
    var photoAccountID: String?
    var valid: Bool {
        name.utf8.count <= 256 && DesktopAvatar.catalog.contains { $0.id == avatar }
            && color.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) != nil
            && (photo?.count ?? 0) <= 512 * 1_024
    }
}

@MainActor protocol ProfileAppearancePersistence {
    func readAppearance(_ key: String) throws -> MobileProfile?
    func writeAppearance(_ value: MobileProfile, key: String) throws
}
@MainActor private struct KeychainProfileAppearance: ProfileAppearancePersistence {
    func readAppearance(_ key: String) throws -> MobileProfile? { try KeychainStore().read(key, as: MobileProfile.self) }
    func writeAppearance(_ value: MobileProfile, key: String) throws { try KeychainStore().write(value, key: key) }
}

@MainActor @Observable
final class ProfilePreferences {
    private static var profiles: [String: ProfilePreferences] = [:]
    static func forOwner(_ owner: String) -> ProfilePreferences {
        if let profile = profiles[owner] { return profile }
        let profile = ProfilePreferences(owner: owner); profiles[owner] = profile; return profile
    }
    static let colors = ["7dd3fc", "60a5fa", "a78bfa", "f472b6", "fb7185", "fb923c", "fbbf24", "a3e635", "34d399", "22d3ee"]
    private var legacyValue = MobileProfile()
    private var legacyReady = false
    private var legacyError: String?
    private var household: HouseholdAppearanceBinding?
    private var binding: HouseholdAppearanceBinding? { household?.exists == true ? household : nil }
    var value: MobileProfile { binding?.value ?? legacyValue }
    var ready: Bool { binding?.ready ?? legacyReady }
    var error: String? { binding?.error ?? legacyError }
    private let key: String
    private let owner: String
    private let persistence: any ProfileAppearancePersistence
    private let photos: ProfilePhotoStore
    private let didChange: ((MobileProfile, MobileProfile) -> Void)?
    var cloud: HarborProfileSync { HarborProfileSync.forOwner(owner, profile: self) }
    init(owner: String, persistence: (any ProfileAppearancePersistence)? = nil, photos: ProfilePhotoStore? = nil, didChange: ((MobileProfile, MobileProfile) -> Void)? = nil) {
        self.owner = owner
        self.persistence = persistence ?? KeychainProfileAppearance(); self.photos = photos ?? .shared
        self.didChange = didChange
        key = "mobile-profile-" + EBookShelf.hash(owner)
        reload()
    }
    func bindHousehold(_ profiles: HouseholdProfileStore, id: String) {
        if household?.matches(profiles, id: id) != true {
            household = HouseholdAppearanceBinding(profiles: profiles, profileID: id, owner: owner, photos: photos)
        }
        household?.reload(legacy: legacyValue, legacyReady: legacyReady)
        if household?.ready == true { legacyError = nil }
    }
    func reload() {
        if let binding {
            if binding.needsLegacyAppearance && !legacyReady { reloadLegacy() }
            binding.reload(legacy: legacyValue, legacyReady: legacyReady)
            if binding.ready { legacyError = nil }; return
        }
        reloadLegacy()
    }
    private func reloadLegacy() {
        do {
            let profile = try persistence.readAppearance(key) ?? MobileProfile()
            guard profile.valid else { throw HarborError(code: "profile-data") }
            legacyValue = profile; legacyReady = true; legacyError = nil
        } catch { legacyReady = false; legacyError = "No se pudo recuperar este perfil. Los datos guardados se conservan." }
    }
    func update(_ edit: (inout MobileProfile) -> Void) {
        guard ready else { return }
        var next = value; edit(&next)
        do { try persist(next) }
        catch { legacyError = "No se pudo guardar el perfil. Los datos anteriores se conservan." }
    }
    private func persist(_ next: MobileProfile) throws {
        guard ready, next.valid else { throw HarborError(code: "profile-data") }
        let previous = value
        if let binding { try binding.update(next); legacyValue = binding.value }
        else { try persistence.writeAppearance(next, key: key); legacyValue = next }
        legacyReady = true; legacyError = nil
        if let didChange { didChange(previous, value) } else { cloud.enqueue(before: previous, after: value) }
    }
    func adopt(_ wire: JSONValue, accountID: String) throws {
        guard ready, let name = wire["name"].string else { throw HarborError(code: "profile-data") }
        var next = value; next.name = String(name.prefix(32))
        if next.photo != nil, next.photoAccountID != accountID {
            try persistence.writeAppearance(value, key: key + "-before-harbor")
            next.photo = nil
        }
        let hex = (wire["color"].string ?? "").replacingOccurrences(of: "#", with: "")
        if hex.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) != nil { next.color = hex }
        next.remoteAvatar = nil; next.initialsAvatar = false
        if let path = wire["avatar"].string, path.hasPrefix("/avatars/") || path.hasPrefix("/kids/avatars/") {
            let id = String(path.split(separator: "/").last?.split(separator: ".").first ?? "")
            if DesktopAvatar.catalog.contains(where: { $0.id == id }) { next.avatar = id; next.photo = nil }
            else if path.count <= 512, !path.contains(".."), let url = URL(string: "https://harbor.site" + path), url.host == "harbor.site" { next.remoteAvatar = url.absoluteString; next.photo = nil }
        } else if next.photo == nil { next.initialsAvatar = true }
        guard next.valid else { throw HarborError(code: "profile-data") }
        if let binding { try binding.adopt(next, avatar: wire["avatar"], account: accountID); legacyValue = binding.value }
        else { try persistence.writeAppearance(next, key: key); legacyValue = next }
        legacyReady = true; legacyError = nil
    }
    func setPhoto(_ data: Data) throws {
        var next = value
        next.photo = try ProfilePhotoStore.normalized(data); next.photoAccountID = cloud.accountID
        next.remoteAvatar = nil; next.initialsAvatar = false
        do { try persist(next) }
        catch { legacyError = "No se pudo guardar el perfil. Los datos anteriores se conservan."; throw error }
    }
    var color: Color { Self.color(value.color) }
    static func color(_ hex: String) -> Color {
        let number = UInt32(hex, radix: 16) ?? 0x7dd3fc
        return Color(.sRGB, red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255, opacity: 1)
    }
    func setColor(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        update { $0.color = String(format: "%02x%02x%02x", Int(red * 255), Int(green * 255), Int(blue * 255)) }
    }
}

struct ProfileAvatar: View {
    let profile: ProfilePreferences
    var size: CGFloat = 72
    var body: some View { MobileProfileAvatar(value: profile.value, size: size) }
}

struct MobileProfileAvatar: View {
    let value: MobileProfile
    var size: CGFloat = 72
    var body: some View {
        Group {
            if let data = value.photo, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else if let remote = value.remoteAvatar { Artwork(url: remote, maxPixels: 384) }
            else if value.initialsAvatar == true { Text(String(value.name.prefix(1))).font(HarborTheme.displayFont(size * 0.45)).frame(maxWidth: .infinity, maxHeight: .infinity).background(HarborTheme.surface) }
            else { Image(DesktopAvatar.catalog.first { $0.id == value.avatar }?.asset ?? "avatar-harbor_animal_01").resizable().scaledToFill() }
        }.frame(width: size, height: size).clipShape(.circle).overlay { Circle().stroke(ProfilePreferences.color(value.color), lineWidth: 2) }.accessibilityHidden(true)
    }
}
