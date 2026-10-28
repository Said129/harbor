import CryptoKit
import Foundation
import ZIPFoundation

actor SpooktoberWorldResources {
    static let shared = SpooktoberWorldResources()
    static let scheme = "harbor-spook"
    static let entry = URL(string: "harbor-spook://world/index.html")!
    struct Resource: Sendable { let data: Data; let mime: String }
    private struct Manifest: Decodable {
        struct File: Decodable { let bytes: Int; let sha256: String }
        let schema: Int
        let reference: String
        let files: [String: File]
        let zip_sha256: String
    }
    private var archive: Archive?
    private var manifest: Manifest?
    private var cache: [String: Resource] = [:]
    nonisolated static func path(_ url: URL) -> String? {
        guard url.scheme == scheme, url.host == "world", url.user == nil, url.password == nil, url.port == nil,
              url.path.utf8.count <= 512, !url.path.contains("\\"), !url.path.contains("\0") else { return nil }
        let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(".."), !components.contains(".") else { return nil }
        return components.joined(separator: "/")
    }
    nonisolated static func imagePath(_ value: String) -> String? {
        guard let url = URL(string: value), let path = path(url), path.hasPrefix("spooktober/assets/"),
              ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased()) else { return nil }; return path
    }
    func resource(_ path: String) throws -> Resource {
        if let saved = cache[path] { return saved }
        if ["native-fonts/Inter.ttf", "native-fonts/Fraunces.ttf"].contains(path) {
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf") else { throw HarborError(code: "spooktober-font") }
            return Resource(data: try Data(contentsOf: url, options: .mappedIfSafe), mime: "font/ttf")
        }
        if archive == nil {
            guard let metadata = Bundle.main.url(forResource: "SpooktoberWorldAssets", withExtension: "json"),
                  let package = Bundle.main.url(forResource: "SpooktoberWorld", withExtension: "zip") else { throw HarborError(code: "spooktober-assets") }
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: metadata))
            let bytes = try Data(contentsOf: package, options: .mappedIfSafe)
            guard manifest.schema == 1, manifest.reference == "0834340cec5531650bfe78cd628628702e636987", manifest.files.count == 99,
                  bytes.count <= 8 * 1024 * 1024, Self.hash(bytes) == manifest.zip_sha256,
                  manifest.zip_sha256 == "8e3b9e510fd67769cd4bb5891606a4abecbf59b3412dcaf3b00809f16263e684" else { throw HarborError(code: "spooktober-assets") }
            archive = try Archive(data: bytes, accessMode: .read); self.manifest = manifest
        }
        guard let archive, let expected = manifest?.files[path], let entry = archive[path],
              entry.type == .file, expected.bytes >= 0, entry.uncompressedSize == UInt64(expected.bytes),
              expected.bytes <= 2 * 1024 * 1024 else { throw HarborError(code: "spooktober-resource") }
        var data = Data(); data.reserveCapacity(expected.bytes)
        let crc = try archive.extract(entry) { chunk in
            guard data.count + chunk.count <= expected.bytes else { throw HarborError(code: "spooktober-resource") }; data.append(chunk)
        }
        guard crc == entry.checksum, data.count == expected.bytes, Self.hash(data) == expected.sha256 else { throw HarborError(code: "spooktober-resource") }
        let result = Resource(data: data, mime: Self.mime(path))
        cache[path] = result; return result
    }
    nonisolated private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    nonisolated private static func mime(_ path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "html": "text/html"; case "js": "application/javascript"; case "css": "text/css"; case "json": "application/json"
        case "svg": "image/svg+xml"; case "png": "image/png"; case "webp": "image/webp"; case "jpg", "jpeg": "image/jpeg"
        default: "application/octet-stream"
        }
    }
}
