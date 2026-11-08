import Foundation

/// Desktop addon catalogs (src/lib/addons.ts): `NON_CONTENT_TYPES` keeps `addon_catalog` out of the
/// content rows, and `collapseEpisodeMetas` folds the episode ids of one series into its series id.
enum AddonCatalogRules {
    /// Desktop strips media-type words and punctuation before comparing rows of the same kind.
    private static let mediaTypeWords = try! NSRegularExpression(pattern: #"(?<![a-z0-9_])(?:movies|movie|series|shows|show|tv)(?![a-z0-9_])"#)
    private static let separator = try! NSRegularExpression(pattern: #"[^a-z0-9]+"#)

    static func normalizedName(_ name: String, kind: String) -> String {
        let lower = name.lowercased()
        let words = mediaTypeWords.stringByReplacingMatches(in: lower, range: NSRange(lower.startIndex..., in: lower), withTemplate: "")
        let normalized = separator.stringByReplacingMatches(in: words, range: NSRange(words.startIndex..., in: words), withTemplate: " ")
        return normalized.trimmingCharacters(in: .whitespaces) + "::" + kind
    }

    static func discoveredRows(_ rows: [CatalogRow], showAll: Bool = false) -> [CatalogRow] {
        let available = rows.filter { !$0.metas.isEmpty }
        let distinct = HomeCatalogFilter.uniqueAddonRows(available, takenKeys: [],
            key: { normalizedName($0.plan.title, kind: $0.plan.kind) }, showAll: showAll)
        return Array(distinct.prefix(showAll ? 200 : 24))
    }

    static func isContentType(_ type: String) -> Bool {
        type.lowercased() != "addon_catalog"
    }

    /// Desktop `seriesBaseId`: a series or anime episode id `<id>:<season>:<episode>` names its series.
    static func seriesBaseID(id: String, type: String) -> String {
        guard type == "series" || type == "anime" else { return id }
        return id.replacingOccurrences(of: #":(\d+):(\d+)$"#, with: "", options: .regularExpression)
    }

    /// Desktop `collapseEpisodeMetas`: when several metas share a series base id, only the first one is kept,
    /// with the base id. Metas whose base id is unique are returned unchanged.
    static func collapseEpisodeMetas(_ metas: [Media]) -> [Media] {
        var counts: [String: Int] = [:]
        for media in metas { counts[seriesBaseID(id: media.id, type: media.type), default: 0] += 1 }
        guard counts.values.contains(where: { $0 > 1 }) else { return metas }
        var seen = Set<String>()
        var out: [Media] = []
        for media in metas {
            let base = seriesBaseID(id: media.id, type: media.type)
            if (counts[base] ?? 0) < 2 { out.append(media); continue }
            guard seen.insert(base).inserted else { continue }
            var item = media
            if base != media.id { item.id = base }
            out.append(item)
        }
        return out
    }
}
