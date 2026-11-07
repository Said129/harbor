import Foundation

/// SIMKL's community score for a title (Desktop's `lib/simkl/ratings.ts`), read from the Harbor community server's
/// public ratings proxy. No account or key is needed. A score is asked by spec ("imdb:tt0111161", "mal:5114").
actor SimklCommunityRatings {
    static let shared = SimklCommunityRatings()
    /// Desktop asks for at most this many specs in one request.
    static let maxBatch = 120
    private static let cacheLimit = 2_000
    typealias Fetch = @Sendable (URL) async throws -> JSONValue

    private struct Remembered { let value: Double? }
    private let fetch: Fetch
    private var cache: [String: Remembered] = [:]

    init(fetch: @escaping Fetch = { try await HTTPClient().json($0.absoluteString, timeout: 15) }) { self.fetch = fetch }

    static func url(_ specs: [String]) -> URL? {
        var parts = URLComponents(string: "https://harborcommunity.site/api/simkl/ratings")
        parts?.queryItems = [URLQueryItem(name: "ids", value: specs.joined(separator: ","))]
        return parts?.url
    }

    /// Scores by lower-cased spec; a title without one is left out. Answers are remembered, including "none" after an
    /// HTTP error; a request that never arrived is asked again next time, as on Desktop.
    func ratings(_ specs: [String]) async -> [String: Double] {
        var wanted: [String] = []
        for spec in specs.map({ $0.lowercased() }) where !spec.isEmpty && !wanted.contains(spec) { wanted.append(spec) }
        var found: [String: Double] = [:]
        var missing: [String] = []
        for spec in wanted {
            if let known = cache[spec] { if let value = known.value { found[spec] = value } } else { missing.append(spec) }
        }
        for start in stride(from: 0, to: missing.count, by: Self.maxBatch) {
            let batch = Array(missing[start..<min(start + Self.maxBatch, missing.count)])
            guard let url = Self.url(batch) else { continue }
            do {
                let data = try await fetch(url)
                if cache.count > Self.cacheLimit { cache.removeAll() }
                for spec in batch {
                    let value = data["ratings"][spec]["rating"].numericValue
                    cache[spec] = Remembered(value: value)
                    if let value { found[spec] = value }
                }
            } catch let error as HarborError where error.code.hasPrefix("http-") {
                for spec in batch { cache[spec] = Remembered(value: nil) }
            } catch { }
        }
        return found
    }

    func rating(_ spec: String) async -> Double? { await ratings([spec])[spec.lowercased()] }
}
