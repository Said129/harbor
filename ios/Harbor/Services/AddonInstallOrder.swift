import Foundation

/// Desktop `installFromUrl` (src/lib/addon-store.ts): an install replaces the addon that has the same
/// manifest id or the same transport URL, and the replacement keeps the replaced addon's place in the
/// list (Desktop's `preserveOrderOnReplace` and the `pushToStremio` insert index). Desktop keys the
/// disabled state by URL, so a re-install of the same URL keeps it.
enum AddonInstallOrder {
    static func merged(_ addons: [Addon], installing addon: Addon) -> [Addon] {
        // An empty or missing manifest id must never match another addon that has no id.
        let rawID = addon.manifest["id"].string
        let manifestID: String? = rawID?.isEmpty == false ? rawID : nil
        func replaced(_ item: Addon) -> Bool {
            item.transportUrl == addon.transportUrl || (manifestID != nil && item.manifest["id"].string == manifestID)
        }
        var installed = addon
        if let sameURL = addons.first(where: { $0.transportUrl == addon.transportUrl }) { installed.enabled = sameURL.enabled }
        guard let first = addons.firstIndex(where: replaced) else { return addons + [installed] }
        var result: [Addon] = []
        for (index, item) in addons.enumerated() {
            if index == first { result.append(installed) }
            if !replaced(item) { result.append(item) }
        }
        return result
    }
}
