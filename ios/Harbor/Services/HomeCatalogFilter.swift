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

    /// Desktop's `homeLanguages`: an empty list shows everything, and a title without an original language always stays.
    static func keepsLanguage(_ media: Media, languages: [String]) -> Bool {
        guard !languages.isEmpty, let language = media.originalLanguage, !language.isEmpty else { return true }
        return languages.contains(language)
    }

    /// Desktop's `homeLanguages` on Home rows (`customizable-rows.tsx`). Catalog and discovery rows lose titles outside the list,
    /// and rows left empty are dropped. Discovery rows with a personal source stay, as in `apply`. Lists, sources and Continue Watching are untouched.
    static func homeLanguageRails(_ rails: [PageRail], languages: [String]) -> [PageRail] {
        guard !languages.isEmpty else { return rails }
        var result: [PageRail] = []
        for rail in rails {
            switch rail {
            case .catalog(var row):
                row.metas = row.metas.filter { (media: Media) -> Bool in keepsLanguage(media, languages: languages) }
                if row.metas.isEmpty { continue }
                result.append(.catalog(row))
            case .discovery(var row):
                row.metas = row.metas.filter { (media: Media) -> Bool in keepsLanguage(media, languages: languages) }
                if row.metas.isEmpty && row.personal == nil { continue }
                result.append(.discovery(row))
            default:
                result.append(rail)
            }
        }
        return result
    }

    /// Desktop's `animeOnlyInAnimeRoom`: Home's Continue Watching leaves out anime. The Anime page keeps its own row.
    static func continueWatching(_ records: [LibraryRecord], animeOnlyInAnimeRoom: Bool, detectedAnime: Set<String>) -> [LibraryRecord] {
        guard animeOnlyInAnimeRoom else { return records }
        return records.filter { (record: LibraryRecord) -> Bool in
            !ContinueWatchingSelection.includes(record, kind: "anime", detectedAnime: detectedAnime)
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

    /// Desktop's `homeShowAllAddonRows` on Home (`home-rows.ts` `mergeRows`): an addon row whose name repeats a built-in row
    /// or an earlier addon row is merged away, unless the setting shows every row. `key` is the row's name key.
    static func uniqueAddonRows<Row>(_ rows: [Row], takenKeys: Set<String>, key: (Row) -> String, showAll: Bool) -> [Row] {
        if showAll { return rows }
        var seen = takenKeys
        return rows.filter { (row: Row) -> Bool in seen.insert(key(row)).inserted }
    }

    /// Desktop's `catalogsPinned` / `catalogsHidden` key for one catalog: `<manifest id>-<type>-<catalog id>` (`catalog-browse.ts`).
    static func catalogKey(_ row: CatalogRow) -> String {
        let addonID = row.plan.addon.manifest["id"].string ?? row.plan.addon.id
        let type = row.plan.catalog?.type ?? row.plan.kind
        return addonID + "-" + type + "-" + (row.plan.catalog?.id ?? row.plan.key)
    }

    struct CatalogSections {
        /// Pinned catalogs in pinned order. Hidden does not remove a pinned catalog (`use-catalog-list.ts` `pinnedCats`).
        var pinned: [CatalogRow]
        /// Catalogs that are neither pinned nor hidden, in their original order.
        var rest: [CatalogRow]
    }

    static func catalogSections(_ rows: [CatalogRow], pinned: [String], hidden: [String]) -> CatalogSections {
        var byKey: [String: CatalogRow] = [:]
        for row in rows where byKey[catalogKey(row)] == nil { byKey[catalogKey(row)] = row }
        let pinnedKeys = Set(pinned)
        let hiddenKeys = Set(hidden)
        let pinnedRows = pinned.compactMap { (key: String) -> CatalogRow? in byKey[key] }
        let rest = rows.filter { (row: CatalogRow) -> Bool in
            let key = catalogKey(row)
            return !pinnedKeys.contains(key) && !hiddenKeys.contains(key)
        }
        return CatalogSections(pinned: pinnedRows, rest: rest)
    }

    /// Desktop's `hiddenCount` in `catalogs.tsx`: counts hidden catalogs among all of them, not only the search results.
    static func hiddenCount(_ rows: [CatalogRow], hidden: [String]) -> Int {
        let hiddenKeys = Set(hidden)
        return rows.filter { (row: CatalogRow) -> Bool in hiddenKeys.contains(catalogKey(row)) }.count
    }

    /// Desktop's pin and hide buttons (`catalogs.tsx`): remove the key when present, otherwise append it.
    static func toggled(_ keys: [String], _ key: String) -> [String] {
        keys.contains(key) ? keys.filter { (item: String) -> Bool in item != key } : keys + [key]
    }

    /// Desktop's `movePin`: swap with the neighbour in the given direction, and do nothing past either end.
    static func movingPin(_ keys: [String], _ key: String, by offset: Int) -> [String] {
        guard let index = keys.firstIndex(of: key), keys.indices.contains(index + offset) else { return keys }
        var result = keys
        result.swapAt(index, index + offset)
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
