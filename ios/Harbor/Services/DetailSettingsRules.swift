import Foundation

/// Pure rules for the detail-page settings ported from Desktop 0.9.132 (`preferCustomMetaAddon` in `lib/meta-resource.ts`).
/// `resumeDetailScroll` is not ported: the navigation stack keeps a detail page's scroll position by itself.
enum DetailSettingsRules {
    /// Desktop's `isCinemeta` matches any id that contains "cinemeta".
    static func isCinemeta(_ addonID: String?) -> Bool {
        (addonID ?? "").lowercased().contains("cinemeta")
    }

    /// The order in which metadata plans are read. With `preferCustom` on, addons that are not
    /// Cinemeta come first and Cinemeta only answers when they return nothing. With it off, the
    /// order is unchanged. Each group keeps its own order. Returns indices into `addonIDs`.
    static func metaPlanOrder(addonIDs: [String?], preferCustom: Bool) -> [Int] {
        let indices = Array(addonIDs.indices)
        guard preferCustom else { return indices }
        let custom = indices.filter({ !isCinemeta(addonIDs[$0]) })
        let cinemeta = indices.filter({ isCinemeta(addonIDs[$0]) })
        return custom + cinemeta
    }

    /// `HarborService.addonMetadata` reads its plans in this order. The setting is read from
    /// UserDefaults because the service is not main-actor isolated.
    static func preferringCustomMeta(_ plans: [RequestPlan]) -> [RequestPlan] {
        let preferCustom = UserDefaults.standard.bool(forKey: "preferCustomMetaAddon")
        let order = metaPlanOrder(addonIDs: plans.map({ $0.addon.manifest["id"].string }), preferCustom: preferCustom)
        return order.map({ plans[$0] })
    }

}
