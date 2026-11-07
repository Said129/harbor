import Foundation

/// Desktop's "Hide watched titles in catalogs" and "Hide unreleased titles" filters for the built-in catalog rows (`customizable-rows.tsx`).
enum HomeCatalogFilter {
    static func releaseYear(_ text: String?) -> Int? {
        let prefix = String((text ?? "").prefix(4))
        var digits = ""
        for character in prefix {
            guard character.isASCII, character.isNumber else { break }
            digits.append(character)
        }
        return Int(digits)
    }

    static func isUnreleased(_ media: Media, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let released = media.released, let date = releaseDate(released) {
            return date > now
        }
        if let year = releaseYear(media.releaseInfo) {
            return year > calendar.component(.year, from: now)
        }
        return false
    }

    static func titleKey(_ id: String) -> String? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        if id.hasPrefix("tt"), id.count > 2, id.dropFirst(2).allSatisfy({ (character: Character) -> Bool in character >= "0" && character <= "9" }) {
            return "imdb:" + id
        }
        if id.hasPrefix("tmdb:"), parts.count > 2, let number = Int(parts[2]) {
            return "tmdb:\(number)"
        }
        return nil
    }

    static func watchTitleKey(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "" }
        let withoutYears = name.lowercased().replacingOccurrences(of: "\\([0-9]{4}\\)", with: "", options: .regularExpression)
        var result = ""
        for scalar in withoutYears.unicodeScalars where (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    struct Watched: Equatable, Sendable {
        var ids: Set<String> = []
        var keys: Set<String> = []
        var names: Set<String> = []

        init() {}

        init(records: [LibraryRecord]) {
            for record in records where record.watched || record.continuing {
                ids.insert(record.id)
                if let key = HomeCatalogFilter.titleKey(record.id) { keys.insert(key) }
                let name = HomeCatalogFilter.watchTitleKey(record.media?.name)
                if !name.isEmpty { names.insert(name) }
            }
        }

        func contains(_ media: Media) -> Bool {
            if ids.contains(media.id) { return true }
            if let key = HomeCatalogFilter.titleKey(media.id), keys.contains(key) { return true }
            let name = HomeCatalogFilter.watchTitleKey(media.name)
            return !name.isEmpty && names.contains(name)
        }
    }

    static func apply(_ rails: [DiscoveryRail], hideWatched: Bool, hideUnreleased: Bool, watched: Watched, now: Date = Date()) -> [DiscoveryRail] {
        guard hideWatched || hideUnreleased else { return rails }
        var result: [DiscoveryRail] = []
        for rail in rails {
            var filtered = rail
            filtered.metas = rail.metas.filter { (media: Media) -> Bool in
                if hideWatched && watched.contains(media) { return false }
                if hideUnreleased && isUnreleased(media, now: now) { return false }
                return true
            }
            if filtered.metas.isEmpty && rail.personal == nil { continue }
            result.append(filtered)
        }
        return result
    }

    private static func releaseDate(_ text: String) -> Date? {
        let withFraction: ISO8601DateFormatter = { () -> ISO8601DateFormatter in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        if let date = withFraction.date(from: text) { return date }
        let plain: ISO8601DateFormatter = { () -> ISO8601DateFormatter in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()
        if let date = plain.date(from: text) { return date }
        let day: DateFormatter = { () -> DateFormatter in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()
        return day.date(from: String(text.prefix(10)))
    }
}
