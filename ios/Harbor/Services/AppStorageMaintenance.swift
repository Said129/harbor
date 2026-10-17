import Foundation

struct AppStorageLocations: Sendable {
    let documents: URL
    let library: URL
    let caches: URL
    let temporary: URL

    static func application() throws -> AppStorageLocations {
        let files = FileManager.default
        return try AppStorageLocations(
            documents: files.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
            library: files.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
            caches: files.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
            temporary: files.temporaryDirectory)
    }
}

struct AppStorageReport: Sendable {
    let documents: Int64
    let library: Int64
    let caches: Int64
    let temporary: Int64
    let files: Int64
    let available: Int64?
}

private final class StorageScanStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var failed = false
    func recordFailure() { lock.withLock { failed = true } }
    var didFail: Bool { lock.withLock { failed } }
}

actor AppStorageMaintenance {
    private let locations: AppStorageLocations?
    init(locations: AppStorageLocations? = nil) { self.locations = locations }

    func measure() throws -> AppStorageReport {
        try Task.checkCancellation()
        let roots = try locations ?? AppStorageLocations.application()
        let documents = try Self.bytes(in: roots.documents)
        let library = try Self.bytes(in: roots.library, excluding: [roots.caches])
        let caches = try Self.bytes(in: roots.caches)
        let temporary = try Self.bytes(in: roots.temporary)
        var total: Int64 = 0
        for value in [documents, library, caches, temporary] {
            let addition = total.addingReportingOverflow(value)
            guard !addition.overflow else { throw HarborError(code: "storage-unavailable") }
            total = addition.partialValue
        }
        let capacity = try? roots.library.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return AppStorageReport(documents: documents, library: library, caches: caches, temporary: temporary, files: total, available: capacity?.volumeAvailableCapacityForImportantUsage)
    }

    static func bytes(in root: URL, excluding exclusions: [URL] = []) throws -> Int64 {
        try Task.checkCancellation()
        let files = FileManager.default, normalized = root.standardizedFileURL
        guard files.fileExists(atPath: normalized.path) else { return 0 }
        guard try normalized.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { return 0 }
        let base = normalized.resolvingSymlinksInPath()
        let excluded = exclusions.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let status = StorageScanStatus()
        guard let enumerator = files.enumerator(at: base, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in status.recordFailure(); return false }) else { throw HarborError(code: "storage-unavailable") }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            let actual = file.standardizedFileURL.resolvingSymlinksInPath().path
            guard actual.hasPrefix(base.path + "/"), !excluded.contains(where: { actual == $0 || actual.hasPrefix($0 + "/") }) else { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true, let size = values.fileSize, size > 0 {
                let addition = total.addingReportingOverflow(Int64(size))
                guard !addition.overflow else { throw HarborError(code: "storage-unavailable") }
                total = addition.partialValue
            }
        }
        if status.didFail { throw HarborError(code: "storage-unavailable") }
        return total
    }
}
