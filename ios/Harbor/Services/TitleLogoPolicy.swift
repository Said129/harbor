import Foundation

/// The title logo on the detail page, in Desktop's order (`detail.tsx`): the pinned logo, then the season artwork,
/// then the logo resolved through `CardArtworkResolver`, then the title's own logo. An empty value counts as missing.
enum TitleLogoPolicy {
    static func logo(pinned: String?, season: String?, resolved: String?, fallback: String?) -> String? {
        [pinned, season, resolved, fallback].compactMap { $0 }.first { !$0.isEmpty }
    }
}
