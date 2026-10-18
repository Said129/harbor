import Foundation
import CryptoKit
import ImageIO
import Observation
import UIKit

/// Local-only immutable image payload. The household record commits its digest
/// after this payload is durable; neither image nor account marker enters wire JSON.
struct ProfilePhotoRecord: Codable, Equatable, Sendable {
    var version = 1
    let photo: Data
    let account: String?
    func validated() throws -> Self {
        guard version == 1, !photo.isEmpty, photo.count <= 512 * 1_024,
              account.map({ !$0.isEmpty && $0.utf8.count <= 512 }) ?? true,
              let source = CGImageSourceCreateWithData(photo as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber,
              width.intValue > 0, width.intValue <= 1_024, height.intValue > 0, height.intValue <= 1_024,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw HarborError(code: "profile-photo") }
        return self
    }
}
@MainActor protocol ProfilePhotoPersistence {
    func readPhoto(_ digest: String) throws -> Data?
    func writePhoto(_ data: Data, digest: String) throws
}
@MainActor private struct KeychainProfilePhotos: ProfilePhotoPersistence {
    func readPhoto(_ digest: String) throws -> Data? { try KeychainStore().read("profile-photo-" + digest, as: Data.self) }
    func writePhoto(_ data: Data, digest: String) throws { try KeychainStore().write(data, key: "profile-photo-" + digest) }
}
@MainActor @Observable final class ProfilePhotoStore {
    static let shared = ProfilePhotoStore()
    private let persistence: any ProfilePhotoPersistence
    private var cache: [String: ProfilePhotoRecord] = [:]
    init(persistence: (any ProfilePhotoPersistence)? = nil) { self.persistence = persistence ?? KeychainProfilePhotos() }
    static func normalized(_ data: Data) throws -> Data {
        guard data.count <= 20 * 1_024 * 1_024, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 384, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85), jpeg.count <= 512 * 1_024 else { throw HarborError(code: "profile-photo") }
        return jpeg
    }
    func cachedPhoto(_ digest: String) -> ProfilePhotoRecord? { cache[digest] }
    nonisolated static func validDigest(_ digest: String) -> Bool { digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }
    private func decode(_ data: Data, digest: String) throws -> ProfilePhotoRecord {
        guard data.count <= 768 * 1_024, Self.digest(data) == digest else { throw HarborError(code: "profile-photo-store") }
        return try JSONDecoder().decode(ProfilePhotoRecord.self, from: data).validated()
    }
    private nonisolated static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func photo(_ digest: String) throws -> ProfilePhotoRecord {
        guard Self.validDigest(digest) else { throw HarborError(code: "profile-photo-store") }
        if let value = cache[digest] { return value }
        guard let data = try persistence.readPhoto(digest) else { throw HarborError(code: "profile-photo-store") }
        let value = try decode(data, digest: digest); cache[digest] = value; return value
    }
    func stage(_ photo: Data, account: String?) throws -> String {
        let value = try ProfilePhotoRecord(photo: photo, account: account).validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(value), digest = Self.digest(data)
        if let cached = cache[digest] { guard cached == value else { throw HarborError(code: "profile-photo-store") }; return digest }
        if let previous = try persistence.readPhoto(digest) {
            guard try decode(previous, digest: digest) == value else { throw HarborError(code: "profile-photo-store") }
        } else { try persistence.writePhoto(data, digest: digest) }
        cache[digest] = value; return digest
    }
}
