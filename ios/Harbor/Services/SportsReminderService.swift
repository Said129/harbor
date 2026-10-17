import Foundation
import UserNotifications

actor SportsReminderService {
    static let shared = SportsReminderService()
    private let center = UNUserNotificationCenter.current()
    private var activeOwner: String?
    func schedule(_ event: SportsEvent, owner: String, minutes: Int) async throws {
        guard activeOwner == owner else { throw HarborError(code: "sports-store") }
        let fire = event.date.addingTimeInterval(-Double(minutes) * 60)
        guard fire.timeIntervalSinceNow > 1 else { throw HarborError(code: "sports-reminder-past") }
        let allowed = try await authorize()
        guard allowed else { throw HarborError(code: "sports-reminder-permission") }
        guard activeOwner == owner else { throw HarborError(code: "sports-store") }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = minutes == 0 ? "El evento empieza ahora · " + event.league.title : "Empieza en \(minutes) minutos · " + event.league.title
        content.sound = .default
        content.userInfo = ["harborSportsOwner": EBookShelf.hash(owner)]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try await add(UNNotificationRequest(identifier: identifier(event, owner: owner), content: content, trigger: trigger))
        if activeOwner != owner { center.removePendingNotificationRequests(withIdentifiers: [identifier(event, owner: owner)]); throw HarborError(code: "sports-store") }
    }
    func scheduled(_ event: SportsEvent, owner: String) async -> Bool {
        let ids = await pendingIDs()
        return activeOwner == owner && ids.contains(identifier(event, owner: owner))
    }
    func cancel(_ event: SportsEvent, owner: String) { center.removePendingNotificationRequests(withIdentifiers: [identifier(event, owner: owner)]) }
    func removeOtherAccounts(owner: String) async {
        activeOwner = owner
        let prefix = "harbor-sports-" + EBookShelf.hash(owner) + "-"
        let old = await pendingIDs().filter { $0.hasPrefix("harbor-sports-") && !$0.hasPrefix(prefix) }
        if activeOwner == owner { center.removePendingNotificationRequests(withIdentifiers: old) }
    }
    private func identifier(_ event: SportsEvent, owner: String) -> String { "harbor-sports-" + EBookShelf.hash(owner) + "-" + EBookShelf.hash(event.id) }
    private func pendingIDs() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in continuation.resume(returning: requests.map(\.identifier)) }
        }
    }
    private func authorize() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { allowed, error in
                if error != nil { continuation.resume(throwing: HarborError(code: "sports-reminder-permission")) }
                else { continuation.resume(returning: allowed) }
            }
        }
    }
    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if error != nil { continuation.resume(throwing: HarborError(code: "sports-reminder-save")) }
                else { continuation.resume(returning: ()) }
            }
        }
    }
}
