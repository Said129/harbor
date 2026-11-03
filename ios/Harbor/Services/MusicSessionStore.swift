import Foundation

struct MusicSessionSnapshot: Sendable {
    let revision: UUID
    let queue: [MusicTrack]
    let current: MusicTrack
    let origin: MusicQueueOrigin?
    let position: Double
    let savedAt: Date

    // Desktop also permits an unknown duration, but never resumes at the end.
    static func usablePosition(_ position: Double, duration: Double) -> Double {
        guard position.isFinite, position > 0 else { return 0 }
        return !duration.isFinite || duration <= 0 || position < duration - 2 ? position : 0
    }
}

protocol MusicSessionPersisting: Sendable {
    func read(owner: String) async throws -> MusicSessionSnapshot?
    func write(_ value: MusicSessionSnapshot, owner: String) async throws
}

/// Queue bytes change only with membership/metadata. The small checkpoint is
/// atomic, profile owned and independent of disposable catalog/image caches.
actor MusicSessionFileStore: MusicSessionPersisting {
    static let shared = MusicSessionFileStore()
    private struct Queue: Codable {
        var schema = 1
        let revision: UUID
        let tracks: [MusicTrack]
    }
    private struct Checkpoint: Codable {
        var schema = 1
        let revision: UUID
        let current: MusicTrack
        let origin: MusicQueueOrigin?
        let position: Double
        let savedAt: Date
    }
    private var written: [String: UUID] = [:]
    private let directory: URL?
    init(directory: URL? = nil) { self.directory = directory }

    func write(_ value: MusicSessionSnapshot, owner: String) throws {
        guard value.position.isFinite, value.position >= 0,
              value.savedAt.timeIntervalSince1970.isFinite else { throw HarborError(code: "music-session") }
        let root = try root(owner)
        let current = try recording(value.current)
        if written[owner] != value.revision {
            guard value.queue.count <= 100_000 else { throw HarborError(code: "music-session") }
            var seen = Set<String>()
            let tracks = try value.queue.map { try recording($0) }.filter { seen.insert(MusicQueueOrder.key($0)).inserted }
            let bytes = try JSONEncoder().encode(Queue(revision: value.revision, tracks: tracks))
            guard bytes.count <= 16 * 1024 * 1024 else { throw HarborError(code: "music-session") }
            try write(bytes, to: root.appendingPathComponent("queue.json"))
            written[owner] = value.revision
        }
        let origin = try validOrigin(value.origin)
        let bytes = try JSONEncoder().encode(Checkpoint(revision: value.revision, current: current, origin: origin,
                                                       position: value.position, savedAt: value.savedAt))
        guard bytes.count <= 128 * 1024 else { throw HarborError(code: "music-session") }
        try write(bytes, to: root.appendingPathComponent("checkpoint.json"))
    }

    func read(owner: String) throws -> MusicSessionSnapshot? {
        let root = try root(owner)
        guard let bytes = try read(root.appendingPathComponent("checkpoint.json"), limit: 128 * 1024) else { return nil }
        let checkpoint = try JSONDecoder().decode(Checkpoint.self, from: bytes)
        guard checkpoint.schema == 1, checkpoint.position.isFinite, checkpoint.position >= 0,
              checkpoint.savedAt.timeIntervalSince1970.isFinite else { throw HarborError(code: "music-session") }
        let current = try recording(checkpoint.current)
        var queue: [MusicTrack] = []
        // A substitute recording still restores when a queue update was interrupted.
        if let bytes = try? read(root.appendingPathComponent("queue.json"), limit: 16 * 1024 * 1024),
           let saved = try? JSONDecoder().decode(Queue.self, from: bytes),
           saved.schema == 1, saved.revision == checkpoint.revision, saved.tracks.count <= 100_000,
           let tracks = try? saved.tracks.map({ try recording($0) }) {
            queue = tracks; written[owner] = saved.revision
        }
        var seen: Set<String> = [MusicQueueOrder.key(current)]
        let key = MusicQueueOrder.key(current)
        if let index = queue.firstIndex(where: { MusicQueueOrder.key($0) == key }) {
            queue[index] = current
            var unique = Set<String>(); queue = queue.filter { unique.insert(MusicQueueOrder.key($0)).inserted }
        } else { queue = [current] + queue.filter { seen.insert(MusicQueueOrder.key($0)).inserted } }
        return .init(revision: checkpoint.revision, queue: queue, current: current, origin: try validOrigin(checkpoint.origin),
                     position: MusicSessionSnapshot.usablePosition(checkpoint.position, duration: Double(current.durationSeconds)),
                     savedAt: checkpoint.savedAt)
    }

    private func recording(_ track: MusicTrack) throws -> MusicTrack {
        guard !track.id.isEmpty, track.id.utf8.count <= 8192, track.id.rangeOfCharacter(from: .controlCharacters) == nil,
              [track.title, track.artist, track.album ?? "", track.artwork].allSatisfy({ $0.utf8.count <= 32768 && !$0.contains("\0") }),
              [track.quality?.sampleRateHz, track.quality?.bitDepth, track.quality?.bitrateKbps].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw HarborError(code: "music-session")
        }
        let saved = track.playlistRecording(replacing: nil)
        return MusicTrack(id: saved.id, connectorId: track.connectorId, sourceId: saved.sourceId,
                          playbackUrl: saved.playbackUrl, title: saved.title, artist: saved.artist, album: saved.album,
                          artwork: saved.artwork, durationSeconds: saved.durationSeconds, durationLabel: saved.durationLabel,
                          explicit: saved.explicit, version: saved.version, mediaKind: saved.mediaKind, isrc: saved.isrc,
                          releaseDate: saved.releaseDate, collectionOrigin: saved.collectionOrigin, quality: saved.quality)
    }
    private func validOrigin(_ origin: MusicQueueOrigin?) throws -> MusicQueueOrigin? {
        guard let origin else { return nil }
        guard [origin.kind, origin.id, origin.name].allSatisfy({ $0.utf8.count <= 8192 && !$0.contains("\0") }) else { throw HarborError(code: "music-session") }
        return origin
    }
    private func root(_ owner: String) throws -> URL {
        let base = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("HarborMusicSessions", isDirectory: true)
        let root = base.appendingPathComponent(EBookShelf.hash(owner), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return root
    }
    private func write(_ bytes: Data, to url: URL) throws {
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func read(_ url: URL, limit: Int) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit else { throw HarborError(code: "music-session") }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= limit else { throw HarborError(code: "music-session") }
        return bytes
    }
}
