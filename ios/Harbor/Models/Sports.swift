import Foundation
import Observation

struct SportsLeague: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let path: String
    let group: String
    let logo: String?
    static func catalog() throws -> [Self] {
        guard let url = Bundle.main.url(forResource: "SportsLeagues", withExtension: "json") else { throw HarborError(code: "sports-catalog") }
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
    }
}
struct SportsPeriod: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let value: String
}
struct SportsSide: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let logo: String?
    let score: String?
    let winner: Bool
    var record: String?
    var periods: [SportsPeriod] = []
}
struct SportsEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let eventID: String
    let league: SportsLeague
    let title: String
    let date: Date
    let state: String
    let status: String
    let sides: [SportsSide]
    let venue: String
    let broadcasts: [String]
    let link: String?
}
struct SportsStatistic: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
}
struct SportsStatGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let values: [SportsStatistic]
}
struct SportsSummary: Sendable {
    var groups: [SportsStatGroup] = []
    var commentary: [String] = []
}
private struct SportsPersonalization: Codable {
    var leagues: [String] = ["ROSHN", "EPL", "UCL", "NBA", "NFL"]
    var favorites: Set<String> = []
}

@MainActor @Observable
final class SportsPreferences {
    let owner: String
    private var stored = SportsPersonalization()
    private(set) var ready = false
    var error: String?
    var leagues: [String] { stored.leagues }
    var favorites: Set<String> { stored.favorites }
    private var key: String { "sports-preferences-" + EBookShelf.hash(owner) }
    init(owner: String) {
        self.owner = owner
        do { stored = try KeychainStore().read(key, as: SportsPersonalization.self) ?? SportsPersonalization(); ready = true }
        catch { self.error = "No se pudo recuperar la configuración de Sports. Los favoritos se conservan." }
    }
    func setLeagues(_ ids: [String]) throws { var next = stored; next.leagues = Array(Set(ids)).sorted(); try save(next) }
    func toggle(_ side: SportsSide, league: SportsLeague) throws {
        let id = league.path + ":" + side.id
        var next = stored
        if next.favorites.contains(id) { next.favorites.remove(id) } else { next.favorites.insert(id) }
        try save(next)
    }
    func favorite(_ side: SportsSide, league: SportsLeague) -> Bool { stored.favorites.contains(league.path + ":" + side.id) }
    private func save(_ next: SportsPersonalization) throws {
        guard ready, next.leagues.count <= 200, next.favorites.count <= 2_000 else { throw HarborError(code: "sports-store") }
        try KeychainStore().write(next, key: key); stored = next
    }
}
