import Foundation

/// Desktop's choice among the metadata answers in `resolveMeta` (`lib/meta-resource.ts`), for the
/// `preferCustomMetaAddon` poster rule.
enum MetaPosterPreference {
    /// One metadata answer, in the order the addons were asked.
    struct MetaAnswer: Equatable, Sendable {
        var isCinemeta: Bool
        var hasPoster: Bool
    }

    /// `index` points into the answers, or is nil when Desktop returns nothing. `fillArtwork` is true when
    /// Desktop takes the poster, background and logo from Cinemeta because the chosen answer lacks them.
    struct Choice: Equatable, Sendable {
        var index: Int?
        var fillArtwork: Bool
    }

    /// Desktop's order. Without the preference, Cinemeta with a poster wins, then the first custom answer with a
    /// poster, then Cinemeta without one. With the preference, the first custom answer with a poster wins, then the
    /// first custom answer (its artwork filled from Cinemeta), then Cinemeta.
    static func choose(_ answers: [MetaAnswer], preferCustom: Bool) -> Choice {
        let cinemeta = answers.indices.first { answers[$0].isCinemeta }
        let custom = answers.indices.filter { !answers[$0].isCinemeta }
        if !preferCustom, let cinemeta, answers[cinemeta].hasPoster {
            return Choice(index: cinemeta, fillArtwork: false)
        }
        if let withPoster = custom.first(where: { answers[$0].hasPoster }) {
            return Choice(index: withPoster, fillArtwork: false)
        }
        if preferCustom, let first = custom.first {
            return Choice(index: first, fillArtwork: true)
        }
        if let cinemeta {
            return Choice(index: cinemeta, fillArtwork: false)
        }
        return Choice(index: nil, fillArtwork: false)
    }
}
