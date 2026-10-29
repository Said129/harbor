import Darwin
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

enum MusicPlaylistCoverError: Error { case type, size, storage }
struct MusicPlaylistCoverStage: Sendable { let file: URL; let owner: String; let playlist: String }
protocol MusicPlaylistCoverIO: Sendable {
    func stage(_ data: Data, owner: String, playlist: String) async throws -> MusicPlaylistCoverStage
    func image(owner: String, playlist: String, maxPixels: Int) async throws -> DecodedArtworkBitmap?
    func discard(_ stage: MusicPlaylistCoverStage) async
}

actor MusicPlaylistCoverFiles: MusicPlaylistCoverIO {
    nonisolated static func root(_ owner: String, create: Bool) throws -> URL {
        guard !owner.isEmpty, owner.utf8.count <= 512 else { throw MusicPlaylistCoverError.storage }
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: create)
        let directory = base.appendingPathComponent("HarborMusicPlaylistCovers", isDirectory: true).appendingPathComponent(EBookShelf.hash(owner), isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try excluded.setResourceValues(values)
        }
        return directory
    }
    nonisolated static func file(_ owner: String, _ playlist: String, create: Bool = false) throws -> URL {
        guard UUID(uuidString: playlist) != nil else { throw MusicPlaylistCoverError.storage }
        return try root(owner, create: create).appendingPathComponent(playlist.lowercased() + ".png")
    }
    func stage(_ data: Data, owner: String, playlist: String) async throws -> MusicPlaylistCoverStage {
        try Task.checkCancellation()
        guard data.count <= 24 * 1024 * 1024 else { throw MusicPlaylistCoverError.size }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary), let type = CGImageSourceGetType(source) else { throw MusicPlaylistCoverError.type }
        // Photos may return HEIC/HEIF. The five original formats remain accepted.
        let types = Set(["png", "jpg", "webp", "gif", "avif", "heic", "heif"].compactMap { UTType(filenameExtension: $0)?.identifier })
        guard types.contains(type as String) else { throw MusicPlaylistCoverError.type }
        let decoded = try ArtworkBitmapDecoder.decode(data, maxPixels: 900)
        guard let image = decoded.image.cgImage else { throw MusicPlaylistCoverError.type }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else { throw MusicPlaylistCoverError.storage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw MusicPlaylistCoverError.storage }
        try Task.checkCancellation()
        let target = try Self.file(owner, playlist, create: true)
        let staged = target.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".stage")
        do {
            try (encoded as Data).write(to: staged, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try Task.checkCancellation()
            return .init(file: staged, owner: owner, playlist: playlist)
        } catch { try? FileManager.default.removeItem(at: staged); throw error }
    }
    func image(owner: String, playlist: String, maxPixels: Int) async throws -> DecodedArtworkBitmap? {
        try Task.checkCancellation()
        let url = try Self.file(owner, playlist)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try ArtworkBitmapDecoder.decode(Data(contentsOf: url), maxPixels: max(1, min(900, maxPixels)))
    }
    func discard(_ stage: MusicPlaylistCoverStage) async {
        guard let root = try? Self.root(stage.owner, create: false), stage.file.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
              stage.file.lastPathComponent.hasPrefix("."), stage.file.pathExtension == "stage" else { return }
        try? FileManager.default.removeItem(at: stage.file)
    }
}

/// Image decoding and encoding finish off the main actor. Publishing is one
/// atomic rename after checking the current profile and upload generation.
@MainActor @Observable final class MusicPlaylistCoverStore {
    static let shared = MusicPlaylistCoverStore()
    private var versions: [String: UInt64] = [:]
    @ObservationIgnored private var requests: [String: UUID] = [:]
    @ObservationIgnored private let io: any MusicPlaylistCoverIO
    init(io: any MusicPlaylistCoverIO = MusicPlaylistCoverFiles()) { self.io = io }
    private func key(_ owner: String, _ playlist: String) -> String { EBookShelf.hash(owner) + ":" + playlist.lowercased() }
    func revision(owner: String, playlist: String) -> UInt64 { versions[key(owner, playlist), default: 0] }
    func image(owner: String, playlist: String, maxPixels: Int = 480) async throws -> DecodedArtworkBitmap? {
        try await io.image(owner: owner, playlist: playlist, maxPixels: maxPixels)
    }
    func save(_ data: Data, owner: String, playlist: String, allowed: @MainActor @Sendable () -> Bool) async throws {
        guard allowed() else { throw CancellationError() }
        let key = key(owner, playlist), token = UUID(); requests[key] = token
        let staged = try await io.stage(data, owner: owner, playlist: playlist)
        do {
            try Task.checkCancellation()
            guard requests[key] == token, staged.owner == owner, staged.playlist == playlist, allowed() else { throw CancellationError() }
            let target = try MusicPlaylistCoverFiles.file(owner, playlist)
            guard staged.file.deletingLastPathComponent().standardizedFileURL == target.deletingLastPathComponent().standardizedFileURL,
                  staged.file.lastPathComponent.hasPrefix("."), staged.file.pathExtension == "stage" else { throw MusicPlaylistCoverError.storage }
            let result = staged.file.path.withCString { source in target.path.withCString { destination in Darwin.rename(source, destination) } }
            guard result == 0 else { throw MusicPlaylistCoverError.storage }
            versions[key, default: 0] &+= 1
        } catch { await io.discard(staged); throw error }
    }
    func clear(owner: String, playlist: String, allowed: @MainActor @Sendable () -> Bool) throws {
        guard allowed() else { throw CancellationError() }
        let target = try MusicPlaylistCoverFiles.file(owner, playlist), key = key(owner, playlist)
        requests[key] = UUID()
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        versions[key, default: 0] &+= 1
    }
}
