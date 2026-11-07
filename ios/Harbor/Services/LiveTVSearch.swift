import Foundation

/// Desktop's Live TV search: `searchLiveTvChannels` in `src/lib/search.ts` (lines 96-126) and
/// `arabicAwareMatch` / `normalizeArabic` in `src/lib/iptv/rtl.ts`.
/// Channels match when the query appears in "name group" (case-insensitive, Arabic-aware). Results keep
/// the source order, the first channel per stream URL wins, and the list stops at `limit` (Desktop: 8).
enum LiveTVSearch {
    static let defaultLimit = 8

    static func channels(matching query: String, in channels: [LiveChannel], limit: Int = defaultLimit) -> [LiveChannel] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.utf16.count >= 2, limit > 0 else { return [] }
        var hits: [LiveChannel] = []
        var seenURLs = Set<String>()
        for channel in channels {
            if seenURLs.contains(channel.url) { continue }
            guard matches("\(channel.name) \(channel.group ?? "")", needle: needle) else { continue }
            seenURLs.insert(channel.url)
            hits.append(channel)
            if hits.count >= limit { break }
        }
        return hits
    }

    /// `arabicAwareMatch`: a plain case-insensitive substring test, then, when either side has Arabic
    /// letters, the same test on the normalised forms.
    static func matches(_ haystack: String, needle: String) -> Bool {
        if haystack.lowercased().contains(needle) { return true }
        guard hasArabic(haystack) || hasArabic(needle) else { return false }
        return normalizeArabic(haystack).contains(normalizeArabic(needle))
    }

    static func hasArabic(_ text: String) -> Bool {
        text.unicodeScalars.contains { isArabicBlock($0.value) }
    }

    /// `normalizeArabic`: NFKC, drop invisible marks and harakat, fold alef, teh marbuta, alef maksura,
    /// waw and yeh variants, map Arabic-Indic digits to ASCII, collapse whitespace, lowercase, trim.
    static func normalizeArabic(_ text: String) -> String {
        var folded = String.UnicodeScalarView()
        for scalar in text.precomposedStringWithCompatibilityMapping.unicodeScalars {
            if isInvisible(scalar.value) || isHarakat(scalar.value) { continue }
            folded.append(foldArabic(scalar))
        }
        return String(folded).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    private static func isArabicBlock(_ value: UInt32) -> Bool {
        switch value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
            return true
        default:
            return false
        }
    }

    private static func isInvisible(_ value: UInt32) -> Bool {
        switch value {
        case 0x200B...0x200F, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF:
            return true
        default:
            return false
        }
    }

    private static func isHarakat(_ value: UInt32) -> Bool {
        switch value {
        case 0x064B...0x0652, 0x0670, 0x0640:
            return true
        default:
            return false
        }
    }

    private static func foldArabic(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        switch scalar.value {
        case 0x0622, 0x0623, 0x0625, 0x0671: return "\u{0627}"
        case 0x0629: return "\u{0647}"
        case 0x0649, 0x0626: return "\u{064A}"
        case 0x0624: return "\u{0648}"
        case 0x0660...0x0669, 0x06F0...0x06F9: return Unicode.Scalar(UInt8(0x30 + (scalar.value & 0xF)))
        default: return scalar
        }
    }
}
