import Foundation

/// Desktop Continue Watching merge (src/lib/continue-watching.ts and `cwSortKey` in src/lib/stremio.ts).
enum ContinueWatchingSortRules {
    /// Desktop leaves cloud anime (`ANIME_CLOUD_ID`) out of the cloud list because anime resumes come from the local source.
    /// iOS imports those cloud items into the local library, so it drops them only while that local copy is shown.
    static func keepsCloudRecord(id: String, localVisible: Bool) -> Bool {
        !CloudAnimeContinueImport.owns(id) || !localVisible
    }

    /// Desktop's `cwSortKey`: the newer of the record's own activity and its local resume timestamp.
    static func sortKey(activity: Double, resumeTimestamp: Double?) -> Double {
        max(activity, resumeTimestamp ?? 0)
    }
}
