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
