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
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url)).map { Self(id: $0.id, title: SportsRules.leagueTitle(id: $0.id, title: $0.title), path: $0.path, group: $0.group, logo: $0.logo) }
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
    var timeline: [SportsTimelineEntry] = []
    var commentary: [String] = []
}
enum SportsTimelineKind: Hashable, Sendable {
    case goal, yellowCard, redCard, substitution, other
    /// Desktop's keyEvents classification; the first matching word wins.
    static func classify(_ typeText: String) -> Self {
        let text = typeText.lowercased()
        if text.contains("goal") { return .goal }
        if text.contains("yellow") { return .yellowCard }
        if text.contains("red") { return .redCard }
        if text.contains("substitution") { return .substitution }
        return .other
    }
}
struct SportsTimelineEntry: Identifiable, Hashable, Sendable {
    let id: String
    let clock: String
    let kind: SportsTimelineKind
    let text: String
    let participant: String?
}
/// Pure decisions shared by the Sports views, services and tests (Desktop's espn-scoreboard.ts, live-schedule.ts, reminders.ts).
enum SportsRules {
    static let reminderLeads = [5, 15, 60, 1440]
    static let defaultReminderLead = 15
    /// Desktop's getLeagueLabel: the NCAA soccer leagues are labelled as soccer.
    static func leagueTitle(id: String, title: String, language: String? = nil) -> String {
        let pattern: String
        switch id {
        case "NCAAMSOCCER": pattern = "NCAA Men's {sport}"
        case "NCAAWSOCCER": pattern = "NCAA Women's {sport}"
        default: return title
        }
        return DesktopInterfaceText.value(pattern, variables: ["sport": DesktopInterfaceText.value("Soccer", language: language)], language: language)
    }
    /// Desktop's sortGames: live, then upcoming, then finished; finished games newest first.
    static func ordered(_ events: [SportsEvent]) -> [SportsEvent] {
        func rank(_ state: String) -> Int { state == "in" ? 0 : state == "pre" ? 1 : 2 }
        return events.sorted { a, b in
            let left = rank(a.state), right = rank(b.state)
            if left != right { return left < right }
            if a.state == "post" { return a.date > b.date }
            return a.date < b.date
        }
    }
    static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    /// Desktop's liveDateRange: yesterday and today, so games that continue past midnight stay covered.
    static func liveRange(today: String) -> String {
        guard today.count == 8, let year = Int(today.prefix(4)), let month = Int(today.dropFirst(4).prefix(2)), let day = Int(today.suffix(2)) else { return today }
        let calendar = Calendar(identifier: .gregorian)
        guard let base = calendar.date(from: DateComponents(year: year, month: month, day: day)), let previous = calendar.date(byAdding: .day, value: -1, to: base) else { return today }
        return dayStamp(previous, calendar: calendar) + "-" + today
    }
    /// The scoreboard request: live scope and today use the yesterday-to-today range.
    static func requestDate(selected: String, today: String, state: String) -> String {
        state == "in" || selected == today ? liveRange(today: today) : selected
    }
    /// Keeps the events a day view or live scope shows. Live scope takes live games from any loaded day.
    static func includes(eventDay: String, eventState: String, selected: String, today: String, state: String) -> Bool {
        if state == "in" { return eventState == "in" }
        return eventDay == selected || (selected == today && eventState == "in")
    }
    /// Desktop's syncSportsReminders: a pending reminder follows its game's start time.
    static func reminderNeedsResync(scheduledFire: Date?, event: SportsEvent, minutes: Int) -> Bool {
        guard let scheduledFire = scheduledFire, event.state == "pre" else { return false }
        let expected = event.date.addingTimeInterval(-Double(minutes) * 60)
        return abs(scheduledFire.timeIntervalSince(expected)) >= 1
    }
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
