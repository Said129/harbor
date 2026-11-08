import Foundation

/// Desktop's episode row and random-episode rules: `daysFromTodayLocal`, `airedWithinDays` and `isNewEpisode`
/// (`src/views/detail/helpers.ts`), and `pickRandomEpisode` (`random-episode-button.tsx`). Pure, so the views only call them.
enum EpisodeDetailPolicy {
    /// Desktop's `daysFromTodayLocal`: whole calendar days from today to the `YYYY-MM-DD` prefix of `released`, nil without one.
    static func daysFromToday(_ released: String?, calendar: Calendar = .current, now: Date = Date()) -> Int? {
        guard let released, released.count >= 10 else { return nil }
        let parts = released.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        guard let air = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: air).day
    }

    /// Desktop's `isNewEpisode`: the episode aired within the last three days, today included.
    static func isNew(_ released: String?, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        guard let days = daysFromToday(released, calendar: calendar, now: now) else { return false }
        return days <= 0 && days >= -3
    }

    /// Desktop's `isAired` rule for the season and random pools: no date counts as aired, otherwise the day has come.
    static func isAired(_ released: String?, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        (daysFromToday(released, calendar: calendar, now: now) ?? -1) <= 0
    }

    /// The whole minutes of a positive runtime, for Desktop's `t("{n} min")` line. Nil without a runtime.
    static func runtimeMinutes(_ runtime: Double?) -> Int? {
        guard let runtime, runtime.isFinite, runtime > 0 else { return nil }
        return Int(runtime.rounded())
    }

    /// Desktop's `pickRandomEpisode`: one episode from the numbered seasons, drawn from the aired ones when any have aired.
    /// `roll` returns an index below its argument; the view uses the default random source.
    static func randomEpisode(_ episodes: [Episode], calendar: Calendar = .current, now: Date = Date(),
                              roll: (Int) -> Int = { Int.random(in: 0..<$0) }) -> Episode? {
        let numbered = episodes.filter { ($0.season ?? 0) >= 1 }
        let aired = numbered.filter { isAired($0.released, calendar: calendar, now: now) }
        let pool = aired.isEmpty ? numbered : aired
        guard !pool.isEmpty else { return nil }
        return pool[min(max(roll(pool.count), 0), pool.count - 1)]
    }
}
