import Foundation

/// Desktop's `qualityBadgeStyle` ("bar" or "chips", default "bar"): how the quality labels are drawn under the player title.
enum QualityBadgeStyle: String, CaseIterable, Sendable {
    case bar, chips

    /// Only the exact stored value "chips" reads as chips; a missing or unknown value reads as Desktop's default, "bar".
    static func restored(_ raw: String?) -> QualityBadgeStyle {
        raw == "chips" ? .chips : .bar
    }
}

/// The pure rules for Desktop's stream quality badges: the format chips on a picker row (`components/format-badge.tsx`,
/// `streamBadges`) and the resolution and HDR line under the player title (`components/player/transport/quality-badge.tsx`,
/// `lib/player/resolution-label.ts`). Views draw the result; nothing here reads settings.
enum QualityBadgePolicy {
    /// Desktop's `showQualityBadge` gate in `primary-card.tsx` and `stremio-row.tsx`: chips show only with the setting on and
    /// at least one kind to show.
    static func showsPickerChips(_ show: Bool, kinds: [String]) -> Bool {
        show && !kinds.isEmpty
    }

    /// Desktop's `realQualityLabel`: the label for the decoded picture size, or nil when neither side is known. A tier is
    /// reached when either side reaches it.
    static func resolutionLabel(width: Int, height: Int) -> String? {
        if width <= 0 && height <= 0 { return nil }
        if height >= 2160 || width >= 3840 { return "4K" }
        if height >= 1440 || width >= 2560 { return "1440p" }
        if height >= 1080 || width >= 1920 { return "1080p" }
        if height >= 720 || width >= 1280 { return "720p" }
        if height >= 480 || width >= 854 { return "480p" }
        return "SD"
    }

    /// Desktop's `hdrFormatLabel`. A pq or hlg gamma decides the flavour from the format names; any other set gamma is SDR
    /// and gives nil; with no gamma, the format names alone decide.
    static func hdrLabel(gamma: String?, formats: [String?] = []) -> String? {
        let query = formats.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ").lowercased()
        let isDolbyVision = query.range(of: #"dolby\s*vision|\bdovi\b|\bdv\b"#, options: .regularExpression) != nil
        let isHDR10Plus = query.range(of: #"hdr10\s*\+|hdr10plus"#, options: .regularExpression) != nil
        let gammaValue = gamma ?? ""
        if gammaValue == "pq" || gammaValue == "hlg" {
            return isDolbyVision ? "DV" : isHDR10Plus ? "HDR10+" : "HDR"
        }
        if !gammaValue.isEmpty { return nil }
        if isDolbyVision { return "DV" }
        if isHDR10Plus { return "HDR10+" }
        if query.range(of: #"\bhdr10\+?\b|hdr10plus|\bhdr\b|\bhlg\b"#, options: .regularExpression) != nil { return "HDR" }
        return nil
    }

    /// Desktop's gold labels in the player: HDR, HDR10+ and DV take the highlight colour.
    static func isHighlighted(_ label: String) -> Bool {
        ["HDR", "HDR10+", "DV"].contains(label)
    }

    /// The labels under the player title, resolution then HDR, as Desktop's `QualityInfo` receives them. Nil entries drop out.
    static func infoLabels(width: Int, height: Int, gamma: String?, formats: [String?] = []) -> [String] {
        [resolutionLabel(width: width, height: height), hdrLabel(gamma: gamma, formats: formats)].compactMap { $0 }
    }

    /// Desktop's stremio renderer (`control-renderer-stremio.tsx`): with the setting on and a stream quality string, that string
    /// is printed under the title and the label badge is hidden. Desktop's default renderer does not check this setting.
    static func showsQualityText(showQualityInfo: Bool, quality: String?) -> Bool {
        showQualityInfo && !(quality ?? "").isEmpty
    }
}
