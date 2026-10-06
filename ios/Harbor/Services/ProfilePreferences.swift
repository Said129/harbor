import SwiftUI
import Observation
import ImageIO

struct DesktopAvatar: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let asset: String
    static let catalog: [DesktopAvatar] = {
        struct Document: Decodable { let avatars: [DesktopAvatar] }
        return Bundle.main.url(forResource: "DesktopAvatars", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Document.self, from: $0).avatars } ?? []
    }()
}

struct MobileProfile: Codable, Sendable {
    var name = ""
    var avatar = "harbor_animal_01"
    var color = "7dd3fc"
    var photo: Data?
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
    private init(owner: String) {
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
            try KeychainStore().write(next, key: key); value = next; error = nil
        } catch { self.error = "No se pudo guardar el perfil. Los datos anteriores se conservan." }
    }
    func setPhoto(_ data: Data) throws {
        guard data.count <= 20 * 1_024 * 1_024, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 384, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85), jpeg.count <= 512 * 1_024 else { throw HarborError(code: "profile-photo") }
        update { $0.photo = jpeg }
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
            else { Image(DesktopAvatar.catalog.first { $0.id == profile.value.avatar }?.asset ?? "avatar-harbor_animal_01").resizable().scaledToFill() }
        }.frame(width: size, height: size).clipShape(.circle).overlay { Circle().stroke(profile.color, lineWidth: 2) }.accessibilityHidden(true)
    }
}
