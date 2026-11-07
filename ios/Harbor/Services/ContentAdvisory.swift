import Foundation

/// Desktop's content advisory (`components/player/content-advisory-toast.tsx`, `content-advisory-prompt.tsx` and
/// `views/player/hooks/use-content-advisory.ts`): the IMDb parental guide of a title, the card that shows it when playback
/// starts, and the one-time invitation to turn it on. The rules are here, pure and testable. The timing and the views are in
/// `ContentAdvisoryDriver` and `ContentAdvisoryOverlay`.

/// One rated category of a parental guide (Desktop's `ParentalCategory`).
struct ContentAdvisoryCategory: Equatable, Sendable {
    let category: String
    let severity: String
}

/// A parental guide: the rated categories and the MPA rating, when the title has one.
struct ContentAdvisoryGuide: Equatable, Sendable {
    var categories: [ContentAdvisoryCategory] = []
    var mpaRating: String?
}

/// Desktop's `contentAdvisoryTheme`. Monochrome is the default, and any other stored value falls back to it.
enum ContentAdvisoryTheme: String, CaseIterable, Hashable, Sendable {
    case colored, monochrome

    init(stored: String?) {
        self = stored.flatMap { ContentAdvisoryTheme(rawValue: $0) } ?? .monochrome
    }
}

/// How a severity is drawn: a semantic colour, or white at an opacity (Desktop's `SEV_STYLE_COLORED` and `SEV_STYLE_MONO`).
enum ContentAdvisoryTone: Equatable, Sendable {
    case danger, accent
    case white(Double)
}

/// What the invitation prompt should do when its inputs change (Desktop's `content-advisory-prompt.tsx` effect).
enum ContentAdvisoryPromptDecision: Equatable, Sendable {
    case none, markSeen, show
}

enum ContentAdvisory {
    /// Desktop's `SEV_RANK`. A category with another severity is not shown.
    static let severityRank: [String: Int] = ["None": 0, "Mild": 1, "Moderate": 2, "Severe": 3]
    /// Desktop's `HOLD_MS`, `HOVER_TAIL_MS` and `EXIT_MS`, the prompt's 12 s hold, and the 0.3 s playback gate.
    static let holdSeconds = 8.0
    static let hoverTailSeconds = 2.5
    static let exitSeconds = 0.16
    static let promptHoldSeconds = 12.0
    static let playbackStartedSeconds = 0.3

    /// The first `tt` and its digits in a title, episode or stream id: "tt0903747:1:2" gives "tt0903747".
    static func imdbID(in raw: String?) -> String? {
        guard let raw, let range = raw.range(of: "tt[0-9]+", options: .regularExpression) else { return nil }
        return String(raw[range])
    }

    /// Reads `{ categories: [{ category, severity }], mpaRating }`. An entry without both strings is skipped, as Desktop does.
    static func guide(_ json: JSONValue) -> ContentAdvisoryGuide {
        var categories: [ContentAdvisoryCategory] = []
        for item in json["categories"].array {
            if let name = item["category"].string, let severity = item["severity"].string {
                categories.append(ContentAdvisoryCategory(category: name, severity: severity))
            }
        }
        let mpaRating = json["mpaRating"].string.flatMap { $0.isEmpty ? nil : $0 }
        return ContentAdvisoryGuide(categories: categories, mpaRating: mpaRating)
    }

    /// The categories the card shows: "None" and unknown severities are dropped, the rest sorted by severity, most severe first.
    /// Equal severities keep the server's order (Swift's sort is not stable, so the index breaks the tie).
    static func rated(_ categories: [ContentAdvisoryCategory]) -> [ContentAdvisoryCategory] {
        categories.enumerated()
            .compactMap { entry -> (rank: Int, index: Int, category: ContentAdvisoryCategory)? in
                guard entry.element.severity != "None", let rank = severityRank[entry.element.severity] else { return nil }
                return (rank, entry.offset, entry.element)
            }
            .sorted { $0.rank != $1.rank ? $0.rank > $1.rank : $0.index < $1.index }
            .map { $0.category }
    }

    /// Desktop's `hasContent`: a rated category, or an MPA rating, is enough to show the card.
    static func showsContent(_ guide: ContentAdvisoryGuide) -> Bool {
        !rated(guide.categories).isEmpty || guide.mpaRating != nil
    }

    /// Desktop's `metaFor`: the SF Symbol and the English label of a category. An unknown category shows its own name.
    static func presentation(of category: String) -> (symbol: String, label: String) {
        let name = category.lowercased()
        if name.contains("sex") || name.contains("nudity") { return ("heart", "Sex & Nudity") }
        if name.contains("violence") || name.contains("gore") { return ("exclamationmark.triangle", "Violence & Gore") }
        if name.contains("profanity") || name.contains("language") { return ("text.bubble", "Profanity") }
        if name.contains("alcohol") || name.contains("drug") || name.contains("smoking") { return ("wineglass", "Alcohol, Drugs & Smoking") }
        if name.contains("frighten") || name.contains("intense") { return ("theatermasks", "Frightening & Intense Scenes") }
        return ("info.circle", category)
    }

    /// Desktop's severity styles. An unknown severity takes the Mild style, as Desktop does.
    static func tone(severity: String, theme: ContentAdvisoryTheme) -> ContentAdvisoryTone {
        switch theme {
        case .colored:
            switch severity {
            case "Severe": return .danger
            case "Moderate": return .accent
            case "None": return .white(0.5)
            default: return .white(0.6)
            }
        case .monochrome:
            switch severity {
            case "Severe": return .white(0.85)
            case "Moderate": return .white(0.7)
            case "None": return .white(0.5)
            default: return .white(0.6)
            }
        }
    }

    static func hasPlaybackStarted(position: Double) -> Bool {
        position > playbackStartedSeconds
    }

    /// Desktop's invitation effect: once seen, never again; with the card already on it is only marked seen; otherwise it
    /// shows when playback is ready and the title has an IMDb id.
    static func promptDecision(seen: Bool, toastOn: Bool, ready: Bool) -> ContentAdvisoryPromptDecision {
        if seen { return .none }
        if toastOn { return .markSeen }
        return ready ? .show : .none
    }
}

/// Desktop's toast timeline: the card appears once per source, when playback has started and the title has something to show.
/// It holds for 8 s, or for 2.5 s after the pointer leaves, and then fades out. Dismiss and Ignore end it at once.
struct ContentAdvisoryToastState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case idle, holding, collapsing, done }

    private(set) var phase: Phase = .idle
    private(set) var hasTriggered = false
    private(set) var paused = false
    private(set) var holdSeconds = ContentAdvisory.holdSeconds

    var isVisible: Bool { phase == .holding || phase == .collapsing }

    /// The seconds until the next step, or nil when the card waits for input.
    var pendingDelay: Double? {
        switch phase {
        case .holding: return paused ? nil : holdSeconds
        case .collapsing: return ContentAdvisory.exitSeconds
        case .idle, .done: return nil
        }
    }

    /// Called whenever the inputs change. Turning the feature off clears the timeline, as Desktop's reset does, so turning it on
    /// again can show the card once more during the same playback.
    mutating func update(enabled: Bool, ready: Bool) {
        guard enabled else {
            self = ContentAdvisoryToastState()
            return
        }
        guard ready, !hasTriggered else { return }
        hasTriggered = true
        phase = .holding
        holdSeconds = ContentAdvisory.holdSeconds
    }

    mutating func pointerEntered() {
        paused = true
    }

    /// A card that is still holding gets the short tail once the pointer leaves.
    mutating func pointerLeft() {
        paused = false
        if phase == .holding { holdSeconds = ContentAdvisory.hoverTailSeconds }
    }

    mutating func dismiss() {
        if isVisible { phase = .collapsing }
    }

    mutating func holdElapsed() {
        if phase == .holding && !paused { phase = .collapsing }
    }

    mutating func exitElapsed() {
        if phase == .collapsing { phase = .done }
    }
}

/// Desktop's invitation card: shown once per device, on the first ready playback of a title with an IMDb id. It closes on
/// "Turn on", "Not now", or after 12 s with no pointer over it.
struct ContentAdvisoryPromptState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case idle, visible, exiting }

    private(set) var phase: Phase = .idle
    private(set) var hovered = false

    var isShown: Bool { phase != .idle }

    var pendingDelay: Double? {
        switch phase {
        case .visible: return hovered ? nil : ContentAdvisory.promptHoldSeconds
        case .exiting: return ContentAdvisory.exitSeconds
        case .idle: return nil
        }
    }

    mutating func show() {
        phase = .visible
        hovered = false
    }

    mutating func pointerChanged(inside: Bool) {
        hovered = inside
    }

    mutating func close() {
        if phase == .visible { phase = .exiting }
    }

    mutating func holdElapsed() {
        if phase == .visible && !hovered { phase = .exiting }
    }

    mutating func exitElapsed() {
        if phase == .exiting { phase = .idle }
    }
}

/// Desktop's `harborImdbParental`: reads the parental guide of a title from Harbor's community server, `/api/imdb/parental/{tt}`.
/// The guide is kept for the session, failures included, as Desktop keeps them. Common Sense Media, which Desktop falls back to,
/// is not reached from iOS.
actor HarborAdvisoryRatings {
    static let shared = HarborAdvisoryRatings()
    static let timeout: TimeInterval = 3
    static let cacheLimit = 200
    typealias Fetch = @Sendable (URL) async throws -> JSONValue

    private let fetch: Fetch
    private var cache: [String: ContentAdvisoryGuide] = [:]
    private var order: [String] = []
    private var inflight: [String: Task<ContentAdvisoryGuide, Never>] = [:]

    init(fetch: @escaping Fetch = { try await HTTPClient().json($0.absoluteString, timeout: HarborAdvisoryRatings.timeout) }) {
        self.fetch = fetch
    }

    static func url(_ imdbID: String) -> URL? {
        guard imdbID.range(of: "^tt[0-9]+$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://harborcommunity.site/api/imdb/parental/\(imdbID)")
    }

    func guide(_ imdbID: String) async -> ContentAdvisoryGuide {
        guard let url = Self.url(imdbID) else { return ContentAdvisoryGuide() }
        if let hit = cache[imdbID] { return hit }
        if let pending = inflight[imdbID] { return await pending.value }
        let load = fetch
        let task = Task<ContentAdvisoryGuide, Never> {
            guard let json = try? await load(url) else { return ContentAdvisoryGuide() }
            return ContentAdvisory.guide(json)
        }
        inflight[imdbID] = task
        let value = await task.value
        inflight[imdbID] = nil
        store(value, for: imdbID)
        return value
    }

    private func store(_ value: ContentAdvisoryGuide, for imdbID: String) {
        if cache[imdbID] == nil { order.append(imdbID) }
        cache[imdbID] = value
        while order.count > Self.cacheLimit {
            let oldest = order.removeFirst()
            cache[oldest] = nil
        }
    }
}
