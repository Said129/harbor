import Foundation
import Observation

/// What the sleep timer waits for (Desktop `lib/sleep-timer-store.ts`).
enum SleepMode: Equatable, Sendable {
    case off
    case minutes(Int)
    case endEpisode
    /// Stops after the episode that follows this one (`remaining` counts the episodes left).
    case endNextEpisode(remaining: Int)
}

/// Desktop's sleep timer (`views/player/hooks/use-sleep-timer.ts` and the speed menu): pause after a
/// number of minutes, at the end of this episode, or at the end of the next one. One timer serves
/// the whole app, so it survives the episode change that "end of next episode" depends on.
@MainActor @Observable
final class SleepTimer {
    static let shared = SleepTimer()

    struct Preset: Identifiable, Equatable, Sendable {
        let id: String
        let mode: SleepMode
        /// Desktop's text for the fixed presets; minutes are labelled from their number.
        let label: String
    }
    /// Desktop's `SLEEP_PRESETS`; its menu shows `curatedIDs` plus the user's own minutes.
    static let presets: [Preset] = [
        .init(id: "15", mode: .minutes(15), label: "15 min"), .init(id: "30", mode: .minutes(30), label: "30 min"),
        .init(id: "45", mode: .minutes(45), label: "45 min"), .init(id: "60", mode: .minutes(60), label: "1 hour"),
        .init(id: "120", mode: .minutes(120), label: "2 hours"), .init(id: "180", mode: .minutes(180), label: "3 hours"),
        .init(id: "240", mode: .minutes(240), label: "4 hours"), .init(id: "360", mode: .minutes(360), label: "6 hours"),
        .init(id: "ep", mode: .endEpisode, label: "End of episode"),
        .init(id: "ep2", mode: .endNextEpisode(remaining: 2), label: "End of next episode"),
    ]
    static let curatedIDs = ["30", "60", "ep", "ep2"]
    static let customKey = "customSleepMinutes"

    private(set) var mode = SleepMode.off
    private(set) var firesAt: Date?
    /// What happens when a minutes timer runs out; the open player sets it.
    @ObservationIgnored var onFire: (@MainActor () -> Void)?
    @ObservationIgnored private var timer: Task<Void, Never>?

    var isActive: Bool { mode != .off }

    func set(_ next: SleepMode) {
        cancel()
        guard next != .off else { return }
        mode = next
        if case .minutes(let total) = next {
            let seconds = Double(total) * 60
            firesAt = Date().addingTimeInterval(seconds)
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.fire()
            }
        }
    }

    func cancel() {
        timer?.cancel(); timer = nil
        mode = .off; firesAt = nil
    }

    func fire() {
        guard case .minutes = mode else { return }
        onFire?()
        cancel()
    }

    func remaining(at date: Date = Date()) -> TimeInterval? {
        guard case .minutes = mode, let firesAt else { return nil }
        return max(0, firesAt.timeIntervalSince(date))
    }

    /// An episode finished by itself. Returns whether playback must stop there; "end of next
    /// episode" counts one episode down and lets the first one continue.
    func episodeEnded() -> Bool {
        switch mode {
        case .endEpisode:
            cancel(); return true
        case .endNextEpisode(let remaining):
            if remaining > 1 { mode = .endNextEpisode(remaining: remaining - 1); return false }
            cancel(); return true
        case .off, .minutes:
            return false
        }
    }

    /// A different video started while "end of episode" was set for the previous one.
    func videoChanged() {
        if mode == .endEpisode { cancel() }
    }

    /// Desktop's chip text next to the speed button: the countdown, or what the timer waits for.
    func badge(at date: Date = Date()) -> String? {
        switch mode {
        case .off: return nil
        case .minutes: return remaining(at: date).map(Self.countdown)
        case .endEpisode: return DesktopInterfaceText.value("End ep")
        case .endNextEpisode(let remaining): return DesktopInterfaceText.value("+{n} ep", variables: ["n": String(remaining)])
        }
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// "30 min", "1 hr", "90 min": Desktop's `sleepMinuteLabel`.
    static func minutesLabel(_ minutes: Int) -> String {
        if minutes >= 60 && minutes % 60 == 0 { return DesktopInterfaceText.value("{n} hr", variables: ["n": String(minutes / 60)]) }
        return DesktopInterfaceText.value("{n} min", variables: ["n": String(minutes)])
    }

    /// Custom minutes the user saved (1...1440, no duplicates, none of the fixed presets).
    static func customMinutes(_ defaults: UserDefaults = .standard) -> [Int] {
        let fixed = Set(presets.compactMap { preset -> Int? in
            if case .minutes(let value) = preset.mode, curatedIDs.contains(preset.id) { return value }
            return nil
        })
        var seen = fixed
        return ((defaults.array(forKey: customKey) as? [Int]) ?? []).filter { (1...1440).contains($0) && seen.insert($0).inserted }.sorted()
    }
    static func addCustom(_ minutes: Int, _ defaults: UserDefaults = .standard) -> Bool {
        guard (1...1440).contains(minutes) else { return false }
        let existing = customMinutes(defaults)
        let fixed = presets.contains { if case .minutes(let value) = $0.mode { return value == minutes && curatedIDs.contains($0.id) }; return false }
        guard !fixed, !existing.contains(minutes) else { return false }
        defaults.set((existing + [minutes]).sorted(), forKey: customKey)
        return true
    }
    static func removeCustom(_ minutes: Int, _ defaults: UserDefaults = .standard) {
        defaults.set(customMinutes(defaults).filter { $0 != minutes }, forKey: customKey)
    }
}
