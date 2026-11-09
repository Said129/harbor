import Foundation

/// Desktop's hero layout rules reduced to what iPhone and iPad can honour. Desktop defaults (`src/lib/settings/defaults.ts`
/// lines 115-118): `heroShadow` 100, `heroFull` false, `heroFullQuality` true, `heroFeed` "trending".
/// Desktop references: `src/components/hero.tsx` line 335 (shadow opacity = heroShadow / 100), lines 288 and 297 (full
/// banner height `h-[78vh] min-h-[640px]`), lines 540-544 (`upsizeTmdb`: `original` when full quality, `w1280` otherwise),
/// `src/views/home.tsx` lines 131, 260-263 (feed fetch) and 1214-1226 (full and fullQuality passed to the carousel),
/// `src/views/settings/library-panel/home-tab.tsx` lines 33-125 (labels and ranges).
/// `scrollUpTrailer` is not part of this policy: it belongs to Desktop's detail page scroll (`src/views/detail.tsx` 478-480).
enum HeroLayoutPolicy {
    static let defaultShadowPercent = 100
    static let defaultFull = false
    static let defaultFullQuality = true
    static let defaultFeed = HeroFeed.trending

    /// Desktop's `Featured source` values.
    enum HeroFeed: String, CaseIterable, Sendable {
        case trending
        case trakt
        case simkl
        case classic

        /// A missing or unknown stored value takes Desktop's default, `trending`.
        init(stored: Any?) {
            self = (stored as? String).flatMap(HeroFeed.init(rawValue:)) ?? HeroLayoutPolicy.defaultFeed
        }
    }

    /// Opacity of the top stop of the hero gradient. This is the part of the gradient that does not depend on the shadow.
    static let topStopOpacity = 0.12
    /// Opacity of the middle stop at 100%, which is the classic look (`0.55`, `ContentPageView.swift` before this change).
    static let classicMiddleStopOpacity = 0.55
    /// The standard hero height on iPhone and iPad, as before this change.
    static let standardHeight: CGFloat = 410
    /// Desktop's minimum height for the full banner (`min-h-[640px]`).
    static let fullMinimumHeight: CGFloat = 640
    /// Desktop's full banner height as a share of the viewport (`78vh`).
    static let fullFraction: CGFloat = 0.78

    /// Clamps a stored or typed shadow value to Desktop's 0...100 range and rounds it to a whole percent.
    /// A value that is not a finite number takes Desktop's default.
    static func shadowPercent(_ value: Double) -> Int {
        guard value.isFinite else { return defaultShadowPercent }
        return Int(min(100, max(0, value)).rounded())
    }

    /// Reads a stored `heroShadow` value. A non-numeric value takes Desktop's default.
    static func shadowPercent(stored: Any?) -> Int {
        guard let number = stored as? NSNumber else { return defaultShadowPercent }
        return shadowPercent(number.doubleValue)
    }

    /// The opacity of the gradient's middle stop. Desktop multiplies its side gradient by `heroShadow / 100`, so the
    /// classic stop is scaled by the same factor: 100% keeps `0.55`, 50% gives `0.275`, 0% removes the middle layer.
    static func middleStopOpacity(shadowPercent percent: Int) -> Double {
        let factor = Double(HeroLayoutPolicy.shadowPercent(Double(percent))) / 100
        return classicMiddleStopOpacity * factor
    }

    /// The largest edge, in pixels, that the hero artwork is decoded to. Full quality keeps the `original` size that
    /// Desktop requests for TMDB backdrops; the standard size matches Desktop's `w1280`.
    static func artworkMaxPixels(fullQuality: Bool) -> Int {
        fullQuality ? 2160 : 1280
    }

    /// The hero height for the container it fills. Full banners take 78% of the container and never less than 640 points.
    static func heroHeight(full: Bool, container: CGFloat) -> CGFloat {
        guard full else { return standardHeight }
        guard container.isFinite, container > 0 else { return fullMinimumHeight }
        return max(fullMinimumHeight, (container * fullFraction).rounded())
    }
}
