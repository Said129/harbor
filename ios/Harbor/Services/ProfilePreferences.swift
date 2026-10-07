import SwiftUI
import Observation
import ImageIO

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

@MainActor @Observable
final class ProfilePreferences {
    private static var profiles: [String: ProfilePreferences] = [:]
    static func forOwner(_ owner: String) -> ProfilePreferences {
        if let profile = profiles[owner] { return profile }
        let profile = ProfilePreferences(owner: owner); profiles[owner] = profile; return profile
    }
    static let colors = ["7dd3fc", "60a5fa", "a78bfa", "f472b6", "fb7185", "fb923c", "fbbf24", "a3e635", "34d399", "22d3ee"]
    private(set) var value = MobileProfile()
    private(set) var ready = false
    var error: String?
    private let key: String
    private let owner: String
    var cloud: HarborProfileSync { HarborProfileSync.forOwner(owner, profile: self) }
    private init(owner: String) {
        self.owner = owner
        key = "mobile-profile-" + EBookShelf.hash(owner)
        reload()
    }
    func reload() {
        do {
            let profile = try KeychainStore().read(key, as: MobileProfile.self) ?? MobileProfile()
            guard profile.valid else { throw HarborError(code: "profile-data") }
            value = profile; ready = true; error = nil
        } catch { ready = false; self.error = "No se pudo recuperar este perfil. Los datos guardados se conservan." }
    }
    func update(_ edit: (inout MobileProfile) -> Void) {
        guard ready else { return }
        var next = value; edit(&next)
        do {
            guard next.valid else { throw HarborError(code: "profile-data") }
            let previous = value
            try KeychainStore().write(next, key: key); value = next; error = nil
            cloud.enqueue(before: previous, after: next)
        } catch { self.error = "No se pudo guardar el perfil. Los datos anteriores se conservan." }
    }
    func adopt(_ wire: JSONValue, accountID: String) throws {
        guard ready, let name = wire["name"].string else { throw HarborError(code: "profile-data") }
        var next = value; next.name = String(name.prefix(32))
        if next.photo != nil, next.photoAccountID != accountID {
            try KeychainStore().write(value, key: key + "-before-harbor")
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
        try KeychainStore().write(next, key: key); value = next; error = nil
    }
    func setPhoto(_ data: Data) throws {
        guard data.count <= 20 * 1_024 * 1_024, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 384, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85), jpeg.count <= 512 * 1_024 else { throw HarborError(code: "profile-photo") }
        update { $0.photo = jpeg; $0.photoAccountID = cloud.accountID; $0.remoteAvatar = nil; $0.initialsAvatar = false }
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
    var body: some View {
        Group {
            if let data = profile.value.photo, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else if let remote = profile.value.remoteAvatar { Artwork(url: remote, maxPixels: 384) }
            else if profile.value.initialsAvatar == true { Text(String(profile.value.name.prefix(1))).font(HarborTheme.displayFont(size * 0.45)).frame(maxWidth: .infinity, maxHeight: .infinity).background(HarborTheme.surface) }
            else { Image(DesktopAvatar.catalog.first { $0.id == profile.value.avatar }?.asset ?? "avatar-harbor_animal_01").resizable().scaledToFill() }
        }.frame(width: size, height: size).clipShape(.circle).overlay { Circle().stroke(profile.color, lineWidth: 2) }.accessibilityHidden(true)
    }
}
