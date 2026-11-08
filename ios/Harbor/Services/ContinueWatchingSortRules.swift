import Foundation

/// Desktop Continue Watching merge (src/lib/continue-watching.ts and `cwSortKey` in src/lib/stremio.ts).
enum ContinueWatchingSortRules {
    /// Desktop always leaves cloud anime (`ANIME_CLOUD_ID`) out of the cloud list; anime resumes come
    /// from the local source instead.
    static func keepsCloudRecord(id: String) -> Bool {
        !CloudAnimeContinueImport.owns(id)
    }

    /// Desktop's `cwSortKey`: the newer of the record's own activity and its local resume timestamp.
    static func sortKey(activity: Double, resumeTimestamp: Double?) -> Double {
        max(activity, resumeTimestamp ?? 0)
    }
}
