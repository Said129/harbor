import Foundation

/// One release on a day, whatever its source (Desktop's `CalendarItem` in `lib/calendar.ts`).
struct CalendarItem: Identifiable, Equatable, Sendable {
    let id: String
    var imdbID: String?
    var isMovie: Bool
    /// The line shown in the day list: "Show S01E02: Title", "Show (premiere)" or the movie's name.
    var name: String
    var poster: String?
    var background: String?
    /// The local calendar day, yyyy-MM-dd.
    var releaseDate: String
    var releaseTime: String?
    /// Milliseconds since 1970 when the source knows the hour.
    var releaseAtMs: Double?
    var isAnime: Bool
    var overview: String
    var voteAverage: Double

    /// Desktop's `calendarBaseId`: the title's own id, without the episode or premiere suffix.
    var baseID: String {
        id.replacingOccurrences(of: #":[0-9]+:[0-9]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #":premiere$"#, with: "", options: .regularExpression)
    }
    /// Desktop's `calendarBaseName`.
    var baseName: String {
        name.replacingOccurrences(of: #" S[0-9]{2,}E[0-9]{2,}.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" \(premiere\)$"#, with: "", options: .regularExpression)
    }
    /// Desktop's `calendarEpisodeHint`: the season and episode an id ends with.
    var episodeHint: (season: Int, episode: Int)? {
        guard let found = id.range(of: #":[0-9]+:[0-9]+$"#, options: .regularExpression) else { return nil }
        let numbers = id[found].split(separator: ":").compactMap { Int($0) }
        return numbers.count == 2 ? (numbers[0], numbers[1]) : nil
    }
    /// Where the item opens: Desktop's `calendarToMeta`.
    var media: Media {
        var media = Media(id: baseID, type: isMovie ? "movie" : "series", name: baseName)
        media.poster = poster; media.background = background; media.description = overview.isEmpty ? nil : overview
        media.releaseInfo = String(releaseDate.prefix(4)); media.released = releaseDate; media.imdbID = imdbID
        return media
    }
    var instant: Date? { releaseAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) } }
}

/// Desktop's `lib/calendar-time.ts` and the month helpers of `lib/calendar.ts`.
enum CalendarTime {
    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

    static func dateString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return "" }
        return "\(year)-\(pad(month))-\(pad(day))"
    }

    /// "7:30 PM", as Desktop prints it.
    static func timeLabel(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        return "\(hour % 12 == 0 ? 12 : hour % 12):\(pad(parts.minute ?? 0)) \(hour >= 12 ? "PM" : "AM")"
    }

    static func instant(_ iso: String) -> Date? {
        let precise = ISO8601DateFormatter(); precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: iso) { return date }
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso)
    }

    /// Desktop's `localDateTimeFromIso`: a plain date keeps its day; a timestamp becomes the local day and hour.
    static func parse(_ iso: String?, calendar: Calendar = .current) -> (date: String, time: String?, atMs: Double?) {
        guard let iso, !iso.isEmpty else { return ("", nil, nil) }
        guard iso.contains("T") else { return (String(iso.prefix(10)), nil, nil) }
        guard let date = instant(iso) else { return (String(iso.prefix(10)), nil, nil) }
        return (dateString(date, calendar: calendar), timeLabel(date, calendar: calendar), date.timeIntervalSince1970 * 1_000)
    }

    /// Desktop's `monthRangeISO` for a month numbered 1 to 12.
    static func monthRange(year: Int, month: Int, calendar: Calendar = .current) -> (start: String, end: String)? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let interval = calendar.dateInterval(of: .month, for: first),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return nil }
        return (dateString(first, calendar: calendar), dateString(last, calendar: calendar))
    }

    /// Midnight of a yyyy-MM-dd day.
    static func startOfDay(_ iso: String, calendar: Calendar = .current) -> Date? {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func inMonth(_ iso: String, year: Int, month: Int) -> Bool {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        return parts.count >= 2 && parts[0] == year && parts[1] == month
    }
}
