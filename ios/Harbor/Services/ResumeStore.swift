import Foundation
import CryptoKit

/// Actor serialization keeps file I/O off the UI thread and commits memory only
/// after a successful atomic write. No stream/addon URLs enter this document.
actor ResumeStore {
    private var document = ResumeDocument()
    private var ready = false
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

    func position(_ target: ResumeTarget, durationMs: Double = 0, playback: Bool = true, prompt: Bool = false, cloud: ResumeEntry? = nil) throws -> ResumeStart {
        guard ready else { throw HarborError(code: "resume-store-unavailable") }
        var merged = document
        if let cloud {
            struct Key: Decodable { let key: String }
            let result = try invoke("resumeKey", ["target": try .encoded(target)], as: Key.self)
            if cloud.t >= (merged.entries[result.key]?.t ?? 0) { merged.entries[result.key] = cloud }
        }
        return try invoke("resumePosition", ["target": try .encoded(target), "document": try .encoded(merged), "durationMs": .number(durationMs), "playback": .bool(playback), "prompt": .bool(prompt)], as: ResumeStart.self)
    }

    func entry(_ target: ResumeTarget) throws -> ResumeEntry? {
        guard ready else { throw HarborError(code: "resume-store-unavailable") }
        struct Key: Decodable { let key: String }
        let result = try invoke("resumeKey", ["target": try .encoded(target)], as: Key.self)
        return document.entries[result.key]
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
        // Late cleanup tasks cannot overwrite a newer checkpoint after reopening.
        if let existing = document.entries[checkpoint.key], existing.t >= checkpoint.entry.t { return false }
        var next = document
        next.entries[checkpoint.key] = checkpoint.entry
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
