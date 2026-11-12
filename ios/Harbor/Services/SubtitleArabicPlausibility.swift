import Foundation

/// Desktop's `arabicLexicalPlausibility` (`lib/subtitles/encoding.ts`): how much of the decoded text reads as Arabic words,
/// used to tell Windows-1256 from ISO-8859-6 when a file is not UTF-8 and the subtitle language is Arabic.
enum SubtitleArabicPlausibility {
    /// Desktop's `COMMON_ARABIC_WORDS`.
    static let commonWords: Set<String> = [
        "\u{0623}\u{0646}\u{0627}", "\u{0623}\u{0646}\u{062A}", "\u{0625}\u{0644}\u{0649}", "\u{0627}\u{0644}\u{0622}\u{0646}",
        "\u{0627}\u{0644}\u{062A}\u{064A}", "\u{0627}\u{0644}\u{0630}\u{064A}", "\u{0627}\u{0644}\u{0633}\u{0644}\u{0627}\u{0645}",
        "\u{0627}\u{0644}\u{0644}\u{0647}", "\u{0641}\u{064A}", "\u{0643}\u{0627}\u{0646}", "\u{0644}\u{0627}",
        "\u{0644}\u{0643}\u{0646}", "\u{0644}\u{0645}", "\u{0644}\u{0646}", "\u{0645}\u{0627}", "\u{0645}\u{0646}",
        "\u{0647}\u{0630}\u{0627}", "\u{0647}\u{0630}\u{0647}", "\u{0647}\u{0648}", "\u{0647}\u{064A}",
        "\u{0648}\u{0647}\u{0648}", "\u{064A}\u{0627}", "\u{0633}\u{0644}\u{0627}\u{0645}", "\u{0639}\u{0627}\u{0644}\u{0645}",
        "\u{0627}\u{0644}\u{0639}\u{0627}\u{0644}\u{0645}", "\u{0628}\u{0627}\u{0644}\u{0639}\u{0627}\u{0644}\u{0645}",
        "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}"
    ]

    /// Desktop's `COMMON_ARABIC_SEQUENCES`.
    static let commonSequences: [String] = [
        "\u{0627}\u{0644}", "\u{0644}\u{0627}", "\u{0628}\u{0627}\u{0644}", "\u{0648}\u{0627}\u{0644}", "\u{0644}\u{0644}",
        "\u{0645}\u{0646}", "\u{0641}\u{064A}", "\u{0639}\u{0644}\u{0649}", "\u{0625}\u{0644}\u{0649}", "\u{0623}\u{0646}",
        "\u{0625}\u{0646}", "\u{0645}\u{0627}", "\u{0647}\u{0648}", "\u{0647}\u{064A}", "\u{0647}\u{0630}\u{0627}",
        "\u{0647}\u{0630}\u{0647}", "\u{0643}\u{0627}\u{0646}", "\u{0645}\u{0631}", "\u{0631}\u{062D}", "\u{062D}\u{0628}",
        "\u{0639}\u{0627}", "\u{0639}\u{0627}\u{0644}", "\u{0627}\u{0644}\u{0645}"
    ]

    private static let wordPattern = try? NSRegularExpression(pattern: "\\p{Script=Arabic}{2,}")

    /// 0 when the text has no Arabic word, otherwise the share of known words times 0.7 plus the density of known letter pairs times 0.3.
    static func score(_ text: String) -> Double {
        let normalized = text.precomposedStringWithCompatibilityMapping
        var cleaned = ""
        cleaned.unicodeScalars.append(contentsOf: normalized.unicodeScalars.filter { !isMark($0) })
        guard let wordPattern else { return 0 }
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        var words: [String] = []
        for match in wordPattern.matches(in: cleaned, options: [], range: range) {
            if let wordRange = Range(match.range, in: cleaned) { words.append(String(cleaned[wordRange])) }
        }
        guard !words.isEmpty else { return 0 }
        let known = words.filter { commonWords.contains($0) }.count
        let commonShare = Double(known) / Double(words.count)
        let joined = words.joined(separator: " ")
        var hits = 0
        for sequence in commonSequences {
            hits += max(0, joined.components(separatedBy: sequence).count - 1)
        }
        let density = min(1, Double(hits) / max(2, Double(joined.utf16.count) / 3))
        return commonShare * 0.7 + density * 0.3
    }

    /// Desktop strips U+0610-061A, U+0640, U+064B-065F, U+0670 and U+06D6-06ED (Quranic marks, tatweel and vowel marks) before counting.
    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if value >= 0x0610 && value <= 0x061A { return true }
        if value == 0x0640 { return true }
        if value >= 0x064B && value <= 0x065F { return true }
        if value == 0x0670 { return true }
        return value >= 0x06D6 && value <= 0x06ED
    }
}
