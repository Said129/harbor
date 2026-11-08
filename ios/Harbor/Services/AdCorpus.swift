import CryptoKit
import Foundation

/// One marked ad range of a release in the signed corpus, in seconds.
struct AdCorpusRange: Equatable, Sendable {
    let start: Double
    let end: Double
}

/// One corpus entry (`adcorpus.ts`'s `CorpusEntry`): the ranges marked for one content and one exact source.
struct AdCorpusEntry: Equatable, Sendable {
    let content: String
    let source: String
    let ranges: [AdCorpusRange]
}

/// Desktop's `lib/skip-intro/adcorpus.ts` as pure functions: the signature check, the entries and the match.
enum AdCorpusRules {
    static let endpoint = "https://harbor.site/updates/ad-segments.json"
    /// The base64 Ed25519 key that signs the corpus.
    static let publicKey = "yszDA2+G0Rtep39h67iuhl8+5pCQkM+O4D4pMnpg4Ks="

    /// The corpus only holds release hashes (`ih_`) and release fingerprints (`rg_`).
    static func acceptsSource(_ source: String) -> Bool {
        source.hasPrefix("ih_") || source.hasPrefix("rg_")
    }

    /// The entries of a signed payload, or nil when the key, the signature or the payload does not hold.
    /// The signature is checked over the payload's UTF-8 bytes, as Desktop does.
    static func verifiedEntries(payload: String, signature: String, publicKey: String) -> [AdCorpusEntry]? {
        guard let keyBytes = Data(base64Encoded: publicKey), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes),
              let signed = Data(base64Encoded: signature) else { return nil }
        let message = Data(payload.utf8)
        guard key.isValidSignature(signed, for: message),
              let json = try? JSONDecoder().decode(JSONValue.self, from: message) else { return nil }
        // A payload that is not an array gives no entries, as in Desktop.
        return json.array.compactMap { (value: JSONValue) -> AdCorpusEntry? in entry(value) }
    }

    /// One entry. Ranges that are not finite, or that end at or before they start, are dropped.
    static func entry(_ value: JSONValue) -> AdCorpusEntry? {
        guard let content = value["content"].string, let source = value["source"].string else { return nil }
        let ranges = value["ranges"].array.compactMap { (item: JSONValue) -> AdCorpusRange? in
            guard let start = number(item["start"]), let end = number(item["end"]),
                  start.isFinite, end.isFinite, end > start else { return nil }
            return AdCorpusRange(start: start, end: end)
        }
        return AdCorpusEntry(content: content, source: source, ranges: ranges)
    }

    static func number(_ value: JSONValue) -> Double? {
        switch value {
        case .number(let number): return number
        case .integer(let number): return Double(number)
        case .unsigned(let number): return Double(number)
        default: return nil
        }
    }

    /// The ad segments of one content and one exact source. Empty for a source the corpus does not hold.
    static func segments(in entries: [AdCorpusEntry], content: String, source: String) -> [SkipSegment] {
        guard !content.isEmpty, acceptsSource(source) else { return [] }
        return entries
            .filter { $0.content == content && $0.source == source }
            .flatMap { $0.ranges }
            .map { SkipSegment(kind: .ad, start: $0.start, end: $0.end, source: "adcorpus") }
            .filter { $0.start.isFinite && $0.end > $0.start }
    }
}

/// Desktop's `fetchAdSegments` cache: the signed corpus, fetched and verified, kept for the session. A lookup
/// asks the network again when `fresh` is set, as Desktop does for each player. A failed load is not kept.
actor AdCorpus {
    typealias Load = @Sendable () async throws -> JSONValue

    static let shared = AdCorpus()

    private let publicKey: String
    private let load: Load
    private var entries: [AdCorpusEntry]?
    private var pending: Task<[AdCorpusEntry]?, Never>?

    init(publicKey: String = AdCorpusRules.publicKey, load: @escaping Load = { try await HTTPClient().json(AdCorpusRules.endpoint) }) {
        self.publicKey = publicKey
        self.load = load
    }

    /// The ad segments for one content and one exact release. Any failure gives an empty list.
    func segments(content: String, source: String, fresh: Bool = false) async -> [SkipSegment] {
        guard !content.isEmpty, AdCorpusRules.acceptsSource(source) else { return [] }
        return AdCorpusRules.segments(in: await corpus(fresh: fresh), content: content, source: source)
    }

    private func corpus(fresh: Bool) async -> [AdCorpusEntry] {
        if !fresh, let entries { return entries }
        if let pending { return await pending.value ?? [] }
        let key = publicKey
        let loader = load
        let task = Task { await AdCorpus.fetch(publicKey: key, load: loader) }
        pending = task
        let loaded = await task.value
        pending = nil
        if let loaded { entries = loaded }
        return loaded ?? []
    }

    /// Nil on any failure, so the failure is not kept.
    private static func fetch(publicKey: String, load: Load) async -> [AdCorpusEntry]? {
        guard !publicKey.isEmpty, let signed = try? await load(),
              let payload = signed["payload"].string, let signature = signed["sig"].string else { return nil }
        return AdCorpusRules.verifiedEntries(payload: payload, signature: signature, publicKey: publicKey)
    }
}
