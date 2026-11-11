import Foundation

/// Desktop's Wikidata crew query (`CREW_QUERY` in `src/lib/providers/wikidata-graph.ts`): the other films that share
/// crew members with a title, found by its IMDb id. The query and the parsing are pure; `load` makes one public request
/// with the IMDb id only, and no account or key is sent.
enum SharedCrewService {
    static let timeout: TimeInterval = 12

    /// The SPARQL text for an IMDb id, or nil when the id is not in `tt` form.
    static func query(imdbID: String) -> String? {
        guard imdbID.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil else { return nil }
        return """
        SELECT ?other ?otherLabel ?tmdb (COUNT(DISTINCT ?person) AS ?shared) (GROUP_CONCAT(DISTINCT ?personLabel; separator=" | ") AS ?who) WHERE {
          ?f wdt:P345 "\(imdbID)" .
          VALUES ?role { wdt:P57 wdt:P344 wdt:P86 wdt:P1040 wdt:P2554 wdt:P2515 wdt:P58 }
          ?f ?role ?person .
          ?other ?role ?person .
          ?other wdt:P31 wd:Q11424 ; wdt:P4947 ?tmdb .
          FILTER(?other != ?f)
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en,mul". ?other rdfs:label ?otherLabel . ?person rdfs:label ?personLabel }
        }
        GROUP BY ?other ?otherLabel ?tmdb HAVING(COUNT(DISTINCT ?person) >= \(SharedCrewRules.minimumShared)) ORDER BY DESC(?shared) LIMIT 12
        """
    }

    /// The GET request that runs the crew query, or nil when the id is not an IMDb id.
    static func request(imdbID: String) -> URLRequest? {
        guard let text = query(imdbID: imdbID), var components = URLComponents(string: "https://query.wikidata.org/sparql") else { return nil }
        components.queryItems = [URLQueryItem(name: "query", value: text), URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Desktop's `parseCrew`: each row with a TMDB id and a label becomes a film keyed as `tmdb:movie:<id>`.
    static func films(from data: Data) -> [SharedCrewFilm] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [String: Any],
              let rows = results["bindings"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row -> SharedCrewFilm? in
            guard let tmdb = cell(row, "tmdb"), let name = cell(row, "otherLabel"), !name.hasPrefix("http"),
                  let sharedText = cell(row, "shared"), let shared = Int(sharedText), shared > 0 else { return nil }
            let who = (cell(row, "who") ?? "").components(separatedBy: " | ").filter { !$0.isEmpty }
            return SharedCrewFilm(metaId: "tmdb:movie:" + tmdb, name: name, shared: shared, who: who)
        }
    }

    /// The films that share at least the minimum crew for a title. Empty when the query fails or the id is not an IMDb id.
    static func load(imdbID: String) async -> [SharedCrewFilm] {
        guard let request = request(imdbID: imdbID) else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return SharedCrewRules.films(films(from: data))
        } catch {
            return []
        }
    }

    private static func cell(_ row: [String: Any], _ key: String) -> String? {
        guard let entry = row[key] as? [String: Any], let raw = entry["value"] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The crew films per IMDb id for the session, so reopening a title does not ask Wikidata again. Like Desktop's cache,
/// it keeps a bounded number of titles.
actor SharedCrewStore {
    static let shared = SharedCrewStore()
    private static let limit = 80
    private var values: [String: [SharedCrewFilm]] = [:]

    func films(imdbID: String) async -> [SharedCrewFilm] {
        if let saved = values[imdbID] { return saved }
        let films = await SharedCrewService.load(imdbID: imdbID)
        if values.count >= Self.limit { values.removeAll() }
        values[imdbID] = films
        return films
    }
}
