import Foundation
import Observation

enum SpooktoberSeason {
    static func available(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return parts.month == 10 || (parts.year == 2026 && parts.month == 9 && (parts.day ?? 0) >= 28)
    }
    static func nextCheck(_ date: Date, calendar: Calendar = .current) -> Double {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else { return 60 }
        return max(1, tomorrow.timeIntervalSince(date) + 0.1)
    }
}

@MainActor @Observable
final class SpooktoberInvitationPreferences {
    private let key: String
    private(set) var dismissed = false
    private(set) var ready = false
    private(set) var error: String?
    init(owner: String) {
        key = "spooktober-invitation-" + EBookShelf.hash(owner)
        do { dismissed = try KeychainStore().read(key, as: Bool.self) ?? false; ready = true }
        catch { error = "No se pudo recuperar la preferencia de Spooktober." }
    }
    func dismiss() {
        guard ready else { return }
        do { try KeychainStore().write(true, key: key); dismissed = true; error = nil }
        catch { error = "No se pudo guardar el cambio. La preferencia anterior se conserva." }
    }
}

struct SpooktoberItem: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let year: String
    let type: String
    let section: String
    let creator: String
    let description: String
    let poster: String
    let source: String
    var backdrop: String?
    var runtime: String?
    var genres: [String]?
    var imdbRating: String?
    var localPoster: String? {
        guard poster.hasPrefix("assets/posters/") else { return nil }
        return "spook-poster-" + URL(fileURLWithPath: poster).deletingPathExtension().lastPathComponent
    }
    var sourceURL: URL? {
        guard let url = URL(string: source), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    var media: Media? {
        guard ["Film", "Series"].contains(type) else { return nil }
        let pattern = "^tt[0-9]{5,12}$"
        let identifier: String?
        if id.range(of: pattern, options: .regularExpression) != nil { identifier = id }
        else {
            identifier = sourceURL?.pathComponents.first { $0.range(of: pattern, options: .regularExpression) != nil }
        }
        guard let identifier else { return nil }
        var result = Media(id: identifier, type: type == "Series" ? "series" : "movie", name: title)
        result.poster = localPoster == nil ? poster : nil
        result.background = backdrop
        result.description = description; result.releaseInfo = year
        result.runtime = runtime; result.genres = genres; result.imdbRating = imdbRating
        result.director = type == "Film" ? [creator] : nil
        return result
    }
}

enum SpooktoberCatalog {
    static func load() throws -> [SpooktoberItem] {
        guard let url = Bundle.main.url(forResource: "SpooktoberContent", withExtension: "json") else { throw HarborError(code: "spooktober-content") }
        let data = try Data(contentsOf: url)
        guard data.count <= 1024 * 1024 else { throw HarborError(code: "spooktober-content") }
        let items = try JSONDecoder().decode([SpooktoberItem].self, from: data)
        guard !items.isEmpty, items.count <= 1_000, Set(items.map(\.id)).count == items.count else { throw HarborError(code: "spooktober-content") }
        return items
    }
}
