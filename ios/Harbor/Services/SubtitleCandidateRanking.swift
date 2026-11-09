import Foundation

/// Desktop's auto-selection order for subtitle candidates (`rankSubtitleCandidates` in `lib/subtitles/candidate-ranking.ts`).
/// Without stream hints Desktop scores every candidate alike on the movie hash, release affinity, source rank, timing and
/// episode, so those keys are left out here. The hash flag is not carried by `SubtitleProviderCandidate` yet.
enum SubtitleCandidateRanking {
    /// Desktop's filters that need no hints: forced and foreign-only tracks are never auto-picked, and when languages
    /// are preferred only candidates with a language score remain.
    static func autoPickable(_ candidates: [SubtitleProviderCandidate], preferredLanguages: [String]) -> [SubtitleProviderCandidate] {
        candidates.filter { !$0.forced && !$0.foreignOnly }
            .filter { preferredLanguages.isEmpty || languageScore($0, preferredLanguages) >= 0 }
    }

    /// The candidates in Desktop's auto-selection order, best first.
    static func rank(_ candidates: [SubtitleProviderCandidate], preferredLanguages: [String]) -> [SubtitleProviderCandidate] {
        autoPickable(candidates, preferredLanguages: preferredLanguages).sorted { compare($0, $1, preferredLanguages: preferredLanguages) < 0 }
    }

    /// Negative when `a` comes first. Each step mirrors one `b - a` comparison of Desktop's sort.
    static func compare(_ a: SubtitleProviderCandidate, _ b: SubtitleProviderCandidate, preferredLanguages: [String]) -> Int {
        let language = desc(languageScore(b, preferredLanguages), languageScore(a, preferredLanguages))
        if language != 0 { return language }
        let strong = desc(strongProviderRank(b), strongProviderRank(a))
        if strong != 0 { return strong }
        if strongProviderRank(a) > 0 {
            let strongScore = desc(providerScore(b), providerScore(a))
            if strongScore != 0 { return strongScore }
        }
        let weak = desc(weakProviderRank(b), weakProviderRank(a))
        if weak != 0 { return weak }
        let providerMatch = desc(providerScore(b), providerScore(a))
        if providerMatch != 0 { return providerMatch }
        let machine = flag(a.machineTranslated) - flag(b.machineTranslated)
        if machine != 0 { return machine }
        let trusted = flag(b.fromTrusted) - flag(a.fromTrusted)
        if trusted != 0 { return trusted }
        let rating = desc(b.ratingScore ?? 0, a.ratingScore ?? 0)
        if rating != 0 { return rating }
        let ratingCount = desc(Double(b.ratingTotal ?? 0), Double(a.ratingTotal ?? 0))
        if ratingCount != 0 { return ratingCount }
        let downloads = desc(Double(b.downloads), Double(a.downloads))
        if downloads != 0 { return downloads }
        let keyA = stableKey(a), keyB = stableKey(b)
        return keyA < keyB ? -1 : (keyA > keyB ? 1 : 0)
    }

    /// Desktop `langScore` through the iOS scorer (-1 for no match, 0 when no languages are preferred).
    static func languageScore(_ candidate: SubtitleProviderCandidate, _ preferredLanguages: [String]) -> Int {
        SubtitleSelectionPolicy.languageScore(candidate.subtitle.lang ?? "", preferred: preferredLanguages)
    }

    /// Desktop `strongProviderConfidenceRank`: exact 2, high 1, anything else 0.
    static func strongProviderRank(_ candidate: SubtitleProviderCandidate) -> Double {
        switch candidate.matchConfidence {
        case "exact": return 2
        case "high": return 1
        default: return 0
        }
    }

    /// Desktop `weakProviderConfidenceRank`: medium 3, low 2, unknown 1, anything else 0.
    static func weakProviderRank(_ candidate: SubtitleProviderCandidate) -> Double {
        switch candidate.matchConfidence {
        case "medium": return 3
        case "low": return 2
        case "unknown": return 1
        default: return 0
        }
    }

    /// Desktop `providerScore`: a score above 1 is read as a percentage, and the result is kept between 0 and 1.
    static func providerScore(_ candidate: SubtitleProviderCandidate) -> Double {
        guard let score = candidate.matchScore, score.isFinite else { return 0 }
        return min(1, max(0, score > 1 ? score / 100 : score))
    }

    /// Desktop `stableCandidateKey`, from the fields iOS carries.
    static func stableKey(_ candidate: SubtitleProviderCandidate) -> String {
        [candidate.provider.rawValue, candidate.subtitle.id ?? "", SubtitleLanguages.normalize(candidate.subtitle.lang ?? ""), candidate.subtitle.url, candidate.release ?? ""]
            .joined(separator: "|")
            .lowercased()
    }

    private static func flag(_ value: Bool) -> Int { value ? 1 : 0 }

    /// The sign of `x - y` as -1, 0 or 1.
    private static func desc(_ x: Int, _ y: Int) -> Int { x > y ? 1 : (x < y ? -1 : 0) }

    private static func desc(_ x: Double, _ y: Double) -> Int { x > y ? 1 : (x < y ? -1 : 0) }
}

/// Desktop's user-facing result order and duplicate merge from `lib/subtitles/search.ts`.
/// Keep this separate from auto-selection: search rows retain forced/foreign-only results,
/// and the display interleaver does not filter candidates.
enum SubtitleSearchRanking {
    private struct IndexedCandidate {
        let index: Int
        let candidate: SubtitleProviderCandidate
    }

    /// Composite identity follows Desktop's normalized-language, URL, title and format key.
    /// The length-prefix encoding avoids collisions when provider text contains a separator.
    static func listIdentity(language: String?, url: String, title: String?, format: String?) -> String {
        [SubtitleLanguages.normalize(language ?? ""), url, title ?? "", format ?? ""]
            .map { "\($0.utf8.count):\($0)" }
            .joined()
    }

    static func listIdentity(for candidate: SubtitleProviderCandidate) -> String {
        candidate.subtitle.searchIdentity ?? duplicateKey(for: candidate)
    }

    static func mergeResults(_ current: [PlaybackSource.Subtitle], _ additions: [PlaybackSource.Subtitle],
                             preferredLanguages: [String]) -> [PlaybackSource.Subtitle] {
        var results = current
        var positions = Dictionary(current.enumerated().map { ($0.element.selectionIdentity, $0.offset) },
                                   uniquingKeysWith: { first, _ in first })
        for subtitle in additions {
            let key = subtitle.selectionIdentity
            if let position = positions[key] {
                if subtitle.providerDownload?.provider != nil { results[position] = subtitle }
            } else {
                positions[key] = results.count
                results.append(subtitle)
            }
        }
        return results.enumerated().map { index, subtitle in
            (index, subtitle, SubtitleSelectionPolicy.languageScore(subtitle.lang ?? "", preferred: preferredLanguages))
        }.sorted { left, right in
            left.2 == right.2 ? left.0 < right.0 : left.2 > right.2
        }.map { $0.1 }
    }

    static func deduplicateAndRank(_ candidates: [SubtitleProviderCandidate], preferredLanguages: [String]) -> [SubtitleProviderCandidate] {
        var groups: [String: [IndexedCandidate]] = [:]
        var groupOrder: [String] = []

        for (index, candidate) in candidates.enumerated() {
            guard SubtitleProviderURL.safe(candidate.subtitle.url) != nil else { continue }
            let key = duplicateKey(for: candidate)
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append(IndexedCandidate(index: index, candidate: candidate))
        }

        let filtered = groupOrder.compactMap { key -> IndexedCandidate? in
            guard let group = groups[key] else { return nil }
            let ordered = group.sorted { left, right in
                let comparison = compareDuplicates(left.candidate, right.candidate)
                return comparison == 0 ? left.index < right.index : comparison < 0
            }
            guard var merged = ordered.first?.candidate else { return nil }
            for item in ordered.dropFirst() {
                mergeMissingMetadata(from: item.candidate, into: &merged)
            }
            merged.subtitle.searchIdentity = key
            return IndexedCandidate(index: group[0].index, candidate: merged)
        }
        return interleave(filtered, preferredLanguages: preferredLanguages).map(\.candidate)
    }

    private static func compareDuplicates(_ a: SubtitleProviderCandidate, _ b: SubtitleProviderCandidate) -> Int {
        let auth = flag(b.requiresKey) - flag(a.requiresKey)
        if auth != 0 { return auth }

        let confidence = providerConfidenceValue(b) - providerConfidenceValue(a)
        if confidence != 0 { return confidence }

        let scoreA = SubtitleCandidateRanking.providerScore(a)
        let scoreB = SubtitleCandidateRanking.providerScore(b)
        if scoreA != scoreB { return scoreA > scoreB ? -1 : 1 }

        // With no stream-hint input, Desktop's compareSubtitleMatch reaches its download
        // count and title tie-breakers. Search does not reuse its auto-selection comparator.
        let localMatch = compareSubtitleMatchWithoutHints(a, b)
        if localMatch != 0 { return localMatch }

        let richness = metadataRichness(b) - metadataRichness(a)
        if richness != 0 { return richness > 0 ? 1 : -1 }

        let aKey = stableDuplicateKey(a)
        let bKey = stableDuplicateKey(b)
        return textCompare(aKey, bKey)
    }

    private static func providerConfidenceValue(_ candidate: SubtitleProviderCandidate) -> Int {
        switch candidate.matchConfidence {
        case "exact": 5
        case "high": 4
        case "medium": 3
        case "low": 2
        case "unknown": 1
        default: 0
        }
    }

    private static func metadataRichness(_ candidate: SubtitleProviderCandidate) -> Int {
        var score = 1 // `source` is always present in Desktop's result.
        if let title = candidate.searchTitle, !title.isEmpty { score += 1 }
        if desktopFormat(candidate) != nil { score += 1 }
        if candidate.archive { score += 1 }
        if candidate.requiresKey { score += 1 }
        if candidate.hearingImpaired { score += 1 }
        if candidate.forced { score += 1 }
        if candidate.foreignOnly { score += 1 }
        if candidate.machineTranslated { score += 1 }
        if candidate.fromTrusted { score += 1 }
        if let release = candidate.release, !release.isEmpty { score += 1 }
        if let author = candidate.author, !author.isEmpty { score += 1 }
        if candidate.downloads > 0 { score += 1 }
        if candidate.ratingScore != nil { score += 1 }
        if candidate.ratingTotal != nil { score += 1 }
        if candidate.fps != nil { score += 1 }
        if candidate.matchConfidence != nil { score += 1 }
        if candidate.matchScore != nil { score += 1 }
        if candidate.idConfirmed { score += 1 }
        if candidate.episodeConfirmed { score += 1 }
        if candidate.season != nil { score += 1 }
        if candidate.episode != nil { score += 1 }
        return score
    }

    private static func stableDuplicateKey(_ candidate: SubtitleProviderCandidate) -> String {
        [candidate.provider.rawValue, candidate.subtitle.id ?? "", "", candidate.release ?? "", "",
         candidate.matchConfidence ?? "", SubtitleCandidateRanking.providerScore(candidate).description]
            .joined(separator: "|")
            .lowercased()
    }

    private static func duplicateKey(for candidate: SubtitleProviderCandidate) -> String {
        return listIdentity(language: candidate.subtitle.lang, url: candidate.subtitle.url,
                            title: candidate.searchTitle, format: desktopFormat(candidate))
    }

    private static func desktopFormat(_ candidate: SubtitleProviderCandidate) -> String? {
        if (candidate.provider == .subdl || candidate.provider == .subsource) && candidate.format == "zip" { return nil }
        return candidate.format
    }

    private static func mergeMissingMetadata(from source: SubtitleProviderCandidate, into target: inout SubtitleProviderCandidate) {
        // Keep the primary candidate's providerDownload grant bound to its provider. A same-URL
        // duplicate is not authority to transfer that in-memory credential context.
        if target.subtitle.id == nil { target.subtitle.id = source.subtitle.id }
        if target.subtitle.lang == nil { target.subtitle.lang = source.subtitle.lang }
        if target.format == nil { target.format = source.format }
        if target.release == nil { target.release = source.release }
        if target.author == nil { target.author = source.author }
        if target.ratingScore == nil { target.ratingScore = source.ratingScore }
        if target.ratingTotal == nil { target.ratingTotal = source.ratingTotal }
        if target.fps == nil { target.fps = source.fps }
        if target.matchConfidence == nil { target.matchConfidence = source.matchConfidence }
        if target.matchScore == nil { target.matchScore = source.matchScore }
        if target.season == nil { target.season = source.season }
        if target.episode == nil { target.episode = source.episode }
    }

    private static func interleave(_ candidates: [IndexedCandidate], preferredLanguages: [String]) -> [IndexedCandidate] {
        var buckets: [SubtitleProviderID: [IndexedCandidate]] = [:]
        var providerOrder: [SubtitleProviderID] = []
        for item in candidates {
            let provider = item.candidate.provider
            if buckets[provider] == nil { providerOrder.append(provider) }
            buckets[provider, default: []].append(item)
        }

        for provider in providerOrder {
            buckets[provider]?.sort { left, right in
                let leftLanguage = languageScore(left.candidate, preferredLanguages)
                let rightLanguage = languageScore(right.candidate, preferredLanguages)
                if leftLanguage != rightLanguage { return leftLanguage > rightLanguage }
                let match = compareSubtitleMatchWithoutHints(left.candidate, right.candidate)
                if match != 0 { return match < 0 }
                return left.index < right.index
            }
        }

        let preferred = candidates.filter { languageScore($0.candidate, preferredLanguages) > 0 }
        let pool = preferred.isEmpty ? candidates : preferred
        let best = pool.sorted { left, right in
            let leftLanguage = languageScore(left.candidate, preferredLanguages)
            let rightLanguage = languageScore(right.candidate, preferredLanguages)
            if leftLanguage != rightLanguage { return leftLanguage > rightLanguage }
            let match = compareSubtitleMatchWithoutHints(left.candidate, right.candidate)
            if match != 0 { return match < 0 }
            return left.index < right.index
        }.first

        var result: [IndexedCandidate] = []
        var seen = Set<Int>()
        if let best {
            result.append(best)
            seen.insert(best.index)
        }

        func drain(_ accepts: (IndexedCandidate) -> Bool) {
            var depth = 0
            while true {
                var found = false
                for provider in providerOrder {
                    guard let item = buckets[provider], item.indices.contains(depth) else { continue }
                    found = true
                    let candidate = item[depth]
                    if !seen.contains(candidate.index), accepts(candidate) {
                        seen.insert(candidate.index)
                        result.append(candidate)
                    }
                }
                if !found { return }
                depth += 1
            }
        }

        drain { languageScore($0.candidate, preferredLanguages) > 0 }
        drain { _ in true }
        return result
    }

    private static func languageScore(_ candidate: SubtitleProviderCandidate, _ preferredLanguages: [String]) -> Int {
        SubtitleCandidateRanking.languageScore(candidate, preferredLanguages)
    }

    private static func compareSubtitleMatchWithoutHints(_ a: SubtitleProviderCandidate, _ b: SubtitleProviderCandidate) -> Int {
        if a.downloads != b.downloads { return a.downloads > b.downloads ? -1 : 1 }
        return textCompare(a.searchTitle ?? "", b.searchTitle ?? "")
    }

    private static func flag(_ value: Bool) -> Int { value ? 1 : 0 }
    private static func textCompare(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        return a.utf8.lexicographicallyPrecedes(b.utf8) ? -1 : 1
    }
}
