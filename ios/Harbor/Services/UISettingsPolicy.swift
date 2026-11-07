import Foundation

/// Pure rules behind a few small Desktop settings: `mpvQuality` (`src/lib/player/mpv-tuning.ts`),
/// `spoilerSkipNext` (`src/lib/spoilers.ts`), `playerTitleSeriesFirst` (`src/components/player/transport/control-renderer.tsx`)
/// and `deleteWatchedDownloads` (`src/views/player/hooks/use-player-media.ts`).
enum UISettingsPolicy {
    static let mpvQualityKey = "mpvQuality"
    static let mpvQualityDefault = "balanced"

    /// Desktop's `mpvQuality` profile. Anything other than "performance" or "quality" means "balanced".
    static func mpvQuality(_ raw: String?) -> String {
        guard let raw, raw == "performance" || raw == "quality" else { return mpvQualityDefault }
        return raw
    }

    /// The Desktop `QUALITY_LINES` entries for the "performance" profile, in Desktop's order.
    static let performanceMpvOptions: [(String, String)] = [
        ("scale", "bilinear"), ("cscale", "bilinear"), ("dscale", "bilinear"), ("dither", "no"),
        ("deband", "no"), ("vd-lavc-fast", "yes"), ("interpolation", "no"), ("hdr-compute-peak", "no")
    ]

    /// The Desktop `QUALITY_LINES` entries for the "quality" profile, in Desktop's order.
    static let qualityMpvOptions: [(String, String)] = [
        ("scale", "ewa_lanczossharp"), ("cscale", "ewa_lanczossharp"), ("dscale", "mitchell"), ("deband", "yes"),
        ("deband-iterations", "2"), ("dither-depth", "auto"), ("correct-downscaling", "yes"), ("linear-downscaling", "yes"),
        ("sigmoid-upscaling", "yes"), ("hdr-compute-peak", "yes")
    ]

    /// The mpv options a quality profile adds. "balanced" adds none, as on Desktop.
    static func mpvQualityOptions(_ raw: String?) -> [(String, String)] {
        switch mpvQuality(raw) {
        case "performance": return performanceMpvOptions
        case "quality": return qualityMpvOptions
        default: return []
        }
    }

    /// The same options written as Desktop writes them, one `name=value` line each.
    static func mpvQualityLines(_ raw: String?) -> [String] {
        mpvQualityOptions(raw).map { "\($0.0)=\($0.1)" }
    }

    /// Desktop's `SpoilerMask`: which parts of an episode stay blurred.
    struct SpoilerMask: Equatable {
        let thumbnail: Bool
        let title: Bool
        let description: Bool
        var active: Bool { thumbnail || title || description }
    }

    /// Desktop's `spoilerMaskFor`. Nothing is blurred when spoilers are not hidden, when the episode is watched,
    /// or when "Keep the next episode visible" is on and the episode is the next one up.
    static func spoilerMask(hideSpoilers: Bool, blurThumbnails: Bool, hideTitles: Bool, hideDescriptions: Bool,
                            skipNext: Bool, watched: Bool, isNextUp: Bool) -> SpoilerMask {
        let clear = SpoilerMask(thumbnail: false, title: false, description: false)
        if !hideSpoilers || watched { return clear }
        if skipNext && isNextUp { return clear }
        return SpoilerMask(thumbnail: blurThumbnails, title: hideTitles, description: hideDescriptions)
    }

    /// Desktop's `playerTitleSeriesFirst` swap. The subtitle leads only when the option is on and a subtitle exists.
    static func titleLines(title: String, subtitle: String?, seriesFirst: Bool) -> (primary: String, secondary: String?) {
        guard seriesFirst, let subtitle, !subtitle.isEmpty else { return (title, subtitle) }
        return (subtitle, title)
    }

    /// Desktop's `deleteWatchedDownloads` rule: a download is removed once playback reaches 90 percent.
    static func removesWatchedDownload(enabled: Bool, progress: Double) -> Bool {
        enabled && progress >= 0.9
    }
}
