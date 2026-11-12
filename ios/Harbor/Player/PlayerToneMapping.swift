import Foundation

/// Desktop's "Tone-mapping curve" (`ColorHdrSection` in `views/settings/mpv-panel/dials.tsx`). Desktop keeps it as the
/// `tone-mapping` key of `mpvTweaks`; iOS keeps the same mpv value under its own preference key and applies it when a
/// video opens, after the HDR-to-SDR block and the quality profile, as Desktop applies its tweaks after both.
enum ToneMappingCurve: String, CaseIterable, Identifiable, Sendable {
    case auto = ""
    case reference = "bt.2390"
    case filmic = "hable"
    case balanced = "mobius"
    case soft = "reinhard"
    case modern = "spline"

    var id: String { rawValue }

    /// Desktop's `TONEMAP` labels, in Desktop's order. The settings control translates them.
    var title: String {
        switch self {
        case .auto: return "Auto (recommended)"
        case .reference: return "Reference (bt.2390)"
        case .filmic: return "Filmic (Hable)"
        case .balanced: return "Balanced (Mobius)"
        case .soft: return "Soft (Reinhard)"
        case .modern: return "Modern (Spline)"
        }
    }
}

enum PlayerToneMapping {
    /// The UserDefaults key. An empty or missing value is Auto, as an absent `tone-mapping` tweak is on Desktop.
    static let curveKey = "mpvToneMapping"

    /// A stored value this build does not know falls back to Auto instead of reaching mpv.
    static func curve(_ stored: String?) -> ToneMappingCurve {
        guard let stored = stored else { return .auto }
        return ToneMappingCurve(rawValue: stored) ?? .auto
    }

    /// The mpv options the curve adds. Auto adds none: mpv keeps its own mapping, or the spline curve the
    /// HDR-to-SDR block asked for, exactly as Desktop leaves the tweak out.
    static func mpvOptions(stored: String?) -> [(String, String)] {
        let choice = curve(stored)
        if choice == .auto { return [] }
        return [("tone-mapping", choice.rawValue)]
    }

    /// The same options written as Desktop writes a tweak, one `name=value` line each.
    static func mpvLines(stored: String?) -> [String] {
        return mpvOptions(stored: stored).map { "\($0.0)=\($0.1)" }
    }
}
