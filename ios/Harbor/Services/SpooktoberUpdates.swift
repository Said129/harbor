import Foundation

/// Public editorial data only. App code and the signed installation remain bundled.
actor SpooktoberUpdates {
    static let shared = SpooktoberUpdates()
    private var current: [SpooktoberItem]?
    private var lastAttempt = Date.distantPast
    private var retryInterval: TimeInterval = 0
    private var refreshing = false
    private var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Harbor/Seasonal/Spooktober.json")
    }
    func catalog() throws -> [SpooktoberItem] {
        if let current { return current }
        if let saved = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           let size = saved.fileSize, size <= 1024 * 1024,
           let data = try? Data(contentsOf: file), let cached = try? SpooktoberCatalog.decode(data) {
            current = cached
            lastAttempt = min(saved.contentModificationDate ?? .distantPast, Date()); retryInterval = 86_400
        } else { current = try SpooktoberCatalog.load() }
        return current ?? []
    }
    @discardableResult func refresh(force: Bool = false) async throws -> [SpooktoberItem] {
        let previous = try catalog()
        guard !refreshing, force || Date().timeIntervalSince(lastAttempt) >= retryInterval else { return previous }
        refreshing = true; lastAttempt = Date(); retryInterval = 3_600
        defer { refreshing = false }
        do {
            let json = try await HTTPClient().json(SpooktoberCatalog.upstream + "content.json")
            let data = try JSONEncoder().encode(json)
            let updated = try SpooktoberCatalog.decode(data, remote: true)
            try Task.checkCancellation()
            let encoded = try JSONEncoder().encode(updated)
            guard encoded.count <= 1024 * 1024 else { throw HarborError(code: "spooktober-content") }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: file, options: .atomic)
            current = updated; retryInterval = 86_400
            return updated
        } catch is CancellationError { throw CancellationError() }
        catch { return previous }
    }
}
