import Foundation

/// Pure rules for the detail-page settings ported from Desktop 0.9.132
/// (`preferCustomMetaAddon` in `lib/meta-resource.ts`, `resumeDetailScroll` in `views/detail.tsx`).
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

    /// The sections of a detail page the scroll memory can return to, in page order.
    /// `DetailView` marks these views with the same ids.
    static let detailScrollSections = ["detail-hero", "detail-overview", "detail-metadata"]

    /// The section to scroll back to, or nil when the setting is off or the saved section is unknown.
    static func restoredDetailSection(saved: String?, enabled: Bool) -> String? {
        guard enabled, let saved = saved, detailScrollSections.contains(saved) else { return nil }
        return saved
    }
}

/// The last visible section of each title, kept for the session like Desktop's scroll memory.
@MainActor
enum DetailScrollMemory {
    private static var sections: [String: String] = [:]

    static func section(for identity: String) -> String? {
        sections[identity]
    }

    static func remember(_ section: String, for identity: String) {
        sections[identity] = section
    }
}
