import Foundation

/// Desktop's `scoreGroupForUser` / `sortGroupsByRelevance` (`src/lib/iptv/group-relevance.ts`): groups
/// ordered by how well their name fits the person's region and preferred languages. Ties sort by name.
enum LiveTVGroupOrder {
    private static let regionTokens: [String: [String]] = [
        "US": ["US", "USA", "UNITED STATES", "AMERICA", "AMERICAN"], "CA": ["CA", "CAN", "CANADA", "CANADIAN"],
        "GB": ["UK", "GB", "BRITAIN", "BRITISH", "ENGLAND", "ENGLISH"], "AU": ["AU", "AUS", "AUSTRALIA", "AUSTRALIAN"],
        "NZ": ["NZ", "NEW ZEALAND"], "IE": ["IE", "IRELAND", "IRISH"], "IN": ["IN", "INDIA", "INDIAN"],
        "FR": ["FR", "FRANCE", "FRENCH"], "DE": ["DE", "GERMANY", "DEUTSCH", "GERMAN"], "IT": ["IT", "ITALY", "ITALIAN"],
        "ES": ["ES", "SPAIN", "SPANISH"], "PT": ["PT", "PORTUGAL", "PORTUGUESE"], "BR": ["BR", "BRAZIL", "BRASIL"],
        "MX": ["MX", "MEXICO", "MEXICAN"], "NL": ["NL", "NETHERLANDS", "DUTCH"], "SE": ["SE", "SWEDEN", "SWEDISH"],
        "NO": ["NO", "NORWAY", "NORWEGIAN"], "DK": ["DK", "DENMARK", "DANISH"], "FI": ["FI", "FINLAND", "FINNISH"],
        "PL": ["PL", "POLAND", "POLISH"], "RU": ["RU", "RUSSIA", "RUSSIAN"], "TR": ["TR", "TURKEY", "TURKISH"],
        "JP": ["JP", "JAPAN", "JAPANESE"], "KR": ["KR", "KOREA", "KOREAN"], "CN": ["CN", "CHINA", "CHINESE"],
    ]
    private static let languageTokens: [String: [String]] = [
        "english": ["EN", "ENG", "ENGLISH", "US", "UK", "CA", "AU"], "spanish": ["ES", "ESP", "SPANISH", "ESPANOL", "LATINO"],
        "french": ["FR", "FRA", "FRENCH", "FRANCAIS"], "german": ["DE", "GER", "GERMAN", "DEUTSCH"],
        "italian": ["IT", "ITA", "ITALIAN", "ITALIANO"], "portuguese": ["PT", "POR", "PORTUGUESE", "BR", "BRAZIL"],
        "dutch": ["NL", "DUTCH", "NEDERLANDS"], "russian": ["RU", "RUS", "RUSSIAN"], "arabic": ["AR", "ARA", "ARABIC", "ARAB"],
        "turkish": ["TR", "TUR", "TURKISH"], "hindi": ["HI", "HIN", "HINDI", "INDIAN"], "japanese": ["JA", "JPN", "JAPANESE"],
        "korean": ["KO", "KOR", "KOREAN"], "chinese": ["ZH", "CHI", "CHINESE", "MANDARIN"], "polish": ["PL", "POL", "POLISH"],
        "swedish": ["SV", "SWE", "SWEDISH"], "norwegian": ["NO", "NOR", "NORWEGIAN"], "danish": ["DA", "DAN", "DANISH"],
        "finnish": ["FI", "FIN", "FINNISH"],
    ]
    private static let neutralBump: Set<String> = ["ENTERTAINMENT", "NEWS", "SPORTS", "MOVIES", "KIDS", "DOCUMENTARY"]

    static func score(_ group: String, region: String, preferredLanguages: [String]) -> Int {
        let tokens = tokenize(group)
        guard let head = tokens.first else { return 0 }
        let regionWords = regionTokens[region.uppercased()] ?? []
        if regionWords.contains(head) { return 100 }
        if regionWords.contains(where: { tokens.contains($0) }) { return 80 }
        for (index, language) in preferredLanguages.enumerated() {
            guard let langTokens = languageTokens[language.lowercased()] else { continue }
            if langTokens.contains(head) { return 60 - index * 5 }
            if langTokens.contains(where: { tokens.contains($0) }) { return 45 - index * 5 }
        }
        return neutralBump.contains(head) ? 5 : 0
    }

    /// `sortGroupsByRelevance`: higher score first, then `localeCompare` order for equal scores.
    static func sortedGroups(_ groups: [String], region: String, preferredLanguages: [String]) -> [String] {
        let scored = groups.map { (group: $0, score: score($0, region: region, preferredLanguages: preferredLanguages)) }
        return scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.group.localizedCompare(b.group) == .orderedAscending
        }.map { $0.group }
    }

    /// Desktop `tokenize`: uppercase, split on whitespace and `| / _ - :`, keep only A-Z in each token.
    private static func tokenize(_ group: String) -> [String] {
        group.uppercased()
            .split(whereSeparator: { $0.isWhitespace || "|/_-:".contains($0) })
            .map { String($0.filter { $0.isASCII && $0.isLetter }) }
            .filter { !$0.isEmpty }
    }
}

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

    /// Desktop's live-screen filter (`use-channel-filter.ts`): the trimmed, lowercased query must match
    /// "name group" with `arabicAwareMatch`; an empty query matches every channel. No minimum length here.
    static func channelMatches(_ channel: LiveChannel, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return matches("\(channel.name) \(channel.group ?? "")", needle: needle)
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
