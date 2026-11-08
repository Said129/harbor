import Foundation

/// Desktop's Wikidata award rules for people (`fetchAwards` and `collapseAwards` with kind "person" in
/// `lib/providers/wikidata.ts`). iOS does not fetch people awards yet, so these helpers have no caller.
enum PersonAwardRules {
    /// Desktop's `kind` in `fetchAwards`: an `nm` id is a person, otherwise a series or a movie.
    static func kind(imdbID: String, isSeries: Bool) -> String {
        if imdbID.hasPrefix("nm") { return "person" }
        return isSeries ? "series" : "movie"
    }

    /// Desktop's `collapseAwards` key for a person: the award, its category, then the work the award was for.
    static func collapseKey(awardName: String, category: String?, workIMDb: String?, workTitle: String?) -> String {
        let base = awardName.lowercased() + "|" + (category ?? "").lowercased()
        return base + "|" + (workIMDb ?? workTitle ?? "")
    }
}
