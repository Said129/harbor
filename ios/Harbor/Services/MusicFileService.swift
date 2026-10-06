import CryptoKit
import Darwin
import Foundation
import Libmpv
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

actor MusicFileService {
    static let shared = MusicFileService()
    private let core = CoreBridge()
    static let extensions: Set<String> = ["flac", "mp3", "m4a", "aac", "ogg", "opus", "wav", "wv"]
    nonisolated static func validFilename(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), extensions.contains(String(name[name.index(after: dot)...])) else { return false }
        let stem = name[..<dot]
        return stem.count == 64 && stem.allSatisfy { "0123456789abcdef".contains($0) }
    }
    nonisolated static func root(owner: String) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = base.appendingPathComponent("HarborMusic", isDirectory: true).appendingPathComponent(EBookShelf.hash(owner), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var protected = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        return root
    }
    nonisolated static func file(_ record: MusicRecord, owner: String) throws -> URL {
        guard validFilename(record.filename) else { throw HarborError(code: "music-file") }
        let url = try root(owner: owner).appendingPathComponent(record.filename)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw HarborError(code: "music-file") }
        return url
    }
    func importFile(_ input: URL, owner: String) async throws -> MusicImport {
        let access = input.startAccessingSecurityScopedResource()
        defer { if access { input.stopAccessingSecurityScopedResource() } }
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        let ext = input.pathExtension.lowercased()
        guard extensions.contains(ext), values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 512 * 1024 * 1024 else { throw HarborError(code: "music-file") }
        let root = try Self.root(owner: owner)
        let owned = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        guard owned.count < 1_000 else { throw HarborError(code: "music-capacity") }
        let used = try owned.reduce(Int64(0)) { try $0 + Int64($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        guard used + Int64(size) <= 4 * 1024 * 1024 * 1024 else { throw HarborError(code: "music-capacity") }
        let staging = root.appendingPathComponent("." + UUID().uuidString + ".import")
        defer { try? FileManager.default.removeItem(at: staging) }
        guard FileManager.default.createFile(atPath: staging.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw HarborError(code: "music-file") }
        let reader = try FileHandle(forReadingFrom: input), writer = try FileHandle(forWritingTo: staging)
        defer { try? reader.close(); try? writer.close() }
        var hash = SHA256(); var copied = 0
        while let bytes = try reader.read(upToCount: 1024 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            copied += bytes.count
            guard copied <= size else { throw HarborError(code: "music-file") }
            hash.update(data: bytes); try writer.write(contentsOf: bytes)
        }
        guard copied == size else { throw HarborError(code: "music-file") }
        try writer.synchronize(); try writer.close()
        let filename = hash.finalize().map { String(format: "%02x", $0) }.joined() + "." + ext
        let final = root.appendingPathComponent(filename)
        let created = !FileManager.default.fileExists(atPath: final.path)
        if created { try FileManager.default.moveItem(at: staging, to: final) }
        do {
            let tags = try await MusicProbe.inspect(final, filename: input.lastPathComponent, sourceID: filename)
            let local: LocalMusic = try await core.call("musicLocalTrack", ["tags": try .encoded(tags)])
            var record = MusicRecord(local: local, filename: filename, originalName: input.lastPathComponent, size: Int64(size), importedAt: Date())
            if let artwork = await MusicArtworkLoader.load(final) {
                let name = String(filename.prefix(64)) + ".jpg"
                let destination = root.appendingPathComponent(name)
                do {
                    try artwork.write(to: destination, options: .atomic)
                    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
                    record.cover = name
                } catch { /* A cover failure must not discard playable audio. */ }
            }
            return MusicImport(record: record, createdFile: created)
        } catch {
            if created { try? FileManager.default.removeItem(at: final) }
            throw error
        }
    }
    func artwork(_ record: MusicRecord, owner: String) throws -> Data? {
        guard let name = record.cover, Self.validCover(name) else { return nil }
        let url = try Self.root(owner: owner).appendingPathComponent(name)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 1024 * 1024 else { return nil }
        return try Data(contentsOf: url)
    }
    nonisolated private static func validCover(_ name: String) -> Bool {
        name.count == 68 && name.hasSuffix(".jpg") && name.prefix(64).allSatisfy { "0123456789abcdef".contains($0) }
    }
    func remove(_ record: MusicRecord, owner: String) throws {
        try FileManager.default.removeItem(at: Self.file(record, owner: owner))
        if let name = record.cover, Self.validCover(name) { try? FileManager.default.removeItem(at: Self.root(owner: owner).appendingPathComponent(name)) }
    }
}

private enum MusicArtworkLoader {
    // AVFoundation objects stay within this nonisolated task; only bounded Data
    // returns to the file-service actor. No unchecked Sendable conformance.
    static func load(_ url: URL) async -> Data? {
        do {
            let asset = AVURLAsset(url: url)
            let metadata = try await asset.load(.commonMetadata)
            guard let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }),
                  let data = try await item.load(.dataValue), data.count <= 12 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 600] as CFDictionary) else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(destination), output.length <= 1024 * 1024 else { return nil }
            return output as Data
        } catch { return nil }
    }
}

private struct MusicTags: Encodable, Sendable {
    let sourceId: String
    let filename: String
    let title: String?
    let artist: String?
    let album: String?
    let albumArtist: String?
    let trackNo: UInt32?
    let discNo: UInt32?
    let year: UInt32?
    let durationSeconds: UInt64
}

private enum MusicProbe {
    static func inspect(_ url: URL, filename: String, sourceID: String) async throws -> MusicTags {
        guard let handle = mpv_create() else { throw HarborError(code: "music-file") }
        defer { mpv_terminate_destroy(handle) }
        for (name, value) in [("config", "no"), ("terminal", "no"), ("msg-level", "all=no"), ("vo", "null"), ("ao", "null"), ("vid", "no"), ("audio-display", "no"), ("pause", "yes"), ("access-references", "no")] {
            guard mpv_set_option_string(handle, name, value) >= 0 else { throw HarborError(code: "music-file") }
        }
        guard mpv_initialize(handle) >= 0 else { throw HarborError(code: "music-file") }
        try MusicMPV.command(handle, ["loadfile", url.path, "replace"])
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            try Task.checkCancellation()
            for _ in 0..<32 {
                guard let event = mpv_wait_event(handle, 0)?.pointee, event.event_id != MPV_EVENT_NONE else { break }
                if event.event_id == MPV_EVENT_FILE_LOADED {
                    guard MusicMPV.hasAudio(handle) else { throw HarborError(code: "music-file") }
                    let metadata = MusicMPV.metadata(handle)
                    var duration = 0.0
                    let status = mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &duration)
                    guard status < 0 || (duration.isFinite && duration >= 0 && duration <= 31_536_000) else { throw HarborError(code: "music-file") }
                    let number: (String?) -> UInt32? = { $0.flatMap { UInt32($0.split(separator: "/").first.map(String.init) ?? "") } }
                    return MusicTags(sourceId: sourceID, filename: filename, title: metadata["title"], artist: metadata["artist"], album: metadata["album"], albumArtist: metadata["album_artist"] ?? metadata["albumartist"], trackNo: number(metadata["track"]), discNo: number(metadata["disc"]), year: number(metadata["date"].map { String($0.prefix(4)) } ?? metadata["year"]), durationSeconds: status < 0 ? 0 : UInt64(duration))
                }
                if event.event_id == MPV_EVENT_END_FILE { throw HarborError(code: "music-file") }
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw HarborError(code: "music-file")
    }
}

enum MusicMPV {
    static func command(_ handle: OpaquePointer, _ values: [String]) throws {
        let allocations = values.map { strdup($0) }
        defer { allocations.forEach { free($0) } }
        guard allocations.allSatisfy({ $0 != nil }) else { throw HarborError(code: "music-player") }
        var pointers: [UnsafePointer<CChar>?] = allocations.map { $0.map { UnsafePointer<CChar>($0) } } + [nil]
        guard mpv_command_async(handle, 0, &pointers) >= 0 else { throw HarborError(code: "music-player") }
    }
    static func metadata(_ handle: OpaquePointer) -> [String: String] {
        var node = mpv_node()
        guard mpv_get_property(handle, "metadata", MPV_FORMAT_NODE, &node) >= 0 else { return [:] }
        defer { mpv_free_node_contents(&node) }
        guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list, let keys = list.pointee.keys, let values = list.pointee.values else { return [:] }
        var result: [String: String] = [:]
        for index in 0..<min(Int(list.pointee.num), 128) {
            guard let key = keys[index], values[index].format == MPV_FORMAT_STRING, let raw = values[index].u.string else { continue }
            let name = String(cString: key).lowercased(), text = String(cString: raw)
            if text.utf8.count <= 4_096 { result[name] = text }
        }
        return result
    }
    static func hasAudio(_ handle: OpaquePointer) -> Bool {
        var node = mpv_node()
        guard mpv_get_property(handle, "track-list", MPV_FORMAT_NODE, &node) >= 0 else { return false }
        defer { mpv_free_node_contents(&node) }
        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list, let values = list.pointee.values else { return false }
        for index in 0..<min(Int(list.pointee.num), 128) {
            let item = values[index]
            guard item.format == MPV_FORMAT_NODE_MAP, let fields = item.u.list, let keys = fields.pointee.keys, let values = fields.pointee.values else { continue }
            for field in 0..<min(Int(fields.pointee.num), 64) {
                if let key = keys[field], String(cString: key) == "type", values[field].format == MPV_FORMAT_STRING,
                   let type = values[field].u.string, String(cString: type) == "audio" { return true }
            }
        }
        return false
    }
}
