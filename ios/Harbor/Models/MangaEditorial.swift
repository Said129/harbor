import Foundation

struct MangaEditorial: Decodable {
    struct Collection: Decodable, Identifiable, Sendable {
        let id: String
        let name: String
        let subtitle: String?
        let titles: [String]
    }
    struct Universe: Decodable, Identifiable, Sendable {
        let id: String
        let name: String
        let query: String
        let logo: String?
        let backdrop: String?
    }
    let collections: [Collection]
    let universes: [Universe]
    static let original: MangaEditorial? = {
        guard let url = Bundle.main.url(forResource: "DesktopMangaEditorial", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()
    static func title(_ key: String) -> String {
        switch key {
        case "Most Popular": "Más popular"
        case "Critically Acclaimed": "Aclamados por la crítica"
        case "Featured at Anime Expo": "Destacado en Anime Expo"
        case "Eisner Award Winners": "Ganadores del Premio Eisner"
        case "Harvey Award Winners": "Ganadores del Premio Harvey"
        case "Seiun Award Winners": "Ganadores del Premio Seiun"
        default: key
        }
    }
    static func normalized(_ title: String) -> String {
        title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\b(manga|the)\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
    static func best(_ items: [MangaBook], title: String) -> MangaBook? {
        let key = normalized(title)
        guard !key.isEmpty else { return nil }
        return items.first { normalized($0.title) == key }
            ?? items.first { let name = normalized($0.title); return !name.isEmpty && (name.contains(key) || key.contains(name)) }
    }
}

/// Resolves the original editorial titles against the user's actual sources.
/// All connections and cached results belong to this screen and its account.
actor MangaEditorialSearch {
    let client: SuwayomiClient?
    let sources: [MangaSource]
    let local: [MangaBook]
    private var cache: [String: MangaBook] = [:]
    init(client: SuwayomiClient?, sources: [MangaSource], local: [MangaBook]) {
        self.client = client; self.sources = sources; self.local = local
    }
    func resolve(_ title: String) async throws -> MangaBook? {
        let key = MangaEditorial.normalized(title)
        if let item = cache[key] { return item }
        if let item = MangaEditorial.best(local, title: title) { cache[key] = item; return item }
        guard let client else { return nil }
        var firstFailure: Error?
        var responded = false
        for source in sources {
            try Task.checkCancellation()
            do {
                let result = try await client.browse(source: source.id, latest: false, query: title, page: 1)
                responded = true
                if let item = MangaEditorial.best(result.0, title: title) { cache[key] = item; return item }
            } catch is CancellationError { throw CancellationError() }
            catch { firstFailure = firstFailure ?? error }
        }
        if !responded, let firstFailure { throw firstFailure }
        return nil
    }
}
