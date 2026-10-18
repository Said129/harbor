import Foundation
import Observation

struct ProfileDailyWatchRecord: Codable, Equatable, Sendable {
    var version = 1
    var date: String
    var seconds: Int
    var unlocked: Bool
    var valid: Bool {
        guard version == 1, seconds >= 0, seconds <= 172_800,
              date.range(of: "^[0-9]{4,6}-[0-9]{1,2}-[0-9]{1,2}$", options: .regularExpression) != nil else { return false }
        let values = date.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3, values[0] > 0, (1...12).contains(values[1]), (1...31).contains(values[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let value = calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2])) else { return false }
        let parts = calendar.dateComponents([.year, .month, .day], from: value)
        return parts.year == values[0] && parts.month == values[1] && parts.day == values[2]
    }
}
@MainActor protocol ProfileDailyWatchPersistence {
    func read(owner: String) throws -> ProfileDailyWatchRecord?
    func write(_ value: ProfileDailyWatchRecord, owner: String) throws
}
@MainActor private struct KeychainDailyWatchPersistence: ProfileDailyWatchPersistence {
    func read(owner: String) throws -> ProfileDailyWatchRecord? { try KeychainStore().read(key(owner), as: ProfileDailyWatchRecord.self) }
    func write(_ value: ProfileDailyWatchRecord, owner: String) throws { try KeychainStore().write(value, key: key(owner)) }
    private func key(_ owner: String) -> String { "native-daily-watch-" + HouseholdProfileScope.hash([owner]) }
}

/// Desktop's curfew.ts record, scoped to the actual selected person. An open
/// player counts even while paused, matching CurfewGuard. The caller supplies
/// one sample per active second and must keep sampling when video is in PiP.
@MainActor @Observable final class ProfileDailyWatchStore {
    private struct Binding: Equatable {
        let store: ObjectIdentifier
        let household: String
        let profileID: String
        let owner: String
        let minutes: Int
    }
    private let persistence: any ProfileDailyWatchPersistence
    private let credentials: any ProfileCredentialChecking
    private let now: @MainActor () -> Date
    private let calendar: Calendar?
    private var binding: Binding?
    private var record: ProfileDailyWatchRecord?
    private var generation = UUID()
    private(set) var ready = false
    private(set) var busy = false
    private(set) var errorCode: String?
    var required: Bool { binding != nil }
    var elapsedSeconds: Int { record?.seconds ?? 0 }
    var unlockedToday: Bool { ready && record?.date == today && record?.unlocked == true }
    var blocked: Bool {
        guard let binding else { return false }
        guard ready, errorCode == nil, let record, record.date == today else { return true }
        return !record.unlocked && record.seconds >= binding.minutes * 60
    }
    private var today: String {
        var current = calendar ?? Calendar(identifier: .gregorian)
        if calendar == nil { current.timeZone = .current }
        let parts = current.dateComponents([.year, .month, .day], from: now())
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
    init(persistence: (any ProfileDailyWatchPersistence)? = nil,
         credentials: any ProfileCredentialChecking = DeviceProfileCredentialChecker(),
         calendar: Calendar? = nil, now: @escaping @MainActor () -> Date = { Date() }) {
        self.persistence = persistence ?? KeychainDailyWatchPersistence(); self.credentials = credentials
        self.calendar = calendar; self.now = now
    }
    private func scope(_ profiles: HouseholdProfileStore) -> Binding? {
        guard profiles.ready, let active = profiles.active, active.desktop.isKid, let minutes = active.desktop.curfewMinutes else { return nil }
        let routing = HouseholdProfileRouting(profile: active, profiles: profiles.profiles, scope: profiles.scope, cwPerProfile: false)
        return Binding(store: ObjectIdentifier(profiles), household: profiles.scope.key, profileID: active.id, owner: routing.personal, minutes: minutes)
    }
    func invalidate() { generation = UUID(); binding = nil; record = nil; ready = false; busy = false; errorCode = nil }
    func permitsPlayback(profiles: HouseholdProfileStore) -> Bool {
        guard profiles.ready, profiles.active != nil else { return false }
        guard let target = scope(profiles) else { return true }
        return binding == target && ready && !blocked
    }
    func activate(profiles: HouseholdProfileStore) async {
        let target = scope(profiles)
        if target == binding && ready && errorCode == nil && record?.date == today { return }
        invalidate(); binding = target
        guard let target else { ready = true; return }
        let expected = generation
        busy = true
        defer { if generation == expected { busy = false } }
        do {
            let saved = try persistence.read(owner: target.owner)
            try Task.checkCancellation()
            guard generation == expected, scope(profiles) == target else { return }
            guard saved?.valid ?? true else { throw HarborError(code: "daily-watch-record") }
            let value = saved?.date == today ? saved! : ProfileDailyWatchRecord(date: today, seconds: 0, unlocked: false)
            if value != saved { try persistence.write(value, owner: target.owner) }
            try Task.checkCancellation()
            guard generation == expected, scope(profiles) == target else { return }
            record = value; ready = true; errorCode = nil
        } catch is CancellationError { return }
        catch { if generation == expected { ready = false; errorCode = "daily-watch-read" } }
    }
    /// No timer or persistence work is needed for adults or profiles without a
    /// limit. Closed players do not accrue time; detached PiP registrations do.
    func sampleOpenPlayerSecond(profiles: HouseholdProfileStore, playback: ProfilePlaybackRegistry) async {
        guard !busy, ready, let target = binding else { return }
        guard scope(profiles) == target else { invalidate(); playback.stopForProfileChange(); return }
        let expected = generation
        guard var value = record else { return }
        if value.date != today { value = ProfileDailyWatchRecord(date: today, seconds: 0, unlocked: false) }
        if !value.unlocked && value.seconds >= target.minutes * 60 { playback.stopForProfileChange(); return }
        if playback.hasOpenPlayers { value.seconds = min(172_800, value.seconds + 1) }
        guard value != record else { return }
        busy = true
        defer { if generation == expected { busy = false } }
        do {
            try persistence.write(value, owner: target.owner)
            try Task.checkCancellation()
            guard generation == expected, scope(profiles) == target else { return }
            record = value; errorCode = nil
            if blocked { playback.stopForProfileChange() }
        } catch is CancellationError { return }
        catch {
            if generation == expected { ready = false; errorCode = "daily-watch-write"; playback.stopForProfileChange() }
        }
    }
    /// Verify the selected child's actual credential, without granting an
    /// editing/exit unlock. UI code cannot submit a Boolean claiming success.
    func unlockToday(pin: String, profiles: HouseholdProfileStore) async throws -> Bool {
        guard !busy, ready, let target = binding, scope(profiles) == target,
              let active = profiles.active, let credential = active.parentCredential,
              DeviceProfileCredential.validPIN(pin), let previous = record, previous.date == today else { return false }
        let expected = generation, security = profiles.securityVersion, date = today
        busy = true
        defer { if generation == expected { busy = false } }
        guard try await credentials.verifies(pin, credential: credential) else { return false }
        try Task.checkCancellation()
        guard generation == expected, scope(profiles) == target, profiles.securityVersion == security,
              profiles.active == active, today == date, record == previous else { return false }
        var value = previous; value.unlocked = true
        do {
            // Verification and this small privileged commit stay on the same
            // actor: a profile change cannot interleave between the final proof
            // check and granting more time.
            try persistence.write(value, owner: target.owner)
            try Task.checkCancellation()
            guard generation == expected, scope(profiles) == target, profiles.securityVersion == security,
                  profiles.active == active, today == date else { return false }
            record = value; errorCode = nil; return true
        } catch {
            if generation == expected { ready = false; errorCode = "daily-watch-write" }
            throw error
        }
    }
}
