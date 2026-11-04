import Foundation

/// Desktop's source-mode preference (`lib/streams/mode.ts`): which kind of result the
/// picker favours. "Direct/debrid" keeps peer-to-peer results out of the way and
/// "P2P" puts them first; neither may ever leave the picker empty.
enum StreamMode: String, CaseIterable, Sendable {
    case both, addons, p2p
    /// A backup can carry a value this build does not know. Desktop shows everything
    /// rather than falling into the restrictive mode, and so does this.
    init(stored: String?) { self = stored.flatMap(Self.init(rawValue:)) ?? .both }
}

/// One entry of Desktop's "Stream priority" list (`StreamPriorityEntry`): the addon's key
/// and the name to show when that addon is no longer installed.
struct StreamPriorityEntry: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var name: String
    var id: String { key }
}

/// The streaming-source settings that shape how addons are queried and listed.
struct StreamSourceSettings: Equatable, Sendable {
    static let defaultTimeoutSeconds = 30
    static let timeoutChoices = [15, 30, 45, 60, 90]
    var timeoutSeconds = StreamSourceSettings.defaultTimeoutSeconds
    var mode = StreamMode.both
    var priority: [StreamPriorityEntry] = []

    /// Desktop clamps the wait to 8...120 seconds and treats anything else as 30.
    static func clamped(_ seconds: Int) -> Int { max(8, min(120, seconds)) }
    var timeoutMilliseconds: Int { Self.clamped(timeoutSeconds) * 1000 }
}

enum StreamSourcePolicy {
    private static let videoExtension = "(?i)\\.(?:mkv|mp4|avi|mov|m4v|webm|ts|m3u8|mpd|flv|wmv|m2ts|mpg|mpeg|ogv|3gp)(?:[?#]|$)"
    private static let httpURL = "(?i)^(?:https?:)?//"
    private static let debridTag = "(?i)\\[(?:realdebrid|real-debrid|torbox|alldebrid|all-debrid|premiumize|debridlink|debrid-link|easydebrid|offcloud|rd|ad|pm|dl|tb|trb|oc|ed|putio)(?:\\+|⚡|✅|⬇|⏳|\\]|\\s)"
    private static let cachedMarker = "[⚡✅]"

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
    private static func number(_ value: JSONValue) -> Double? {
        switch value {
        case .integer(let value): Double(value)
        case .unsigned(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }
    private static func hasVideoFileExtension(_ value: String?) -> Bool {
        matches(videoExtension, (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A torrent hash that no provider holds and no addon marks as debrid (`isP2pStream`).
    static func isPeerToPeer(_ raw: JSONValue) -> Bool {
        guard let hash = raw["infoHash"].string, !hash.isEmpty else { return false }
        if raw["cached"].objectValue.values.contains(.bool(true)) { return false }
        let text = [raw["name"].string, raw["title"].string, raw["description"].string].map { $0 ?? "" }.joined(separator: " ")
        return !matches(debridTag, text) && !matches(cachedMarker, text)
    }

    /// Whether a non-P2P result carries enough evidence to be treated as a playable stream.
    /// Plain web links are inconclusive: addons sometimes put a watch page in `url`.
    static func hasDirectMediaEvidence(_ raw: JSONValue) -> Bool {
        let hints = raw["behaviorHints"]
        let url = (raw["url"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if hasVideoFileExtension(url) || hasVideoFileExtension(hints["filename"].string ?? hints["fileName"].string) { return true }
        if let size = number(hints["videoSize"]), size.isFinite, size > 0 { return true }
        if hints["notWebReady"] == .bool(true) || !hints["proxyHeaders"]["request"].objectValue.isEmpty
            || !hints["proxyHeaders"]["response"].objectValue.isEmpty || !hints["headers"].objectValue.isEmpty { return true }
        if !url.isEmpty, url != "#", !matches(httpURL, url) { return true }
        if let hash = raw["infoHash"].string, !hash.isEmpty { return !isPeerToPeer(raw) }
        return false
    }

    /// Desktop's `filterStreamsByMode`. When the preferred transport has nothing to offer
    /// every result stays visible, so the picker never becomes artificially empty.
    static func filter(_ offers: [StreamOffer], mode: StreamMode) -> [StreamOffer] {
        switch mode {
        case .both:
            return offers
        case .p2p:
            let peers = offers.filter { isPeerToPeer($0.raw) }
            return peers.isEmpty ? offers : peers
        case .addons:
            let others = offers.filter { !isPeerToPeer($0.raw) }
            return others.contains { hasDirectMediaEvidence($0.raw) } ? others : offers
        }
    }
}

/// Desktop's picker filter for one title (`strictMode` and `forceShowAll` in play-picker.tsx):
/// the profile's safety level, which "Search wider" relaxes from Strict to Balanced and
/// "Show everything anyway" turns off, until another title or episode is opened.
struct StreamPickerFilter: Equatable, Sendable {
    var relaxed = false
    var showAll = false
    func level(_ setting: String) -> String {
        if showAll || setting == "off" { return "off" }
        return relaxed || setting == "balanced" ? "balanced" : "strict"
    }
    /// Desktop's `onSearchWider`: Strict becomes Balanced first, then everything is shown.
    mutating func widen(_ setting: String) {
        if level(setting) == "strict" { relaxed = true } else { showAll = true }
    }
}

/// Desktop's rejection groups for the "0 made it through" state (`groupRejections`).
enum StreamRejections {
    static func label(_ reason: String) -> String {
        if reason.hasPrefix("suspicious-extension:") { return "sketchy files" }
        if reason.hasPrefix("cinema-window-") { return "cam rips" }
        if reason == "size-stub" { return "tiny stubs" }
        if reason.hasPrefix("size-too-large-") { return "oversized" }
        if reason.hasPrefix("year-mismatch") { return "year mismatch" }
        if reason.hasPrefix("season-mismatch") || reason.hasPrefix("episode-mismatch") { return "wrong episode" }
        if reason == "season-pack-no-file-idx" { return "season packs" }
        if reason.hasPrefix("scam-score-") { return "scam metadata" }
        if reason == "dead-torrent-zero-seeders" { return "dead torrents" }
        if reason == "language-mismatch" { return "language" }
        if reason == "trailer-or-extra" { return "trailers/extras" }
        if reason == "movie-stub-too-small" { return "stub files" }
        if reason == "title-mismatch" { return "wrong movie" }
        return reason
    }
    struct Group: Hashable, Sendable {
        let label: String
        let count: Int
    }
    /// Labels by count, most frequent first; equal counts keep their first appearance.
    static func groups(_ reasons: [String]) -> [Group] {
        var counts: [String: Int] = [:], order: [String] = []
        for reason in reasons {
            let key = label(reason)
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        return order.enumerated().sorted { left, right in
            let a = counts[left.element] ?? 0, b = counts[right.element] ?? 0
            return a == b ? left.offset < right.offset : a > b
        }.map { Group(label: $0.element, count: counts[$0.element] ?? 0) }
    }
}

/// Desktop's automatic start (`use-auto-fire.ts`) while addons are still answering: a
/// confident top result starts after a short grace, otherwise the list settles once the
/// top source is playable for a moment, most addons have answered, or 10 s have passed.
struct StreamAutoSettle: Sendable {
    static let settle = Duration.milliseconds(1500)
    static let packSettle = Duration.milliseconds(4000)
    static let highConfidenceGrace = Duration.milliseconds(350)
    static let cap = Duration.seconds(10)
    static let quorumRatio = 0.8

    var started: ContinuousClock.Instant
    var season: Int?
    var episode: Int?
    /// An addon whose results Desktop trusts over Torrentio's own instant marker.
    var strongAddon = false
    private(set) var firstResult: ContinuousClock.Instant?
    private(set) var highConfidenceSince: ContinuousClock.Instant?
    /// Desktop's `autoSettleReady`: once set it stays set for this request.
    private(set) var settled = false

    init(started: ContinuousClock.Instant, season: Int? = nil, episode: Int? = nil, strongAddon: Bool = false) {
        self.started = started; self.season = season; self.episode = episode; self.strongAddon = strongAddon
    }

    static func strong(_ addons: [Addon]) -> Bool {
        addons.contains { $0.name.range(of: "(?i)mediafusion|comet", options: .regularExpression) != nil }
    }

    /// The release answers for the requested episode; a file without episode numbers
    /// must name it (`episodeVariantMatch`).
    func qualifies(_ offer: StreamOffer) -> Bool {
        guard let episode else { return true }
        let parsedSeason = offer.raw["season"].integer, parsedEpisode = offer.raw["episode"].integer
        if parsedEpisode == episode, season == nil || parsedSeason == nil || parsedSeason == season { return true }
        if parsedEpisode != nil { return false }
        let pattern = season.map { "(?i)(?:\\bS0*\($0)[ ._-]?E0*\(episode)|\\b\($0)x0*\(episode))(?!\\d)" } ?? "(?i)(?:\\bE|\\bEp\\.?\\s?)0*\(episode)(?!\\d)"
        return offer.pickerFilename.range(of: pattern, options: .regularExpression) != nil
    }

    private func named(_ offer: StreamOffer) -> Bool { offer.raw["nameAbsent"] != .bool(true) }
    private func instantMarker(_ offer: StreamOffer) -> Bool {
        [offer.raw["name"].string, offer.raw["title"].string, offer.raw["description"].string].map { $0 ?? "" }.joined(separator: " ")
            .range(of: "(?i)\\binstant\\b|⚡", options: .regularExpression) != nil
    }
    func highConfidence(_ offer: StreamOffer) -> Bool {
        instantMarker(offer) && offer.automaticallyPlayable && qualifies(offer) && named(offer)
            && !(strongAddon && offer.source.range(of: "(?i)torrentio", options: .regularExpression) != nil)
    }

    /// Whether automatic play may start `top` now. `protecting` keeps a remembered source
    /// that has not answered yet from being skipped before every addon has finished.
    mutating func shouldStart(now: ContinuousClock.Instant, top: StreamOffer?, candidates: [StreamOffer], hasResults: Bool,
                              answered: Int, total: Int, done: Bool, protecting: Bool) -> Bool {
        if hasResults, firstResult == nil { firstResult = now }
        if done { return top != nil }
        guard let top else { highConfidenceSince = nil; return false }
        if !settled, !protecting, let first = firstResult {
            let sinceFirst = now - first
            let exact = candidates.contains { $0.automaticallyPlayable && qualifies($0) }
            let baseline = episode != nil && !exact ? Self.packSettle : Self.settle
            let floor = top.automaticallyPlayable && named(top) && qualifies(top) && sinceFirst >= baseline
            let quorum = total > 0 && Double(answered) / Double(total) >= Self.quorumRatio && sinceFirst >= Self.settle
            if floor || quorum || now - started >= Self.cap { settled = true }
        }
        if !protecting, highConfidence(top) {
            let since = highConfidenceSince ?? now
            highConfidenceSince = since
            if now - since >= Self.highConfidenceGrace { return true }
        } else { highConfidenceSince = nil }
        return settled
    }
}

/// Desktop's Stremio picker layout (`stremio-layout.tsx`, `stremio-row.tsx`): a flat list
/// grouped by addon, with each addon's own headline and description and no scoring.
enum StremioPickerPresentation {
    struct AddonOption: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let count: Int
    }

    static func headline(_ offer: StreamOffer) -> String {
        let name = (offer.raw["name"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? offer.source : name
    }
    /// The title, or the description; "Show full descriptions" off shortens the first line to 90 characters.
    static func description(_ offer: StreamOffer, full: Bool) -> String {
        let title = (offer.raw["title"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = title.isEmpty ? (offer.raw["description"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : title
        guard !full, !text.isEmpty else { return text }
        var lines = text.components(separatedBy: "\n")
        if lines[0].count > 90 {
            let head = String(lines[0].prefix(90))
            lines[0] = String(head.reversed().drop(while: \.isWhitespace).reversed()) + "…"
        }
        return lines.joined(separator: "\n")
    }

    private static func rank(_ offer: StreamOffer, addons: [Addon]) -> Int {
        guard let url = offer.raw["addonUrl"].string else { return 9999 }
        return addons.firstIndex { $0.transportUrl == url } ?? 9999
    }
    private static func marked(_ offer: StreamOffer, _ pattern: String) -> Bool {
        [offer.raw["name"].string, offer.raw["title"].string, offer.raw["description"].string].map { $0 ?? "" }
            .joined(separator: " ").range(of: pattern, options: .regularExpression) != nil
    }

    /// With "Addon order" the list keeps each addon's own order. Otherwise WatchHub and
    /// still-downloading results go last, then the addon list order, instant results first.
    static func ordered(_ offers: [StreamOffer], addons: [Addon], preserveOrder: Bool) -> [StreamOffer] {
        guard !preserveOrder else { return offers }
        func watchHub(_ offer: StreamOffer) -> Int {
            ((offer.addonID ?? "") + " " + offer.source).range(of: "(?i)watchhub", options: .regularExpression) == nil ? 0 : 1
        }
        func downloading(_ offer: StreamOffer) -> Int {
            marked(offer, "(?i)[⏳⌛⬇⏬🔽📥]|\\bdownload(ing)?\\b|\\bqueued?\\b|\\bnot[\\s_-]?cached\\b") ? 1 : 0
        }
        func instant(_ offer: StreamOffer) -> Int { marked(offer, "(?i)\\binstant\\b|⚡") ? 1 : 0 }
        return offers.enumerated().sorted { left, right in
            let a = left.element, b = right.element
            if watchHub(a) != watchHub(b) { return watchHub(a) < watchHub(b) }
            if downloading(a) != downloading(b) { return downloading(a) < downloading(b) }
            let ra = rank(a, addons: addons), rb = rank(b, addons: addons)
            if ra != rb { return ra < rb }
            if instant(a) != instant(b) { return instant(a) > instant(b) }
            return left.offset < right.offset
        }.map(\.element)
    }

    /// One entry per addon instance that returned results, in addon list order.
    static func addonOptions(_ offers: [StreamOffer], addons: [Addon]) -> [AddonOption] {
        var counts: [String: Int] = [:], first: [String: StreamOffer] = [:], order: [String] = []
        for offer in offers {
            let key = offer.pickerInstance
            if first[key] == nil { first[key] = offer; order.append(key) }
            counts[key, default: 0] += 1
        }
        return order.enumerated().sorted { left, right in
            let a = rank(first[left.element]!, addons: addons), b = rank(first[right.element]!, addons: addons)
            return a == b ? left.offset < right.offset : a < b
        }.map { AddonOption(id: $0.element, name: first[$0.element]!.source, count: counts[$0.element] ?? 0) }
    }
}

/// Desktop's "Stream priority" (`lib/streams/addon-priority.ts`, `priority-partition.ts`):
/// results from addons higher in the list come first; one that finds nothing lets the next fill in.
enum StreamAddonPriority {
    struct Ranker: Sendable {
        let positions: [String: Int]
        let base: Int
        func rank(index: Int, addon: Addon) -> Int { positions[StreamAddonPriority.key(addon)] ?? base + index }
    }

    static func host(_ url: String) -> String {
        guard let parts = URLComponents(string: url), let host = parts.host, !host.isEmpty else { return url }
        return parts.port.map { "\(host):\($0)" } ?? host
    }
    /// The manifest id, or the host when an addon has none.
    static func key(_ addon: Addon) -> String {
        let id = (addon.manifest["id"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return id.isEmpty ? "host:" + host(addon.transportUrl) : id
    }
    /// Addons that can list streams; the others are not shown in the priority list.
    static func streamAddons(_ addons: [Addon]) -> [Addon] { addons.filter(AddonOriginPolicy.declaresStreams) }

    /// Nil unless an order was chosen and at least two addons stream (`resolveAddonRanks`).
    static func ranker(addons: [Addon], priority: [StreamPriorityEntry]) -> Ranker? {
        guard !priority.isEmpty, streamAddons(addons).count >= 2 else { return nil }
        var positions: [String: Int] = [:]
        for (index, entry) in priority.enumerated() { positions[entry.key] = index }
        return Ranker(positions: positions, base: priority.count)
    }

    /// Entries as the settings list shows them: the saved order first (addons no longer
    /// installed stay, muted, until removed), then newly installed stream addons.
    static func entries(addons: [Addon], priority: [StreamPriorityEntry]) -> [(entry: StreamPriorityEntry, installed: Bool)] {
        let live = Dictionary(streamAddons(addons).map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set<String>()
        var result: [(entry: StreamPriorityEntry, installed: Bool)] = []
        for saved in priority where used.insert(saved.key).inserted {
            if let addon = live[saved.key] { result.append((entry: StreamPriorityEntry(key: saved.key, name: addon.name), installed: true)) }
            else { result.append((entry: saved, installed: false)) }
        }
        for addon in streamAddons(addons) where used.insert(key(addon)).inserted {
            result.append((entry: StreamPriorityEntry(key: key(addon), name: addon.name), installed: true))
        }
        return result
    }

    /// Stable reorder by the rank each stream carries; unchanged when no order is active.
    static func order(_ offers: [StreamOffer], active: Bool) -> [StreamOffer] {
        guard active else { return offers }
        func rank(_ offer: StreamOffer) -> Int { offer.raw["addonPriority"].integer ?? Int.max }
        return offers.enumerated().sorted { left, right in
            let a = rank(left.element), b = rank(right.element)
            return a == b ? left.offset < right.offset : a < b
        }.map(\.element)
    }

    /// Plugin results follow every addon, including addons the chosen order ranks after the list.
    static func pluginStart(addons: [Addon], settings: StreamSourceSettings) -> Int {
        addons.count + (ranker(addons: addons, priority: settings.priority) == nil ? 0 : settings.priority.count)
    }

    /// Applies the wait time and the chosen order to the requests before they are sent.
    /// Desktop waits at least as long as the addon's own budget (8 s, or 22 s for slow
    /// aggregators) and as long as the profile setting.
    static func tune(_ requests: HarborService.StreamRequests, settings: StreamSourceSettings, addons: [Addon]) -> HarborService.StreamRequests {
        let ceiling = settings.timeoutMilliseconds
        let chosen = ranker(addons: addons, priority: settings.priority)
        func tuned(_ plan: RequestPlan) -> RequestPlan {
            RequestPlan(key: plan.key, url: plan.url, title: plan.title, kind: plan.kind, addon: plan.addon,
                        addonPriority: chosen?.rank(index: plan.addonPriority, addon: plan.addon) ?? plan.addonPriority,
                        timeoutMs: max(plan.timeoutMs, ceiling), catalog: plan.catalog)
        }
        return .init(plans: requests.plans.map(tuned), fallbacks: requests.fallbacks.mapValues { $0.map(tuned) })
    }
}
