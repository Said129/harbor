import Foundation

/// The filters of Desktop's stream switcher that the native picker did not have (`components/player/stream-switcher.tsx`
/// and `filters-menu.tsx`): cached only, "my languages only", the source format and "show flagged". Quality, provider and the
/// Both/Direct-debrid mode keep their own controls in the picker. Everything here is pure, so preferences arrive as parameters.
struct StreamSwitcherFilters: Equatable, Sendable {
    /// One entry of Desktop's "Format" chips with the streams it holds.
    struct SourceGroup: Identifiable, Equatable, Sendable {
        let name: String
        let count: Int
        var id: String { name }
    }

    var cachedOnly = false
    var preferredLanguageOnly = false
    var showFlagged = false
    /// One of `sourceGroupOrder`, or nil for every format.
    var sourceGroup: String? = nil

    /// Desktop's order of the format chips.
    static let sourceGroupOrder = ["Remux", "BluRay", "WEB-DL", "WEBRip", "HDTV", "CAM"]

    /// How many of these filters are on, for the badge on the Filters button (Desktop's `activeCountOf`).
    var activeCount: Int {
        var count = 0
        if cachedOnly { count += 1 }
        if preferredLanguageOnly { count += 1 }
        if showFlagged { count += 1 }
        if sourceGroup != nil { count += 1 }
        return count
    }

    // MARK: Format

    /// Desktop's `sourceGroup`: the release family of a stream, or nil when its source is unknown.
    static func group(_ offer: StreamOffer) -> String? {
        guard let source = offer.raw["source"].string else { return nil }
        switch source {
        case "REMUX": return "Remux"
        case "BluRay", "BDRip": return "BluRay"
        case "WEB-DL": return "WEB-DL"
        case "WEBRip", "HDRip": return "WEBRip"
        case "HDTV", "DVDRip": return "HDTV"
        case "CAM", "TS", "HDTS", "TC", "SCR": return "CAM"
        default: return nil
        }
    }

    /// The formats present in a list, in Desktop's order, each with its count.
    static func sourceGroups(in offers: [StreamOffer]) -> [SourceGroup] {
        var counts: [String: Int] = [:]
        for offer in offers {
            guard let name = group(offer) else { continue }
            counts[name, default: 0] += 1
        }
        var result: [SourceGroup] = []
        for name in sourceGroupOrder {
            let count = counts[name] ?? 0
            if count > 0 { result.append(SourceGroup(name: name, count: count)) }
        }
        return result
    }

    // MARK: Cached only

    private static func marker(_ offer: StreamOffer) -> Bool {
        let parts: [String?] = [offer.raw["name"].string, offer.raw["title"].string, offer.raw["description"].string]
        let text = parts.map { $0 ?? "" }.joined(separator: " ")
        // The lightning bolt and the check mark that addons put on streams a debrid service already holds. Scalars are compared,
        // because the bolt often arrives with an emoji variation selector that makes it a different Character.
        return text.unicodeScalars.contains { $0.value == 0x26A1 || $0.value == 0x2705 }
    }

    /// Desktop's `cachedStreams` test: a direct link, a stream a provider reports as cached or in its library, or one an addon marks as cached.
    static func isCachedOrDirect(_ offer: StreamOffer) -> Bool {
        let link = (offer.raw["url"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty { return true }
        if offer.raw["cached"].objectValue.values.contains(.bool(true)) { return true }
        if offer.raw["inLibrary"].objectValue.values.contains(.bool(true)) { return true }
        return marker(offer)
    }

    /// How many streams "Cached only" would hide (Desktop's `uncachedHidden`).
    static func uncachedCount(in offers: [StreamOffer]) -> Int {
        return offers.count - offers.filter { isCachedOrDirect($0) }.count
    }

    /// Desktop's `baseList`: without a debrid service, or when nothing is cached, the whole list stays so the picker is never emptied.
    static func applyCached(_ offers: [StreamOffer], cachedOnly: Bool, hasDebrid: Bool) -> [StreamOffer] {
        guard cachedOnly, hasDebrid else { return offers }
        let cached = offers.filter { isCachedOrDirect($0) }
        return cached.isEmpty ? offers : cached
    }

    static func applyGroup(_ offers: [StreamOffer], group wanted: String?) -> [StreamOffer] {
        guard let wanted = wanted else { return offers }
        return offers.filter { group($0) == wanted }
    }

    // MARK: Languages

    private static let languageCodes: [String: String] = [
        "english": "en", "portuguese": "pt", "spanish": "es", "french": "fr", "german": "de", "italian": "it",
        "japanese": "ja", "korean": "ko", "chinese": "zh", "russian": "ru", "hindi": "hi", "arabic": "ar",
        "dutch": "nl", "polish": "pl", "turkish": "tr", "swedish": "sv", "norwegian": "no", "danish": "da",
        "finnish": "fi", "czech": "cs", "hungarian": "hu", "romanian": "ro", "hebrew": "he", "thai": "th",
        "vietnamese": "vi", "ukrainian": "uk"
    ]

    /// Desktop's `normalizeLangCode`.
    static func languageCode(_ name: String) -> String {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower == "jp" { return "ja" }
        if let code = languageCodes[lower] { return code }
        return String(lower.prefix(2))
    }

    /// The languages Desktop's switcher prefers: the stream-ranking languages, then the playback audio languages, each once.
    /// Japanese counts only for anime, where Desktop adds it and otherwise leaves it out.
    static func preferredLanguages(ranking: [String], audio: [String], isAnime: Bool) -> [String] {
        var all = ranking + audio
        if isAnime { all.append("Japanese") }
        var seen = Set<String>()
        var result: [String] = []
        for language in all {
            let code = languageCode(language)
            if code.isEmpty { continue }
            if !isAnime && code == "ja" { continue }
            if seen.contains(code) { continue }
            seen.insert(code)
            result.append(language)
        }
        return result
    }

    /// Desktop's `abbreviateLanguages`: "EN, ES".
    static func abbreviated(_ languages: [String]) -> String {
        var seen = Set<String>()
        var codes: [String] = []
        for language in languages {
            let code = languageCode(language).uppercased()
            if code.isEmpty || seen.contains(code) { continue }
            seen.insert(code)
            codes.append(code)
        }
        return codes.joined(separator: ", ")
    }

    /// Desktop's `streamMatchesLangs`: a stream that names no audio language, or "Multi", always matches.
    static func matchesLanguages(_ audio: [String], preferred: [String]) -> Bool {
        if audio.isEmpty { return true }
        if audio.contains("Multi") { return true }
        for language in audio {
            let lower = language.lowercased()
            for wanted in preferred {
                let other = wanted.lowercased()
                if other.isEmpty { continue }
                if lower == other || lower.hasPrefix(other) { return true }
            }
        }
        return false
    }

    static func audioLanguages(_ offer: StreamOffer) -> [String] {
        return offer.raw["audioLanguages"].array.compactMap { $0.string }
    }

    static func applyLanguages(_ offers: [StreamOffer], preferred: [String], enabled: Bool) -> [StreamOffer] {
        guard enabled, !preferred.isEmpty else { return offers }
        return offers.filter { matchesLanguages(audioLanguages($0), preferred: preferred) }
    }

    /// How many streams the language filter would hide (Desktop's `langHidden`).
    static func languageHiddenCount(in offers: [StreamOffer], preferred: [String]) -> Int {
        guard !preferred.isEmpty else { return 0 }
        return offers.count - applyLanguages(offers, preferred: preferred, enabled: true).count
    }

    // MARK: Flagged

    /// Desktop lists a stream the safety filter set aside with a `filtered:` reason, a zero score and the ROUGH tier.
    static func isFlagged(_ offer: StreamOffer) -> Bool {
        return offer.raw["reasons"].array.contains { reason in
            reason["signal"].string?.hasPrefix("filtered:") == true
        }
    }

    // MARK: Whole list

    /// Every stream the picker may list: the kept ones, then the flagged ones when they are shown.
    func pool(kept: [StreamOffer], flagged: [StreamOffer]) -> [StreamOffer] {
        return showFlagged ? kept + flagged : kept
    }

    /// The list after these filters, before the picker's own quality and provider filters.
    func apply(kept: [StreamOffer], flagged: [StreamOffer], hasDebrid: Bool, preferred: [String]) -> [StreamOffer] {
        let all = pool(kept: kept, flagged: flagged)
        let cached = Self.applyCached(all, cachedOnly: cachedOnly, hasDebrid: hasDebrid)
        let grouped = Self.applyGroup(cached, group: sourceGroup)
        return Self.applyLanguages(grouped, preferred: preferred, enabled: preferredLanguageOnly)
    }
}

extension StreamOffer {
    /// Set aside by the safety filter and shown only through "Show flagged".
    var isFlagged: Bool { StreamSwitcherFilters.isFlagged(self) }
}
