import Foundation

/// Desktop's `SubtitleMatchConfidence` (`src/lib/subtitles/release-match.ts:16`).
enum SubtitleMatchLevel: Sendable {
    case exact, high, medium, low, incompatible

    /// Desktop `subtitleConfidenceRank` (`release-match.ts:18-30`).
    var rank: Int {
        switch self {
        case .exact: return 5
        case .high: return 4
        case .medium: return 3
        case .low: return 2
        case .incompatible: return 0
        }
    }
}

/// Desktop's `SubtitleTimingStatus` (`candidate-preflight.ts`). iOS has no timing preflight yet, so candidates default to `.notChecked`.
enum SubtitleTimingStatus: Sendable {
    case aligned, fixedOffset, drifting, unmeasurable, differentCut, invalid, notChecked
}

/// One subtitle track as the selection rules see it. Built from `PlayerState.Track` by `SubtitleSelectionPlayerTrack.swift`.
struct SubtitleSelectionCandidate: Equatable, Sendable {
    var id: Int
    var language: String = ""
    /// The mpv title only. Desktop also matches its label, but iOS's `Track.label` joins title, language and codec, so it is not used.
    var title: String = ""
    var forced: Bool = false
    var hearingImpaired: Bool = false
    var external: Bool = false
    var codec: String = ""
    var isDefault: Bool = false
    var matchScore: Double = 0
    var matchLevel: SubtitleMatchLevel = .low
    var timing: SubtitleTimingStatus = .notChecked
    /// Desktop's `prepared && autoSelectionEligible` for external tracks. iOS adds an external file to mpv only after it has loaded, so the adapter passes true.
    var prepared: Bool = true
}

/// What the player has selected right now, split the way Desktop's track autoload tells them apart.
enum SubtitleSelectionOrigin: Equatable, Sendable {
    /// Nothing is selected.
    case none
    /// Something is selected but Harbor did not choose it (mpv's own default).
    case playerDefault
    /// Harbor chose it automatically (Desktop `autoSubIdRef`).
    case automatic
    /// The person chose it.
    case manual
}

/// The settings and state the selection rules read. The caller fills `suppressed` when subtitles are off for this video, a remembered choice applies, or a pre-playback choice exists.
struct SubtitleAutoSelectionContext: Equatable, Sendable {
    var origin: SubtitleSelectionOrigin = .none
    var languages: [String] = []
    var preferEmbedded = false
    var autoUpgrade = false
    var blockWords: [String] = []
    var suppressed = false
}

/// Desktop's `subtitlePreselect` value: the pre-playback choice (`src.subtitlePreselect`).
enum SubtitlePreselectChoice: Equatable, Sendable {
    case off
    case track(id: Int)
}

/// Pure subtitle selection rules ported from Desktop 0.9.132. Nothing here touches mpv, UserDefaults or the network.
enum SubtitleSelectionPolicy {
    // MARK: Language score and eligibility

    /// Desktop `langScore` (`src/lib/subtitles/language.ts:351-365`). Exact match scores `(n - i) * 2`, a base-language match `(n - i) * 2 - 1`, no match `-1`, and an empty list `0`.
    static func languageScore(_ language: String, preferred: [String]) -> Int {
        if preferred.isEmpty { return 0 }
        let normalized = SubtitleLanguages.normalize(language)
        var exactIndex = -1
        var baseIndex = -1
        for (index, preference) in preferred.enumerated() {
            let code = SubtitleLanguages.normalize(preference)
            if exactIndex == -1 && code == normalized { exactIndex = index }
            if baseIndex == -1 && baseLanguage(code) == baseLanguage(normalized) { baseIndex = index }
        }
        if exactIndex != -1 { return (preferred.count - exactIndex) * 2 }
        if baseIndex != -1 { return (preferred.count - baseIndex) * 2 - 1 }
        return -1
    }

    private static func baseLanguage(_ code: String) -> String {
        String(code.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    /// Desktop `isAutoSelectableSubtitleTrack` (`track-selection.ts:36-43`).
    static func isAutoSelectable(_ candidate: SubtitleSelectionCandidate) -> Bool {
        if candidate.external && !candidate.prepared { return false }
        if candidate.timing == .differentCut || candidate.timing == .invalid { return false }
        return candidate.matchLevel != .incompatible
    }

    /// Desktop `isForcedTrack` (`track-selection.ts:21-23`): the word `forced` as a whole word, case-insensitive (`\bforced\b`).
    static func hasForcedWord(_ text: String) -> Bool {
        let characters = Array(text.lowercased())
        let word = Array("forced")
        guard characters.count >= word.count else { return false }
        for start in 0...(characters.count - word.count) {
            guard Array(characters[start..<(start + word.count)]) == word else { continue }
            let beforeOK = start == 0 || !isWordCharacter(characters[start - 1])
            let afterIndex = start + word.count
            let afterOK = afterIndex == characters.count || !isWordCharacter(characters[afterIndex])
            if beforeOK && afterOK { return true }
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
    }

    /// Desktop's eligibility filter in `pickDesiredSubtitleTrack` (`track-selection.ts:72-79`).
    static func isPickEligible(_ candidate: SubtitleSelectionCandidate, languages: [String]) -> Bool {
        if candidate.forced || hasForcedWord(candidate.title) { return false }
        guard isAutoSelectable(candidate) else { return false }
        return languageScore(candidate.language, preferred: languages) >= 0
    }

    // MARK: Choosing a track

    private static func flag(_ value: Bool) -> Int { value ? 1 : 0 }

    /// Desktop `sourceRank` (`track-selection.ts:25-29`).
    private static func sourceRank(_ candidate: SubtitleSelectionCandidate, preferEmbedded: Bool) -> Int {
        if !candidate.external { return preferEmbedded ? 3 : 0 }
        return candidate.title.lowercased().contains("opensubtitles") ? 1 : 2
    }

    /// Desktop `confidenceRank` (`track-selection.ts:31-34`).
    private static func confidenceRank(_ candidate: SubtitleSelectionCandidate, preferEmbedded: Bool) -> Int {
        if !candidate.external { return preferEmbedded ? 4 : 3 }
        return candidate.matchLevel.rank
    }

    /// Desktop comparator in `pickDesiredSubtitleTrack` (`track-selection.ts:81-99`). A negative result means `a` is preferred.
    static func compare(_ a: SubtitleSelectionCandidate, _ b: SubtitleSelectionCandidate, languages: [String], preferEmbedded: Bool) -> Int {
        let languageDelta = languageScore(b.language, preferred: languages) - languageScore(a.language, preferred: languages)
        if languageDelta != 0 { return languageDelta }
        if preferEmbedded {
            let embeddedDelta = flag(!b.external) - flag(!a.external)
            if embeddedDelta != 0 { return embeddedDelta }
        }
        let timingDelta = flag(b.timing == .aligned) - flag(a.timing == .aligned)
        if timingDelta != 0 { return timingDelta }
        let confidenceDelta = confidenceRank(b, preferEmbedded: preferEmbedded) - confidenceRank(a, preferEmbedded: preferEmbedded)
        if confidenceDelta != 0 { return confidenceDelta }
        if a.matchScore != b.matchScore { return b.matchScore > a.matchScore ? 1 : -1 }
        let sourceDelta = sourceRank(b, preferEmbedded: preferEmbedded) - sourceRank(a, preferEmbedded: preferEmbedded)
        if sourceDelta != 0 { return sourceDelta }
        return flag(b.isDefault) - flag(a.isDefault)
    }

    /// Desktop `pickDesiredSubtitleTrack` (`track-selection.ts:67-101`). Ties keep the earlier track, as Desktop's stable sort does.
    static func desiredTrack(among candidates: [SubtitleSelectionCandidate], languages: [String], preferEmbedded: Bool) -> SubtitleSelectionCandidate? {
        let eligible = candidates.filter { isPickEligible($0, languages: languages) }
        guard var best = eligible.first else { return nil }
        for candidate in eligible.dropFirst() where compare(candidate, best, languages: languages, preferEmbedded: preferEmbedded) < 0 {
            best = candidate
        }
        return best
    }

    /// Desktop `desiredSubtitleIsEmbedded` (`track-selection.ts:107-115`). Uses the unfiltered track list, as Desktop does.
    static func desiredIsEmbedded(_ candidates: [SubtitleSelectionCandidate], languages: [String], preferEmbedded: Bool) -> Bool {
        guard preferEmbedded else { return false }
        guard let desired = desiredTrack(among: candidates, languages: languages, preferEmbedded: true) else { return false }
        return !desired.external
    }

    // MARK: Block words

    /// Desktop `audio-tab.tsx:44-47`: comma split, trimmed, empties dropped, duplicates removed in order.
    static func blockWords(fromText text: String) -> [String] {
        var seen = Set<String>()
        var words: [String] = []
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let word = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty && seen.insert(word).inserted { words.append(word) }
        }
        return words
    }

    /// Desktop `blockWords` (`use-track-autoload.ts:895-897`): trimmed, lowercased, empties dropped.
    static func normalizedBlockWords(_ words: [String]) -> [String] {
        words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
    }

    /// Desktop `trackMatchesWords` (`use-track-autoload.ts:899-902`): a plain substring test on the lowercased title.
    static func isBlocked(_ candidate: SubtitleSelectionCandidate, words: [String]) -> Bool {
        let title = candidate.title.lowercased()
        return words.contains { title.contains($0) }
    }

    /// Desktop `allow` (`use-track-autoload.ts:801-806`). When every track matches, the full list is kept.
    static func allowed(_ candidates: [SubtitleSelectionCandidate], blockWords: [String]) -> [SubtitleSelectionCandidate] {
        let words = normalizedBlockWords(blockWords)
        if words.isEmpty { return candidates }
        let kept = candidates.filter { !isBlocked($0, words: words) }
        return kept.isEmpty ? candidates : kept
    }

    // MARK: Auto selection and upgrades

    /// Whether Harbor may change the selection, given what the person or mpv already did. Desktop `subtitleAutoloadLateSelectionAllowed` (`autoload-run.ts:36-43`) for late arrivals, and `use-track-autoload.ts:839-843` for the normal path.
    static func replacementAllowed(origin: SubtitleSelectionOrigin, autoUpgrade: Bool, lateArrival: Bool) -> Bool {
        if lateArrival {
            if origin == .none { return true }
            return autoUpgrade && origin == .automatic
        }
        switch origin {
        case .manual: return false
        case .automatic: return autoUpgrade
        case .none, .playerDefault: return true
        }
    }

    /// The track Harbor should select among the tracks mpv already reports, or nil to leave the selection alone. Desktop `use-track-autoload.ts:838-863`. Caller compares the result with the current track before it calls mpv.
    static func trackToAutoSelect(among candidates: [SubtitleSelectionCandidate], context: SubtitleAutoSelectionContext) -> SubtitleSelectionCandidate? {
        guard !context.suppressed, !context.languages.isEmpty else { return nil }
        guard replacementAllowed(origin: context.origin, autoUpgrade: context.autoUpgrade, lateArrival: false) else { return nil }
        let pool = allowed(candidates, blockWords: context.blockWords)
        return desiredTrack(among: pool, languages: context.languages, preferEmbedded: context.preferEmbedded)
    }

    /// Whether a freshly fetched external candidate may be selected. `existing` are the tracks mpv already reports, before the arrival. Desktop `use-track-autoload.ts:343-371`, with the `keepEmbedded` veto that stops a download from replacing the embedded track Desktop prefers.
    static func allowsExternalArrival(existing: [SubtitleSelectionCandidate], lateArrival: Bool, context: SubtitleAutoSelectionContext) -> Bool {
        if context.suppressed { return false }
        if lateArrival {
            guard replacementAllowed(origin: context.origin, autoUpgrade: context.autoUpgrade, lateArrival: true) else { return false }
        } else if context.origin == .manual {
            return false
        }
        return !desiredIsEmbedded(existing, languages: context.languages, preferEmbedded: context.preferEmbedded)
    }

    // MARK: Pre-playback choice

    /// Desktop default in the pre-playback picker (`subtitle-select-step.tsx:42-48`): the best candidate, or off when there is none.
    static func preselectDefault(best: SubtitleSelectionCandidate?) -> SubtitlePreselectChoice {
        guard let best = best else { return .off }
        return .track(id: best.id)
    }

    /// Desktop `openPlayerGated` (`play-picker.tsx:557-564`): whether the pre-playback step is shown for this source.
    static func preselectApplies(enabled: Bool, isDownload: Bool, inSession: Bool, autoFired: Bool, isLive: Bool, metaID: String?, mediaType: String) -> Bool {
        guard enabled, !isDownload, !inSession, !autoFired, !isLive else { return false }
        if let metaID = metaID, metaID.hasPrefix("iptv:") { return false }
        return ["movie", "series", "anime"].contains(mediaType)
    }

    /// Desktop `use-track-autoload.ts:361,546,834`: any pre-playback choice stops automatic selection.
    static func automaticSelectionSuppressed(by choice: SubtitlePreselectChoice?) -> Bool {
        choice != nil
    }

    // MARK: Secondary line size

    /// Desktop `subtitle-overlay.tsx:112-115`: default 0.85, clamped to 0.4...1.4.
    static func secondaryScale(_ stored: Double?) -> Double {
        guard let stored = stored, stored.isFinite else { return 0.85 }
        return min(1.4, max(0.4, stored))
    }
}

/// Desktop's ASS size normalisation (`src/lib/player/ass-header.ts`, `use-ass-normalize.ts`, `use-player-media.ts:220-237`, `sub-style.ts:79-95`).
enum AssSizeNormalization {
    static let referenceHeight = 720.0
    static let minimumScale = 0.2
    static let maximumScale = 6.0
    static let minimumFraction = 0.02
    static let maximumFraction = 0.22

    private struct AssStyle {
        let name: String
        var size: Double
    }

    /// Desktop `computeAssBaseFactor` (`ass-header.ts:160-172`). nil when the dominant style cannot be measured.
    static func baseFactor(assText text: String) -> Double? {
        let styles = assStyles(text)
        if styles.isEmpty { return nil }
        let playResY = playResolutionY(lines(text))
        guard let dominant = dominantDialogueStyle(text, styles: styles),
              let style = styles.first(where: { $0.name == dominant }),
              style.size > 0 else { return nil }
        let fraction = style.size / Double(playResY)
        if fraction < minimumFraction || fraction > maximumFraction { return nil }
        let factor = Double(playResY) / (referenceHeight * style.size)
        return factor.isFinite && factor > 0 ? factor : nil
    }

    /// Desktop `assScaleFromFactor` (`ass-header.ts:174-177`).
    static func scale(baseFactor: Double, targetFontSize: Double) -> Double {
        let target = targetFontSize.isFinite ? targetFontSize : 32
        let value = baseFactor * target
        guard value.isFinite else { return minimumScale }
        return min(maximumScale, max(minimumScale, value))
    }

    /// Desktop enable gate (`use-player-media.ts:220,229-231`) for iOS, where mpv renders every track: the setting is on, the selected track is ASS, and the override is "no" or "scale".
    static func isActive(normalizeSize: Bool, assOverride: String, selectedIsASS: Bool) -> Bool {
        guard normalizeSize, selectedIsASS else { return false }
        return assOverride == "no" || assOverride == "scale"
    }

    /// The `sub-scale` value to send to mpv with `sub-ass-override=scale` (`sub-style.ts:79-81,95`). nil when normalisation does not apply.
    static func mpvSubScale(active: Bool, baseFactor: Double?, targetFontSize: Double) -> Double? {
        guard active, let factor = baseFactor else { return nil }
        return scale(baseFactor: factor, targetFontSize: targetFontSize)
    }

    /// Desktop `isAssTrack` (`sub-format.ts:3-16`): the codec names ASS or SSA, or the external file ends in `.ass` or `.ssa`.
    static func isASSTrack(codec: String, title: String) -> Bool {
        let upper = codec.uppercased()
        if upper.contains("ASS") || upper.contains("SSA") || upper.contains("SUBSTATION") || upper.contains("SUB STATION") {
            return true
        }
        let lower = title.lowercased()
        return lower.hasSuffix(".ass") || lower.hasSuffix(".ssa")
    }

    // MARK: Parsing (Desktop ass-header.ts)

    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
    }

    /// Desktop `matchSection`: the lines after a header, up to the next `[section]` line.
    private static func sectionLines(_ text: String, headers: [String]) -> [String]? {
        let all = lines(text)
        guard let start = all.firstIndex(where: { headers.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }) else {
            return nil
        }
        var section: [String] = []
        for line in all[(start + 1)...] {
            if isSectionHeader(line) { break }
            section.append(line)
        }
        return section
    }

    private static func isSectionHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
    }

    /// Desktop `/^Name:\s*(.*)$/i` on one line: the text after `Name:`, leading blanks removed.
    private static func directive(_ line: String, _ name: String) -> String? {
        let prefix = name + ":"
        guard line.count >= prefix.count, line.prefix(prefix.count).lowercased() == prefix.lowercased() else { return nil }
        return String(line.dropFirst(prefix.count).drop(while: { $0 == " " || $0 == "\t" }))
    }

    private static func field(_ fields: [String], _ index: Int) -> String {
        index >= 0 && index < fields.count ? fields[index] : ""
    }

    /// Desktop `parseAssStyles` (`ass-header.ts:74-99`), keeping insertion order. A repeated name replaces the size and keeps its place.
    private static func assStyles(_ text: String) -> [AssStyle] {
        guard let section = sectionLines(text, headers: ["[v4 styles]", "[v4+ styles]"]) else { return [] }
        var styles: [AssStyle] = []
        var nameColumn = -1
        var sizeColumn = -1
        for line in section {
            if let format = directive(line, "Format") {
                let columns = format.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                nameColumn = columns.firstIndex(of: "name") ?? -1
                sizeColumn = columns.firstIndex(of: "fontsize") ?? -1
                continue
            }
            guard nameColumn >= 0, sizeColumn >= 0, let style = directive(line, "Style") else { continue }
            let fields = style.components(separatedBy: ",")
            let name = field(fields, nameColumn).trimmingCharacters(in: .whitespaces)
            guard let size = leadingDouble(field(fields, sizeColumn).trimmingCharacters(in: .whitespaces)), !name.isEmpty else { continue }
            if let index = styles.firstIndex(where: { $0.name == name }) {
                styles[index].size = size
            } else {
                styles.append(AssStyle(name: name, size: size))
            }
        }
        return styles
    }

    /// Desktop `parseFloat` for the simple numbers ASS uses.
    private static func leadingDouble(_ text: String) -> Double? {
        var number = ""
        for character in text {
            if (character.isASCII && character.isNumber) || character == "." || (character == "-" && number.isEmpty) {
                number.append(character)
            } else {
                break
            }
        }
        return Double(number)
    }

    private static func leadingInt(_ text: String) -> Int? {
        let digits = text.prefix(while: { $0.isASCII && $0.isNumber })
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func firstInteger(_ lines: [String], key: String) -> Int {
        for line in lines {
            if let rest = directive(line, key), let value = leadingInt(rest) { return value }
        }
        return 0
    }

    /// Desktop `inferPlayResY` (`ass-header.ts:66-72`).
    private static func playResolutionY(_ lines: [String]) -> Int {
        let height = firstInteger(lines, key: "PlayResY")
        if height > 0 { return height }
        let width = firstInteger(lines, key: "PlayResX")
        if width > 0 { return width == 1280 ? 1024 : (width * 3) / 4 }
        return 288
    }

    /// Desktop `splitFields`: the last column keeps any commas.
    private static func splitFields(_ line: String, columns: Int) -> [String] {
        guard columns > 0 else { return line.components(separatedBy: ",") }
        var parts: [String] = []
        var rest = Substring(line)
        for _ in 0..<(columns - 1) {
            guard let comma = rest.firstIndex(of: ",") else {
                parts.append(String(rest))
                rest = ""
                continue
            }
            parts.append(String(rest[..<comma]))
            rest = rest[rest.index(after: comma)...]
        }
        parts.append(String(rest))
        return parts
    }

    /// Desktop `SIGN_TAGS` (`ass-header.ts:6`): `\pos`, `\move`, `\clip`, `\iclip` and `\p1` to `\p9`.
    private static func hasSignTag(_ body: String) -> Bool {
        let lower = body.lowercased()
        if lower.contains("\\pos") || lower.contains("\\move") || lower.contains("\\clip") || lower.contains("\\iclip") {
            return true
        }
        let scalars = Array(lower.unicodeScalars)
        if scalars.count < 3 { return false }
        for index in 0...(scalars.count - 3) where scalars[index] == "\\" && scalars[index + 1] == "p" {
            let digit = scalars[index + 2].value
            if digit >= 49 && digit <= 57 { return true }
        }
        return false
    }

    /// Desktop `visibleLen` (`ass-header.ts:59-64`): drop `{...}` blocks, turn `\N`, `\n` and `\h` into spaces, trim, count UTF-16 units.
    private static func visibleLength(_ body: String) -> Int {
        let characters = Array(body)
        var kept: [Character] = []
        var index = 0
        while index < characters.count {
            if characters[index] == "{", let close = characters[index...].firstIndex(of: "}") {
                index = close + 1
                continue
            }
            kept.append(characters[index])
            index += 1
        }
        var spaced: [Character] = []
        var position = 0
        while position < kept.count {
            if kept[position] == "\\" && position + 1 < kept.count && "Nnh".contains(kept[position + 1]) {
                spaced.append(" ")
                position += 2
                continue
            }
            spaced.append(kept[position])
            position += 1
        }
        return String(spaced).trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
    }

    private static func isDialogueName(_ name: String) -> Bool {
        ["default", "dialogue", "dialog", "main", "regular"].contains(name.lowercased())
    }

    private static func styleIndex(_ name: String, _ styles: [AssStyle]) -> Int {
        styles.firstIndex(where: { $0.name == name }) ?? 0
    }

    /// Desktop ordering in `dominantDialogueStyle` (`ass-header.ts:145-154`). Returns true when `a` ranks before `b`.
    private static func dominantPrecedes(_ a: String, _ b: String, counts: [String: Int], characters: [String: Int], styles: [AssStyle]) -> Bool {
        let countA = counts[a] ?? 0
        let countB = counts[b] ?? 0
        if countA != countB { return countA > countB }
        let charsA = characters[a] ?? 0
        let charsB = characters[b] ?? 0
        if charsA != charsB { return charsA > charsB }
        let dialogueA = isDialogueName(a)
        let dialogueB = isDialogueName(b)
        if dialogueA != dialogueB { return dialogueA }
        return styleIndex(a, styles) < styleIndex(b, styles)
    }

    /// Desktop `fallbackStyle` (`ass-header.ts:101-112`).
    private static func fallbackStyle(_ styles: [AssStyle]) -> String? {
        var firstPositive: String?
        for style in styles where style.size > 0 {
            if style.name.lowercased() == "default" { return style.name }
            if firstPositive == nil { firstPositive = style.name }
        }
        return firstPositive ?? styles.first?.name
    }

    /// Desktop `dominantDialogueStyle` (`ass-header.ts:114-158`): the style with the most non-sign dialogue lines.
    private static func dominantDialogueStyle(_ text: String, styles: [AssStyle]) -> String? {
        var counts: [String: Int] = [:]
        var characters: [String: Int] = [:]
        if let section = sectionLines(text, headers: ["[events]"]) {
            var styleColumn = -1
            var textColumn = -1
            var columnCount = 0
            for line in section {
                if let format = directive(line, "Format") {
                    let columns = format.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    columnCount = columns.count
                    styleColumn = columns.firstIndex(of: "style") ?? -1
                    textColumn = columns.firstIndex(of: "text") ?? -1
                    continue
                }
                guard styleColumn >= 0, textColumn >= 0, let dialogue = directive(line, "Dialogue") else { continue }
                let fields = splitFields(dialogue, columns: columnCount)
                let name = field(fields, styleColumn).trimmingCharacters(in: .whitespaces)
                let body = field(fields, textColumn)
                if hasSignTag(body) { continue }
                if !styles.contains(where: { $0.name == name }) { continue }
                counts[name, default: 0] += 1
                characters[name, default: 0] += visibleLength(body)
            }
        }
        let ranked = counts.keys.sorted { dominantPrecedes($0, $1, counts: counts, characters: characters, styles: styles) }
        if let first = ranked.first { return first }
        return fallbackStyle(styles)
    }
}
