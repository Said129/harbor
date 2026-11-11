import Foundation

/// What the debrid providers confirmed about the streams of one title, passed to
/// the Rust ranking as Desktop's applyDebridFlags input.
struct DebridVerification: Sendable, Equatable {
    var cached: [String: [String]] = [:]
    var library: [String: [String]] = [:]
    var flags: JSONValue { .object(["cached": Self.object(cached), "library": Self.object(library)]) }
    var isEmpty: Bool { cached.values.allSatisfy(\.isEmpty) && library.values.allSatisfy(\.isEmpty) }
    private static func object(_ map: [String: [String]]) -> JSONValue { .object(map.mapValues { .array($0.map(JSONValue.string)) }) }
    /// Adds what a later check confirmed, as Desktop accumulates results per provider.
    mutating func merge(_ other: DebridVerification) {
        for (slug, hashes) in other.cached { cached[slug, default: []] += hashes.filter { !(cached[slug] ?? []).contains($0) } }
        for (slug, hashes) in other.library { library[slug, default: []] += hashes.filter { !(library[slug] ?? []).contains($0) } }
    }

    /// Rebuilds the flags a previous ranking applied, so ranking the same offers
    /// again (automatic selection) does not lose them.
    static func from(offers: [JSONValue]) -> DebridVerification {
        var value = DebridVerification()
        for raw in offers {
            guard let hash = raw["infoHash"].string?.lowercased(), !hash.isEmpty else { continue }
            for (slug, flag) in raw["cacheVerified"].objectValue where flag == JSONValue.bool(true) {
                if raw["inLibrary"][slug] == JSONValue.bool(true) { value.library[slug, default: []].append(hash) }
                else { value.cached[slug, default: []].append(hash) }
            }
        }
        return value
    }
}

/// Desktop's pipeline cache verification: every configured provider is asked
/// about the title's hashes and its library at the same time. A provider that
/// fails or answers too slowly is ignored, never an error for the stream list.
enum DebridStreamVerifier {
    static let chunk = 100
    /// The whole verification of one provider, so a slow service can only cost
    /// its own badges and never delay the stream list for longer than this.
    static let timeoutSeconds = 8.0

    static func hashes(_ streams: [JSONValue]) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for stream in streams {
            guard let hash = stream["infoHash"].string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !hash.isEmpty, seen.insert(hash).inserted else { continue }
            result.append(hash)
        }
        return result
    }

    static func verify(_ streams: [JSONValue], client: DebridClient?) async -> DebridVerification {
        guard let client else { return .init() }
        let providers = await client.providers, wanted = Self.hashes(streams)
        guard !providers.isEmpty, !wanted.isEmpty else { return .init() }
        return await withTaskGroup(of: (DebridProvider, [String], [String]).self) { group in
            for provider in providers {
                group.addTask { await Self.bounded({ await Self.check(provider, hashes: wanted, client: client) }) ?? (provider, [], []) }
            }
            var result = DebridVerification()
            for await (provider, cached, library) in group {
                if !cached.isEmpty { result.cached[provider.rawValue] = cached }
                if !library.isEmpty { result.library[provider.rawValue] = library }
            }
            return result
        }
    }

    private static func check(_ provider: DebridProvider, hashes: [String], client: DebridClient) async -> (DebridProvider, [String], [String]) {
        var cached: [String] = []
        for start in stride(from: 0, to: hashes.count, by: chunk) {
            let part = Array(hashes[start..<min(start + chunk, hashes.count)])
            if let outcome = await Self.bounded({ try await client.cacheCheck(provider, hashes: part) }), let map = outcome.value {
                cached += part.filter { map[$0] == true }
            }
        }
        var library: [String] = []
        if let outcome = await Self.bounded({ try await client.listLibrary(provider) }), let entries = outcome.value {
            let wanted = Set(hashes)
            library = entries.map { $0.hash.lowercased() }.filter { wanted.contains($0) }
        }
        return (provider, cached, library)
    }

    static func bounded<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await work() }
            group.addTask { try? await Task.sleep(for: .seconds(timeoutSeconds)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// Desktop's resolveViaDebrids: providers that already have the file cached come
/// first, each one is tried in turn, a link that looks like a provider's error
/// clip is rejected, and the last provider's code explains a failure.
enum DebridStreamResolver {
    static let errorVideoMaxBytes = 80.0 * 1_048_576

    static func resolve(_ raw: JSONValue, client: DebridClient?, season: Int? = nil, episode: Int? = nil) async throws -> PlaybackSource {
        guard let hash = raw["infoHash"].string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !hash.isEmpty else { throw HarborError(code: "no-source") }
        guard let client else { throw HarborError(code: "no-debrid-configured") }
        let providers = await client.providers
        guard !providers.isEmpty else { throw HarborError(code: "no-debrid-configured") }
        let fileIdx = Self.number(raw["fileIdx"]).map { Int($0) }, expected = Self.number(raw["size"])
        var lastCode: String?
        for provider in order(providers, cached: raw["cached"].objectValue) {
            try Task.checkCancellation()
            switch try await client.playableURL(provider, magnet: hash, fileIdx: fileIdx, season: season, episode: episode) {
            case .failure(let code, _):
                if code == "aborted" { throw CancellationError() }
                lastCode = code
            case .success(let link):
                guard validLink(link, expectedSize: expected) else { lastCode = "stub-or-error-video"; continue }
                guard let source = playbackSource(link, via: provider) else { lastCode = "invalid-playback-url"; continue }
                return source
            }
        }
        throw HarborError(code: lastCode ?? "all-debrids-failed")
    }

    /// Cached on a provider first; otherwise the configured order, as a stable sort.
    static func order(_ providers: [DebridProvider], cached: [String: JSONValue]) -> [DebridProvider] {
        providers.enumerated().sorted { left, right in
            let l = cached[left.element.rawValue] == JSONValue.bool(true), r = cached[right.element.rawValue] == JSONValue.bool(true)
            return l != r ? l : left.offset < right.offset
        }.map(\.element)
    }

    /// Desktop's validateLink: a tiny file, or one far smaller than the release it
    /// should be, is the provider's error clip rather than the requested video.
    static func validLink(_ link: DebridLink, expectedSize: Double?) -> Bool {
        validSize(link.filesize, expectedSize: expectedSize)
    }

    static func validSize(_ filesize: Double?, expectedSize: Double?) -> Bool {
        guard let size = filesize, size > 0 else { return true }
        if size < errorVideoMaxBytes, expectedSize == nil || (expectedSize ?? 0) > errorVideoMaxBytes { return false }
        if let expected = expectedSize, size < expected * 0.4, expected > 100 * 1_048_576 { return false }
        return true
    }

    /// Only a plain http(s) link without control characters reaches the player.
    static func playbackSource(_ link: DebridLink, via provider: DebridProvider) -> PlaybackSource? {
        guard link.url.rangeOfCharacter(from: .controlCharacters) == nil, let url = URL(string: link.url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { return nil }
        let subtitles = link.subtitles?.map { PlaybackSource.Subtitle(url: $0.url, lang: $0.lang, id: $0.id) }
        return PlaybackSource(url: link.url, headers: link.headers, subtitles: subtitles, via: provider.rawValue)
    }

    private static func number(_ value: JSONValue) -> Double? {
        switch value {
        case .integer(let number): Double(number)
        case .unsigned(let number): Double(number)
        case .number(let number): number.isFinite ? number : nil
        default: nil
        }
    }
}
