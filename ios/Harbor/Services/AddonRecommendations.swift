import Foundation

/// Desktop "Recommended for you" rail (src/lib/addons-store/recommend.ts `recommendedAddons`,
/// shown by src/views/addons/addon-detail.tsx). iOS has no Harbor curated list, so the curated
/// terms (`curated.recommended` and the +12 curated bonus) are absent and score 0 here.
enum AddonRecommendations {
    /// Desktop shows at most 8 recommendations (src/views/addons.tsx `recommendedAddons(..., 8)`).
    static let limit = 8

    /// Desktop identity: `manifest.id ?? curated.id ?? transportUrl`; iOS has no curated id.
    static func key(_ addon: Addon) -> String {
        let id = addon.manifest["id"].string ?? ""
        return id.isEmpty ? addon.transportUrl : id
    }

    /// Desktop `normName`: lower-case, drop [bracketed] and |piped| tails and common debrid or
    /// provider words, then keep only a-z and 0-9.
    static func normalizedName(_ name: String?) -> String {
        guard let name else { return "" }
        var value = name.lowercased()
        value = value.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\|.*$"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\b(rd|tb|ad|premiumize|debrid|elfhosted|community|official|free|paid|sponsored|by\s+\S+)\b"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
        return value
    }

    /// Desktop `recommendedAddons`. `candidates` should hold the catalog plus installed addons, as
    /// Desktop's `allAddons` does, so that the installed set contributes its categories as taste.
    static func recommended(
        for target: Addon,
        candidates: [Addon],
        installedIDs: Set<String>,
        exclude: Set<String>,
        limit: Int = AddonRecommendations.limit
    ) -> [Addon] {
        let selfID = key(target)
        let targetName = normalizedName(target.manifest["name"].string)
        let targetCategory = target.category
        var taste = Set<AddonCategory>()
        for addon in candidates where installedIDs.contains(key(addon)) {
            taste.insert(addon.category)
        }
        var ranked: [(addon: Addon, score: Int, index: Int)] = []
        for (index, addon) in candidates.enumerated() {
            let id = key(addon)
            if id == selfID || installedIDs.contains(id) || exclude.contains(id) { continue }
            if addon.adult != target.adult { continue }
            if !targetName.isEmpty && normalizedName(addon.manifest["name"].string) == targetName { continue }
            let category = addon.category
            var score = 0
            if taste.contains(category) { score += 30 }
            if category == targetCategory { score += 20 }
            ranked.append((addon: addon, score: score, index: index))
        }
        // Stable order: higher score first, then catalog order (Desktop's Array.sort is stable).
        ranked.sort { lhs, rhs in lhs.score != rhs.score ? lhs.score > rhs.score : lhs.index < rhs.index }
        return Array(dedupeByName(ranked.map(\.addon)).prefix(max(0, limit)))
    }

    /// Desktop `dedupeByName`: keep the first addon per normalized name, or per id when the name is empty.
    private static func dedupeByName(_ addons: [Addon]) -> [Addon] {
        var seen = Set<String>()
        var out: [Addon] = []
        for addon in addons {
            let normalized = normalizedName(addon.manifest["name"].string)
            let token = normalized.isEmpty ? key(addon) : normalized
            if seen.insert(token).inserted { out.append(addon) }
        }
        return out
    }
}
