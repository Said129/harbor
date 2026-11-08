import Foundation

/// Desktop's ad-report rules as pure functions: the release window (`lib/ad-report/window.ts`) and when the report
/// button shows (`views/player/should-show-adreport.ts`). No screen uses them yet.
enum AdReportRules {
    static let windowDays = 150

    /// A release counts as recent when it came out within 150 days. Without a usable date, the year in
    /// `releaseInfo` must be this year or the one before. Future dates count as recent, as in Desktop.
    static func withinAdWindow(releaseDate: String?, releaseInfo: String?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let releaseDate, let released = parseDate(releaseDate) {
            return now.timeIntervalSince(released) <= Double(windowDays) * 86_400
        }
        guard let info = releaseInfo, let range = info.range(of: #"\d{4}"#, options: .regularExpression),
              let year = Int(info[range]) else { return false }
        return year >= calendar.component(.year, from: now) - 1
    }

    /// The ISO forms Harbor's metadata uses: date and time with or without a fraction, or a bare date (UTC).
    static func parseDate(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return day.date(from: value)
    }

    /// Desktop's `shouldShowAdReport`: never on a direct stream, always when asked to, otherwise only on a recent release
    /// with the setting on.
    static func shouldShow(enabled: Bool, alwaysShow: Bool, isDirectStream: Bool, recentRelease: Bool) -> Bool {
        if isDirectStream { return false }
        if alwaysShow { return true }
        if !enabled { return false }
        return recentRelease
    }
}
