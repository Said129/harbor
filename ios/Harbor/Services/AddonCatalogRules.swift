import Foundation

/// Desktop addon catalogs (src/lib/addons.ts): `NON_CONTENT_TYPES` keeps `addon_catalog` out of the
/// content rows, and `collapseEpisodeMetas` folds the episode ids of one series into its series id.
enum AddonCatalogRules {
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
