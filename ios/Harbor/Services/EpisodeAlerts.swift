import Foundation
import UserNotifications

/// The release kinds Desktop's webhook settings count: `notifyMovies`, `notifyTv` and `notifyAnime` (`settings/types.ts`).
enum EpisodeAlertKind: String, Sendable, Equatable {
    case movie, series, anime
}

/// One upcoming release the planner may alert about. `id` is Desktop's calendar item id: the title's id, plus
/// `:season:episode` for an episode (`calendar-library.ts`).
struct EpisodeAlertEvent: Equatable, Sendable {
    let id: String
    let title: String
    let season: Int?
    let episode: Int?
    /// The episode's own title, printed after its label when the source has one.
    var episodeTitle: String? = nil
    /// The release instant when `hasTime`, otherwise the start of the release day in the planner's calendar.
    let date: Date
    let hasTime: Bool
    let kind: EpisodeAlertKind
}

/// The person's choices for these alerts. Built from `EpisodeAlertPreferences.settings`.
struct EpisodeAlertSettings: Equatable, Sendable {
    var enabled = false
    var leadMinutes = EpisodeAlertPlanner.defaultLeadMinutes
    var movies = true
    var series = true
    var anime = true
    /// Desktop's "My library" source. Off means no library releases are scheduled.
    var library = true
}

/// One local notification the planner wants pending.
struct PlannedEpisodeAlert: Equatable, Sendable {
    /// Desktop's dedupe key: `library:desktop:<item id>` (`webhook-engine.ts`, `legacyKey`).
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
}

/// Pure planning of the release alerts. No UserNotifications, no network, no clock except the `now` it is given.
enum EpisodeAlertPlanner {
    /// Desktop's key prefix for the library source, `${source}:${kind}:${item.id}` with kind "desktop".
    static let identifierPrefix = "library:desktop:"
    /// Desktop's `WINDOW_DAYS_TRACK` (`webhook-engine.ts`): releases up to 14 days ahead. Desktop's fire window is two days,
    /// but Desktop polls while open and this app schedules ahead, so the horizon is the tracking window. The 60 cap bounds it.
    static let windowDays = 14
    /// Desktop's live-TV `leadMinutes` default (`webhook-engine.ts`). Desktop itself has no lead time for episodes.
    static let defaultLeadMinutes = 15
    static let leadOptions = [0, 15, 30, 60]
    /// Date-only releases have no hour, so they alert at this local hour on their day.
    static let dateOnlyHour = 9
    /// Pending requests kept by this feature. The system allows 64 per app; the rest is left for other features.
    static let maxPending = 60

    /// The alerts for `events` that are due after `now`, earliest first, at most `maxPending`.
    /// `alreadyAlerted` holds identifiers already delivered; Desktop alerts about an item once, so they are not planned again.
    static func plan(_ events: [EpisodeAlertEvent], settings: EpisodeAlertSettings, now: Date, calendar: Calendar = .current,
                     alreadyAlerted: Set<String> = []) -> [PlannedEpisodeAlert] {
        guard settings.enabled else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let lastDay = calendar.date(byAdding: .day, value: windowDays, to: today) else { return [] }
        var seen = Set<String>()
        var planned: [PlannedEpisodeAlert] = []
        for event in events where isWanted(event, settings: settings) {
            let day = calendar.startOfDay(for: event.date)
            guard day >= today, day <= lastDay else { continue }
            guard let fire = fireDate(for: event, leadMinutes: settings.leadMinutes, calendar: calendar), fire > now else { continue }
            let identifier = identifierPrefix + event.id
            guard !alreadyAlerted.contains(identifier), seen.insert(identifier).inserted else { continue }
            planned.append(PlannedEpisodeAlert(identifier: identifier, fireDate: fire, title: headline(event), body: body(event, calendar: calendar)))
        }
        planned.sort(by: isEarlier)
        return Array(planned.prefix(maxPending))
    }

    static func isWanted(_ event: EpisodeAlertEvent, settings: EpisodeAlertSettings) -> Bool {
        switch event.kind {
        case .movie: return settings.movies
        case .series: return settings.series
        case .anime: return settings.anime
        }
    }

    /// Timed releases alert `leadMinutes` before; date-only releases alert at `dateOnlyHour` on their day.
    static func fireDate(for event: EpisodeAlertEvent, leadMinutes: Int, calendar: Calendar) -> Date? {
        if event.hasTime { return event.date.addingTimeInterval(-Double(leadMinutes) * 60) }
        return calendar.date(bySettingHour: dateOnlyHour, minute: 0, second: 0, of: event.date)
    }

    /// Desktop's notification title: the kind's icon, then the calendar name (`calendar.ts`, `fireWebhook`).
    static func headline(_ event: EpisodeAlertEvent) -> String {
        let icon: String
        switch event.kind {
        case .movie: icon = "🎬"
        case .series: icon = "📺"
        case .anime: icon = "🍙"
        }
        return icon + " " + label(event)
    }

    /// "Show S01E02" or "Show S01E02: Title", as Desktop names a library episode; a movie is its name.
    static func label(_ event: EpisodeAlertEvent) -> String {
        guard let season = event.season, let number = event.episode else { return event.title }
        var text = "\(event.title) S\(pad(season))E\(pad(number))"
        if let episodeTitle = event.episodeTitle, !episodeTitle.isEmpty { text += ": " + episodeTitle }
        return text
    }

    /// Desktop's notification body: the day, then " · " and the hour when the source has one (`desktopNotifyBody`).
    static func body(_ event: EpisodeAlertEvent, calendar: Calendar) -> String {
        let day = dayText(event.date, calendar: calendar)
        guard event.hasTime else { return day }
        return day + " · " + CalendarTime.timeLabel(event.date, calendar: calendar)
    }

    private static func isEarlier(_ lhs: PlannedEpisodeAlert, _ rhs: PlannedEpisodeAlert) -> Bool {
        if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
        return lhs.identifier < rhs.identifier
    }

    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

    private static func dayText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

/// The part of UNUserNotificationCenter the scheduler needs. `SystemEpisodeAlertCenter` is the real one; tests use a fake.
@MainActor
protocol EpisodeAlertNotificationCenter: AnyObject {
    func isAuthorized() async -> Bool
    func requestAuthorization() async -> Bool
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func add(_ alert: PlannedEpisodeAlert) async throws
    func remove(identifiers: [String])
}

/// Keeps the pending alerts this feature owns equal to a planned set. Other pending requests (sports reminders) are not touched.
@MainActor
final class EpisodeAlertScheduler {
    private let center: any EpisodeAlertNotificationCenter

    init(center: any EpisodeAlertNotificationCenter = SystemEpisodeAlertCenter()) {
        self.center = center
    }

    func authorized() async -> Bool { await center.isAuthorized() }
    func requestAuthorization() async -> Bool { await center.requestAuthorization() }

    /// Identifiers of this feature's alerts already delivered, so a later plan does not repeat them.
    func alertedIdentifiers() async -> Set<String> {
        let delivered = await center.deliveredIdentifiers().filter { $0.hasPrefix(EpisodeAlertPlanner.identifierPrefix) }
        return Set(delivered)
    }

    /// Removes the pending alerts this feature owns, then adds `alerts`.
    func replace(with alerts: [PlannedEpisodeAlert]) async throws {
        let owned = await ownedIdentifiers()
        center.remove(identifiers: owned)
        for alert in alerts { try await center.add(alert) }
    }

    func removeAll() async {
        let owned = await ownedIdentifiers()
        center.remove(identifiers: owned)
    }

    private func ownedIdentifiers() async -> [String] {
        await center.pendingIdentifiers().filter { $0.hasPrefix(EpisodeAlertPlanner.identifierPrefix) }
    }
}

/// UNUserNotificationCenter behind `EpisodeAlertNotificationCenter`. Triggers are calendar triggers, as the sports reminders use.
@MainActor
final class SystemEpisodeAlertCenter: EpisodeAlertNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    func isAuthorized() async -> Bool {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let status = settings.authorizationStatus
                continuation.resume(returning: status == .authorized || status == .provisional)
            }
        }
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    func deliveredIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.map { $0.request.identifier })
            }
        }
    }

    func add(_ alert: PlannedEpisodeAlert) async throws {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let request = UNNotificationRequest(identifier: alert.identifier, content: content, trigger: trigger)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if error != nil { continuation.resume(throwing: HarborError(code: "episode-alert-save")) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    func remove(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Builds the library's upcoming releases and reschedules the alerts. Called when the library loads and when the app becomes active.
@MainActor
enum EpisodeAlertRefresh {
    /// Desktop's `TICK_INTERVAL_MS` (`webhook-loop-mount.tsx`): a background check runs at most every 30 minutes unless forced.
    static let minimumInterval: TimeInterval = 30 * 60
    private static var lastRun: Date?
    /// The account, profile and library size of the last run. A change (a profile switch, the library arriving) runs at once.
    private static var lastSignature: String?
    /// One calendar model for the whole app run, so its title metadata cache survives between refreshes.
    private static let model = CalendarModel()

    static func refresh(app: AppModel, force: Bool = false, now: Date = Date()) async {
        guard app.storageReady else { return }
        let signature = app.accountOperationScope + "|" + String(app.library.items.count)
        if !force, signature == lastSignature, let lastRun, now.timeIntervalSince(lastRun) < minimumInterval { return }
        // Another profile may have changed the saved values since the last run.
        EpisodeAlertPreferences.shared.reloadPreferences()
        let settings = EpisodeAlertPreferences.shared.settings
        let scheduler = EpisodeAlertScheduler()
        let allowed = await scheduler.authorized()
        lastRun = now
        lastSignature = signature
        guard settings.enabled, allowed else {
            await scheduler.removeAll()
            return
        }
        // A library still loading, or a load cut short, must not wipe the alerts that are already pending.
        guard !app.library.loading, !app.library.items.isEmpty else {
            lastRun = nil
            return
        }
        var found: [EpisodeAlertEvent]? = []
        if settings.library { found = await libraryEvents(app: app, now: now) }
        guard let events = found else {
            lastRun = nil
            return
        }
        let alerted = await scheduler.alertedIdentifiers()
        let planned = EpisodeAlertPlanner.plan(events, settings: settings, now: now, alreadyAlerted: alerted)
        do {
            try await scheduler.replace(with: planned)
        } catch {
            lastRun = nil
        }
    }

    /// This month, and the next one when the window crosses into it. Reuses the calendar's library path.
    /// The library's releases in the window, or nil when a month did not load or the task was cancelled (a partial list).
    private static func libraryEvents(app: AppModel, now: Date) async -> [EpisodeAlertEvent]? {
        let calendar = Calendar.current
        let windowEnd = calendar.date(byAdding: .day, value: EpisodeAlertPlanner.windowDays, to: now) ?? now
        var months = [now]
        if !calendar.isDate(windowEnd, equalTo: now, toGranularity: .month) { months.append(windowEnd) }
        var releases: [ReleaseEvent] = []
        for month in months {
            await model.load(month: month, app: app)
            guard model.error == nil, !Task.isCancelled else { return nil }
            releases += model.events
        }
        var seen = Set<String>()
        return releases.compactMap { alertEvent($0, calendar: calendar) }.filter { seen.insert($0.id).inserted }
    }

    /// The alert view of a library release. Date-only values keep their day; timed values keep their instant.
    /// Desktop marks a title as anime from its animation genre (`calendar-library.ts`, `isAnimationGenre`).
    static func alertEvent(_ release: ReleaseEvent, calendar: Calendar) -> EpisodeAlertEvent? {
        let episode = release.episode
        let season = episode?.season
        let number = episode?.episode
        let genres = release.media.genres ?? []
        let animation = genres.contains { ["animation", "anime"].contains($0.lowercased()) }
        let kind: EpisodeAlertKind = (release.kind == "anime" || animation) ? .anime : (release.kind == "movie" ? .movie : .series)
        var id = release.media.id
        if let season, let number { id += ":\(season):\(number)" }
        let raw = episode?.released ?? release.media.released ?? ""
        let dateOnly = !raw.contains("T") || raw.contains("T00:00:00")
        let date = dateOnly ? (CalendarTime.startOfDay(raw, calendar: calendar) ?? release.date) : release.date
        let title = release.media.name
        guard !title.isEmpty else { return nil }
        return EpisodeAlertEvent(id: id, title: title, season: season, episode: number, episodeTitle: episode?.title ?? episode?.name,
                                 date: date, hasTime: !dateOnly, kind: kind)
    }
}
