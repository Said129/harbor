import Foundation

/// Desktop's local folder scan rules (music/connectors/local/scan.rs).
/// A file whose size and modified time match its index entry is skipped, and indexed paths that the scan
/// did not see are removed. iOS keeps no folder source yet, so these rules have no caller.
enum MusicFolderRescanRules {
    /// Desktop's modified_seconds: whole seconds since the Unix epoch; unknown or pre-epoch times are 0.
    static func modifiedSeconds(_ date: Date?) -> Int64 {
        guard let date else { return 0 }
        let seconds = date.timeIntervalSince1970
        guard seconds >= 0, seconds < 9.0e18 else { return 0 }
        return Int64(seconds)
    }

    /// Desktop's unchanged test: the indexed file has the same size and modified time.
    static func unchanged(knownSize: Int64?, knownModified: Int64?, size: Int64, modified: Int64) -> Bool {
        knownSize == size && knownModified == modified
    }

    /// Desktop's prune: indexed paths the scan did not find.
    static func removedPaths(indexed: [String], seen: Set<String>) -> [String] {
        indexed.filter { !seen.contains($0) }
    }
}
