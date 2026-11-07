import Foundation

/// Desktop's episode list display settings (`episodeLayout`, `episodeCardScale`, `hdEpisodeImages`) as pure rules,
/// so the views and the tests share one definition of card sizes and artwork.
enum EpisodeLayoutPolicy {
    /// Desktop's `episodeLayout`: the vertical list, the horizontal strip, or the grid of cards.
    enum Layout: String, CaseIterable, Sendable {
        case list, strip, grid
    }

    /// Desktop's `defaults.ts`: `episodeLayout: "list"`.
    static let defaultLayout = Layout.list
    /// Desktop's `defaults.ts`: `episodeCardScale: 1`.
    static let defaultCardScale = 1.0
    /// The card sizes Desktop offers in `library-panel/detail-tab.tsx` (Default, Large, Extra large).
    static let cardScaleChoices: [Double] = [1.0, 1.2, 1.45]
    /// Desktop's `episode-strip.tsx`: a strip card is `Math.round(244 * scale)` pixels wide.
    static let stripBaseWidth = 244.0
    /// Desktop's `episode-grid.tsx`: grid columns are at least `Math.round(232 * scale)` pixels wide.
    static let gridBaseMinimumWidth = 232.0

    /// An unknown or missing stored value shows the default layout.
    static func layout(_ raw: String?) -> Layout {
        raw.flatMap(Layout.init(rawValue:)) ?? defaultLayout
    }

    /// Desktop reads `settings.episodeCardScale || 1`, so a missing, zero, negative or non-finite scale means 1.
    static func cardScale(_ value: Double?) -> Double {
        guard let value, value.isFinite, value > 0 else { return defaultCardScale }
        return value
    }

    /// Width of one card in the horizontal strip.
    static func stripWidth(_ scale: Double?) -> Double {
        (stripBaseWidth * cardScale(scale)).rounded()
    }

    /// Smallest width of one column in the grid; the grid fits as many columns of this width as the screen allows.
    static func gridMinimumWidth(_ scale: Double?) -> Double {
        (gridBaseMinimumWidth * cardScale(scale)).rounded()
    }

    /// Desktop's still URLs: TMDB stills use `original` when HD is on and `w300` when it is off.
    /// Other hosts (and a missing thumbnail) are returned unchanged.
    static func still(_ url: String?, hd: Bool) -> String? {
        guard let url else { return nil }
        let (from, to) = hd ? ("/t/p/w300/", "/t/p/original/") : ("/t/p/original/", "/t/p/w300/")
        return url.replacingOccurrences(of: from, with: to)
    }

    /// The largest decoded still: cards in the strip and grid decode bigger pictures when HD is on.
    static func artworkPixels(hd: Bool) -> Int {
        hd ? 1000 : 600
    }
}
