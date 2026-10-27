import Foundation
import CryptoKit

/// Actor serialization keeps file I/O off the UI thread and commits memory only
/// after a successful atomic write. No stream/addon URLs enter this document.
actor ResumeStore {
    private var document = ResumeDocument()
    private var ready = false
    private var clearedAt: [String: Double] = [:]
    private var fileURL: URL?
    private let owner: String
    private let limit = 8 * 1024 * 1024

    init(fileURL: URL? = nil, owner: String = "guest") { self.fileURL = fileURL; self.owner = owner }

    func load() throws {
        ready = false
        do {
            let file = try location()
            var next = ResumeDocument()
            do {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= limit else { throw HarborError(code: "resume-store-too-large") }
                let data = try Data(contentsOf: file)
                guard data.count <= limit else { throw HarborError(code: "resume-store-too-large") }
                next = try JSONDecoder().decode(ResumeDocument.self, from: data)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                // Only genuine absence initializes an empty store.
            }
            document = try invoke("validateResume", ["document": try .encoded(next)], as: ResumeDocument.self)
            ready = true
        } catch let error as HarborError { throw error }
        catch { throw HarborError(code: "resume-read-failed") }
    }

    func position(_ target: ResumeTarget, durationMs: Double = 0, playback: Bool = true, prompt: Bool = false, cloud: ResumeEntry? = nil, media: Media? = nil) throws -> ResumeStart {
        guard ready else { throw HarborError(code: "resume-store-unavailable") }
        var merged = document
        struct Key: Decodable { let key: String }
        let result = try invoke("resumeKey", ["target": try .encoded(target)], as: Key.self)
        // Earlier builds treated the provider's single movie video as S1E1.
        // Reuse that position only for the exact same real movie/video; keep
        // newer resets and leave the original key intact for older builds.
        if let media, media.type == "movie", media.id == target.id, target.season == nil, target.episode == nil {
            let videoID = target.videoId ?? media.behaviorHints?.defaultVideoId ?? media.id
            for episode in media.videos ?? [] where episode.id == videoID {
                let previous = ResumeTarget(id: media.id, season: episode.season, episode: episode.episode, videoId: episode.id)
                let key = try invoke("resumeKey", ["target": try .encoded(previous)], as: Key.self)
                if let entry = document.entries[key.key], Double(entry.t) > (clearedAt[result.key] ?? -1), entry.t > (merged.entries[result.key]?.t ?? 0) { merged.entries[result.key] = entry }
            }
        }
        if let cloud {
            if Double(cloud.t) > (clearedAt[result.key] ?? -1), cloud.t >= (merged.entries[result.key]?.t ?? 0) { merged.entries[result.key] = cloud }
        }
        return try invoke("resumePosition", ["target": try .encoded(target), "document": try .encoded(merged), "durationMs": .number(durationMs), "playback": .bool(playback), "prompt": .bool(prompt)], as: ResumeStart.self)
    }

    func entry(_ target: ResumeTarget) throws -> ResumeEntry? {
        guard ready else { throw HarborError(code: "resume-store-unavailable") }
        struct Key: Decodable { let key: String }
        let result = try invoke("resumeKey", ["target": try .encoded(target)], as: Key.self)
        return document.entries[result.key]
    }

    /// Preserve the provider pause time; importing an unchanged remote checkpoint
    /// must never manufacture fresh local activity or replace a newer Start Over.
    @discardableResult
    func importRemote(_ target: ResumeTarget, entry: ResumeEntry, current: @escaping SimklClient.Lease) async throws -> Bool {
        guard ready else { throw HarborError(code: "resume-store-unavailable") }
        guard await current() else { throw CancellationError() }
        struct Key: Decodable { let key: String }
        let result = try invoke("resumeKey", ["target": try .encoded(target)], as: Key.self)
        guard Double(entry.t) > (clearedAt[result.key] ?? -1) else { return false }
        if let held = document.entries[result.key] {
            let newer = entry.t > 0 && entry.t >= held.t
            guard newer || (held.t == 0 && entry.ms > held.ms) else { return false }
        }
        var next = document; next.entries[result.key] = entry
        _ = try invoke("validateResume", ["document": try .encoded(next)], as: ResumeDocument.self)
        return try commit(next)
    }

    @discardableResult
    func save(_ target: ResumeTarget, snapshot: ResumeSnapshot) throws -> Bool {
        guard ready else { throw HarborError(code: "resume-store-unavailable") }
        // Reject nonfinite values before JSONEncoder; errors never include input.
        guard snapshot.positionMs.isFinite, snapshot.durationMs.isFinite else { throw HarborError(code: "invalid-resume-position") }
        struct Checkpoint: Decodable { let key: String; let entry: ResumeEntry }
        struct Result: Decodable { let checkpoint: Checkpoint? }
        let result: Result = try invoke("resumeCheckpoint", ["target": try .encoded(target), "positionMs": .number(snapshot.positionMs), "durationMs": .number(snapshot.durationMs), "timestampMs": .unsigned(snapshot.timestampMs), "exiting": .bool(snapshot.exiting)], as: Result.self)
        guard let checkpoint = result.checkpoint else { return false }
        guard Double(checkpoint.entry.t) > (clearedAt[checkpoint.key] ?? -1) else { return false }
        // Late cleanup tasks cannot overwrite a newer checkpoint after reopening.
        if let existing = document.entries[checkpoint.key], existing.t >= checkpoint.entry.t { return false }
        var next = document
        next.entries[checkpoint.key] = checkpoint.entry
        return try commit(next)
    }

    /// An explicit Start Over is different from an initial zero-position autosave.
    /// Keep a newer zero checkpoint so legacy movie aliases and older cloud values cannot return.
    @discardableResult
    func restart(_ target: ResumeTarget, timestampMs: UInt64) throws -> Bool {
        guard ready else { throw HarborError(code: "resume-store-unavailable") }
        struct Key: Decodable { let key: String }
        let result = try invoke("resumeKey", ["target": try .encoded(target)], as: Key.self)
        guard !target.id.hasPrefix("iptv:") else { return false }
        guard Double(timestampMs) > (clearedAt[result.key] ?? -1) else { return false }
        if let current = document.entries[result.key], current.t >= timestampMs { return false }
        var next = document; next.entries[result.key] = ResumeEntry(ms: 0, t: timestampMs)
        return try commit(next)
    }

    /// Dismiss only the captured episode. A checkpoint written after the tap
    /// must survive delayed cleanup, as must every personal resume document.
    @discardableResult
    func clear(_ target: ResumeTarget, notNewerThan timestampMs: Double) throws -> Bool {
        guard ready else { throw HarborError(code: "resume-store-unavailable") }
        struct Key: Decodable { let key: String }
        let key = try invoke("resumeKey", ["target": try .encoded(target)], as: Key.self).key
        guard timestampMs.isFinite, timestampMs >= 0 else { throw HarborError(code: "invalid-resume-position") }
        if let held = document.entries[key], Double(held.t) > timestampMs { return false }
        let changed = document.entries[key] != nil
        if changed { var next = document; next.entries.removeValue(forKey: key); _ = try commit(next) }
        // The key stays absent, matching Desktop. Keep a bounded in-flight
        // barrier so a request already awaiting its lease cannot recreate it.
        clearedAt[key] = max(clearedAt[key] ?? 0, timestampMs)
        if clearedAt.count > 2_000, let oldest = clearedAt.min(by: { $0.value < $1.value })?.key { clearedAt.removeValue(forKey: oldest) }
        return changed
    }

    private func commit(_ next: ResumeDocument) throws -> Bool {
        do {
            let data = try JSONEncoder().encode(next)
            guard data.count <= limit else { throw HarborError(code: "resume-store-too-large") }
            let file = try location()
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            document = next
            return true
        } catch let error as HarborError { throw error }
        catch { throw HarborError(code: "resume-write-failed") }
    }

    private func location() throws -> URL {
        if let fileURL { return fileURL }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let hash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent("Harbor", isDirectory: true).appendingPathComponent("resume-\(hash).json")
        fileURL = file
        return file
    }

    private func invoke<T: Decodable>(_ operation: String, _ fields: [String: JSONValue], as: T.Type) throws -> T {
        var request = fields
        request["operation"] = .string(operation)
        return try CoreBridge.invoke(JSONEncoder().encode(JSONValue.object(request)), as: T.self)
    }
}
