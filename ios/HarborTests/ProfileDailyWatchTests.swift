import XCTest
@testable import Harbor

@MainActor private final class WatchProfileMemory: HouseholdProfilePersistence {
    var value: HouseholdProfileState?
    func readHousehold(_ key: String) throws -> HouseholdProfileState? { value }
    func writeHousehold(_ value: HouseholdProfileState, key: String) throws { self.value = value }
}
@MainActor private final class WatchTimeMemory: ProfileDailyWatchPersistence {
    var values: [String: ProfileDailyWatchRecord] = [:]
    var reads = 0
    var writes = 0
    var failRead = false
    var failWrite = false
    func read(owner: String) throws -> ProfileDailyWatchRecord? { reads += 1; if failRead { throw HarborError(code: "synthetic-watch-read") }; return values[owner] }
    func write(_ value: ProfileDailyWatchRecord, owner: String) throws {
        if failWrite { throw HarborError(code: "synthetic-watch-write") }; values[owner] = value; writes += 1
    }
}
@MainActor private final class WatchClock {
    var date = Date(timeIntervalSince1970: 1_792_324_800)
}
@MainActor private final class WatchController: ProfilePlaybackControlling {
    var closed = 0
    func close() { closed += 1 }
}
private actor HeldWatchCredential: ProfileCredentialChecking {
    private var result: CheckedContinuation<Bool, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func verifies(_ password: String, credential: DeviceProfileCredential) async -> Bool {
        await withCheckedContinuation { result = $0; started?.resume(); started = nil }
    }
    func waitUntilStarted() async { if result == nil { await withCheckedContinuation { started = $0 } } }
    func complete() { result?.resume(returning: true); result = nil }
}

@MainActor final class ProfileDailyWatchTests: XCTestCase {
    private func profiles() throws -> HouseholdProfileStore {
        let value = HouseholdProfileStore(scope: .local(owner: "synthetic-daily-watch"), persistence: WatchProfileMemory())
        _ = try value.create(name: "Primary"); return value
    }
    private func child(_ profiles: HouseholdProfileStore, name: String = "Child") throws -> DeviceHouseholdProfile {
        try profiles.create(name: name, kid: .object(["age": .integer(7), "curfewMinutes": .integer(1)]))
    }
    private func owner(_ row: DeviceHouseholdProfile, _ profiles: HouseholdProfileStore) -> String {
        HouseholdProfileRouting(profile: row, profiles: profiles.profiles, scope: profiles.scope, cwPerProfile: false).personal
    }
    private func store(_ memory: WatchTimeMemory, clock: WatchClock, credentials: any ProfileCredentialChecking = DeviceProfileCredentialChecker()) -> ProfileDailyWatchStore {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return ProfileDailyWatchStore(persistence: memory, credentials: credentials, calendar: calendar, now: { clock.date })
    }
    private func day(_ clock: WatchClock) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let value = calendar.dateComponents([.year, .month, .day], from: clock.date)
        return "\(value.year!)-\(value.month!)-\(value.day!)"
    }
    func testAdultsNeedNoCounterIOAndOnlyOpenPlayerRegistrationsAccrueTime() async throws {
        let profiles = try profiles(), memory = WatchTimeMemory(), clock = WatchClock(), playback = ProfilePlaybackRegistry()
        let budget = store(memory, clock: clock)
        await budget.activate(profiles: profiles)
        XCTAssertTrue(budget.permitsPlayback(profiles: profiles)); XCTAssertEqual(memory.reads, 0); XCTAssertEqual(memory.writes, 0)
        let row = try child(profiles); _ = try await profiles.select(row.id)
        await budget.activate(profiles: profiles)
        let writes = memory.writes
        await budget.sampleOpenPlayerSecond(profiles: profiles, playback: playback)
        XCTAssertEqual(budget.elapsedSeconds, 0); XCTAssertEqual(memory.writes, writes)
        let controller = WatchController(); XCTAssertTrue(playback.register(controller, generation: playback.generation))
        await budget.sampleOpenPlayerSecond(profiles: profiles, playback: playback)
        XCTAssertEqual(budget.elapsedSeconds, 1)
        playback.remove(controller)
        await budget.sampleOpenPlayerSecond(profiles: profiles, playback: playback)
        XCTAssertEqual(budget.elapsedSeconds, 1)
    }
    func testLimitClosesRegisteredVideoAndSurvivesReopeningAndSwitchingPeople() async throws {
        let profiles = try profiles(), memory = WatchTimeMemory(), clock = WatchClock(), playback = ProfilePlaybackRegistry()
        let one = try child(profiles, name: "One"), two = try child(profiles, name: "Two")
        let firstOwner = owner(one, profiles)
        memory.values[firstOwner] = ProfileDailyWatchRecord(date: day(clock), seconds: 59, unlocked: false)
        _ = try await profiles.select(one.id)
        let budget = store(memory, clock: clock); await budget.activate(profiles: profiles)
        let controller = WatchController(); _ = playback.register(controller, generation: playback.generation)
        await budget.sampleOpenPlayerSecond(profiles: profiles, playback: playback)
        XCTAssertTrue(budget.blocked); XCTAssertEqual(controller.closed, 1)
        XCTAssertFalse(budget.permitsPlayback(profiles: profiles)); XCTAssertEqual(memory.values[firstOwner]?.seconds, 60)
        let restart = store(memory, clock: clock); await restart.activate(profiles: profiles)
        XCTAssertTrue(restart.blocked)
        _ = try await profiles.select(two.id); await restart.activate(profiles: profiles)
        XCTAssertEqual(restart.elapsedSeconds, 0); XCTAssertTrue(restart.permitsPlayback(profiles: profiles))
        _ = try await profiles.select(one.id); await restart.activate(profiles: profiles)
        XCTAssertEqual(restart.elapsedSeconds, 60); XCTAssertTrue(restart.blocked)
    }
    func testUnreadableInvalidOrUnwritableCountersCannotEnablePlaybackOrOverwriteFallbacks() async throws {
        let profiles = try profiles(), memory = WatchTimeMemory(), clock = WatchClock(), playback = ProfilePlaybackRegistry()
        let row = try child(profiles); _ = try await profiles.select(row.id)
        let key = owner(row, profiles), budget = store(memory, clock: clock)
        memory.failRead = true; await budget.activate(profiles: profiles)
        XCTAssertFalse(budget.ready); XCTAssertTrue(budget.blocked); XCTAssertFalse(budget.permitsPlayback(profiles: profiles)); XCTAssertEqual(memory.writes, 0)
        memory.failRead = false
        for invalid in [ProfileDailyWatchRecord(date: day(clock), seconds: -1, unlocked: false),
                        ProfileDailyWatchRecord(date: "2026-99-99", seconds: 0, unlocked: false),
                        ProfileDailyWatchRecord(date: "2026-2-30", seconds: 0, unlocked: false)] {
            memory.values[key] = invalid; await budget.activate(profiles: profiles)
            XCTAssertFalse(budget.ready); XCTAssertEqual(memory.writes, 0); XCTAssertEqual(memory.values[key], invalid)
        }
        memory.values[key] = ProfileDailyWatchRecord(date: day(clock), seconds: 59, unlocked: false)
        await budget.activate(profiles: profiles); XCTAssertTrue(budget.ready)
        let controller = WatchController(); _ = playback.register(controller, generation: playback.generation)
        memory.failWrite = true; await budget.sampleOpenPlayerSecond(profiles: profiles, playback: playback)
        XCTAssertFalse(budget.ready); XCTAssertTrue(budget.blocked); XCTAssertEqual(controller.closed, 1)
        XCTAssertEqual(memory.values[key]?.seconds, 59)
    }
    func testARealParentPINAllowsTodayWithoutUnlockingEditingOrExitingTheChild() async throws {
        let profiles = try profiles(), memory = WatchTimeMemory(), clock = WatchClock()
        let adult = try XCTUnwrap(profiles.active), row = try child(profiles)
        try await profiles.setCredential(row.id, password: "4826", parent: true)
        _ = try await profiles.select(row.id)
        let key = owner(row, profiles)
        memory.values[key] = ProfileDailyWatchRecord(date: day(clock), seconds: 60, unlocked: false)
        let budget = store(memory, clock: clock); await budget.activate(profiles: profiles)
        let wrong = try await budget.unlockToday(pin: "4827", profiles: profiles)
        XCTAssertFalse(wrong); XCTAssertTrue(budget.blocked)
        let accepted = try await budget.unlockToday(pin: "4826", profiles: profiles)
        XCTAssertTrue(accepted); XCTAssertTrue(budget.unlockedToday); XCTAssertTrue(budget.permitsPlayback(profiles: profiles))
        XCTAssertThrowsError(try profiles.edit(row.id, fields: ["kid": .null]))
        let exited = try await profiles.select(adult.id)
        XCTAssertFalse(exited, "A daily time override must not grant the parental exit proof")
        let restart = store(memory, clock: clock); await restart.activate(profiles: profiles)
        XCTAssertTrue(restart.unlockedToday)
    }
    func testNewLocalDayResetsTimeAndRevokesYesterdayOverrideEvenWithoutAnOpenPlayer() async throws {
        let profiles = try profiles(), memory = WatchTimeMemory(), clock = WatchClock(), playback = ProfilePlaybackRegistry()
        let row = try child(profiles); _ = try await profiles.select(row.id)
        let key = owner(row, profiles)
        memory.values[key] = ProfileDailyWatchRecord(date: day(clock), seconds: 60, unlocked: true)
        let budget = store(memory, clock: clock); await budget.activate(profiles: profiles)
        XCTAssertTrue(budget.unlockedToday)
        clock.date.addTimeInterval(86_400)
        await budget.sampleOpenPlayerSecond(profiles: profiles, playback: playback)
        XCTAssertEqual(budget.elapsedSeconds, 0); XCTAssertFalse(budget.unlockedToday); XCTAssertFalse(budget.blocked)
        XCTAssertEqual(memory.values[key]?.date, day(clock)); XCTAssertEqual(memory.values[key]?.unlocked, false)
    }
    func testLockingTheSameChildInvalidatesAnInFlightParentOverride() async throws {
        let profiles = try profiles(), memory = WatchTimeMemory(), clock = WatchClock(), held = HeldWatchCredential()
        let row = try child(profiles)
        try await profiles.setCredential(row.id, password: "4826", parent: true); _ = try await profiles.select(row.id)
        let key = owner(row, profiles)
        memory.values[key] = ProfileDailyWatchRecord(date: day(clock), seconds: 60, unlocked: false)
        let budget = store(memory, clock: clock, credentials: held); await budget.activate(profiles: profiles)
        let task = Task { try await budget.unlockToday(pin: "4826", profiles: profiles) }
        await held.waitUntilStarted(); profiles.lockSession(); await held.complete()
        let accepted = try await task.value
        XCTAssertFalse(accepted); XCTAssertTrue(budget.blocked); XCTAssertEqual(memory.values[key]?.unlocked, false)
    }
    func testLocalMidnightStartsANewDayBeforeUTCMidnight() async throws {
        let profiles = try profiles(), memory = WatchTimeMemory(), clock = WatchClock(), playback = ProfilePlaybackRegistry()
        let row = try child(profiles); _ = try await profiles.select(row.id)
        clock.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-18T21:59:59Z"))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 7_200)!
        let key = owner(row, profiles)
        memory.values[key] = ProfileDailyWatchRecord(date: "2026-10-18", seconds: 60, unlocked: true)
        let budget = ProfileDailyWatchStore(persistence: memory, calendar: calendar, now: { clock.date })
        await budget.activate(profiles: profiles); XCTAssertTrue(budget.unlockedToday)
        clock.date.addTimeInterval(2)
        await budget.sampleOpenPlayerSecond(profiles: profiles, playback: playback)
        XCTAssertEqual(memory.values[key]?.date, "2026-10-19")
        XCTAssertEqual(budget.elapsedSeconds, 0); XCTAssertFalse(budget.unlockedToday)
    }
}
