import Foundation

enum SimklCollection {
    struct Row: Identifiable, Sendable {
        let id: String
        var media: Media
        let items: [SimklListItem]
        let date: String?
    }
    struct Group: Identifiable, Sendable {
        let id: String
        let label: String
        let rows: [Row]
    }
    static func isAnime(_ item: SimklListItem) -> Bool { item.kind == .anime || item.kind == .movie && (item.ids.values["mal"] != nil || item.ids.values["kitsu"] != nil) }
    static func counts(_ snapshot: SimklLibrarySnapshot, kind: SimklMediaKind, relations: [String: Set<String>] = [:]) -> [SimklListStatus: Int] {
        let items = Array(snapshot.items.values)
        let groups = kind == .anime ? franchises(items.filter(isAnime), relations: relations) : items.filter { $0.kind == kind && !isAnime($0) }.map { [$0] }
        var counts: [SimklListStatus: Int] = [:]
        for group in groups { for status in Set(group.map(\.status)) { counts[status, default: 0] += 1 } }
        return counts
    }
    static func normalize(_ title: String) -> String {
        var value = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let patterns = [#"[.°'`:!?,_\-()\[\]{}#]+$"#, #"\s+season\s*\d+$"#, #"\s+s\d+$"#, #"\s+\d+(st|nd|rd|th)\s+season$"#,
            #"\s+(part|cour)\s*\d+$"#, #"\s+(ii|iii|iv|v|vi|vii|viii|ix|x)$"#, #"\s+\d+(st|nd|rd|th)$"#, #"\s+\d{4}$"#,
            #"\s+(final\s+season|the\s+final|final|shippuden|gaiden|side\s+story|r\d?|tv|porori\s+hen|enchousen|hen|season)$"#,
            #"\s*\((tv|movie|ova)\)$"#, #"\s*\[(tv|movie|ova)\]$"#]
        var previous: String
        repeat {
            previous = value
            for pattern in patterns { value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
        } while value != previous
        value = String(value.split(separator: ":", omittingEmptySubsequences: false).first ?? "")
        return value.replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
    static func franchises(_ items: [SimklListItem], relations: [String: Set<String>] = [:]) -> [[SimklListItem]] {
        let sorted = items.sorted { $0.id < $1.id }
        var groups: [[SimklListItem]] = [], keys: [String: Int] = [:]
        for item in sorted {
            let key = normalize(item.title); guard !key.isEmpty else { continue }
            if let index = keys[key] { groups[index].append(item) } else { keys[key] = groups.count; groups.append([item]) }
        }
        var parents = Array(groups.indices)
        func root(_ index: Int) -> Int { var value = index; while parents[value] != value { value = parents[value] }; return value }
        let byID = Dictionary(uniqueKeysWithValues: groups.enumerated().flatMap { index, items in items.map { ($0.id, index) } })
        for (id, related) in relations {
            guard let first = byID[id] else { continue }
            for id in related { if let second = byID[id] { parents[root(first)] = root(second) } }
        }
        var merged: [Int: [SimklListItem]] = [:]
        for index in groups.indices { merged[root(index), default: []].append(contentsOf: groups[index]) }
        return merged.values.map { $0.sorted { ($0.year ?? 9999, $0.id) < ($1.year ?? 9999, $1.id) } }.sorted { ($0.first?.id ?? "") < ($1.first?.id ?? "") }
    }
    static func rows(_ snapshot: SimklLibrarySnapshot, kind: SimklMediaKind, status: SimklListStatus, query: String = "", relations: [String: Set<String>] = [:]) -> [Row] {
        let items = Array(snapshot.items.values)
        let groups: [[SimklListItem]]
        if kind == .anime { groups = franchises(items.filter(isAnime), relations: relations) }
        else { groups = items.filter { $0.kind == kind && !isAnime($0) }.map { [$0] } }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return groups.compactMap { items in
            guard items.contains(where: { $0.status == status }) else { return nil }
            guard let row = Self.row(items, kind: kind), query.isEmpty || row.media.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(query) else { return nil }
            return row
        }
    }
    static func row(_ items: [SimklListItem], kind: SimklMediaKind) -> Row? {
        let watching = items.filter { $0.status == .watching }.sorted { ($0.addedAt ?? "") > ($1.addedAt ?? "") }
        guard let representative = watching.first ?? items.first else { return nil }
        var media = representative.media
        if kind == .anime {
            media.name = items.map(\.title).reduce(nil as String?) { best, value in
                guard let best else { return value }; return value.count < best.count ? value : best
            } ?? media.name
            let years = items.compactMap(\.year)
            if let first = years.min(), let last = years.max() { media.releaseInfo = first == last ? String(first) : "\(first)-\(last)" }
            if media.poster == nil { media.poster = items.compactMap(\.poster).first }
        }
        return Row(id: kind == .anime ? "franchise:" + items.map(\.id).sorted().joined(separator: ",") : representative.id,
            media: media, items: items, date: items.compactMap(\.addedAt).max())
    }
    static func groups(_ rows: [Row], sort: LibrarySort, now: Date = Date(), calendar: Calendar = .current) -> [Group] {
        let rows = rows.sorted {
            if sort == .recent, $0.date != $1.date { return ($0.date ?? "") > ($1.date ?? "") }
            if sort == .year {
                let a = Int(($0.media.releaseInfo ?? "").prefix(4)) ?? 0, b = Int(($1.media.releaseInfo ?? "").prefix(4)) ?? 0
                if a != b { return a > b }
            }
            let comparison = $0.media.name.localizedStandardCompare($1.media.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        if sort != .recent { return [.init(id: sort.rawValue, label: sort == .title ? "A to Z" : "By year", rows: rows)] }
        var buckets: [Int: (String, [Row])] = [:]
        for row in rows {
            let date = row.date.flatMap { ISO8601DateParser.shared.date($0) }
            let days = date.map { now.timeIntervalSince($0) / 86_400 }
            let year = date.map { calendar.component(.year, from: $0) } ?? 0
            let rank = days == nil ? 1000 : days! < 1 ? 0 : days! < 7 ? 1 : days! < 30 ? 2 : 10 + calendar.component(.year, from: now) - year
            let label = days == nil ? "No date" : rank == 0 ? "Today" : rank == 1 ? "This week" : rank == 2 ? "This month" : String(year)
            var values = buckets[rank]?.1 ?? []; values.append(row); buckets[rank] = (label, values)
        }
        return buckets.sorted { $0.key < $1.key }.map { .init(id: String($0.key), label: $0.value.0, rows: $0.value.1) }
    }
}

/// Immutable prepared rows keep title normalization and franchise grouping out
/// of SwiftUI body updates, status taps and individual search keystrokes.
final class SimklCollectionIndex: Sendable {
    private struct Prepared: Sendable {
        let row: SimklCollection.Row
        let statuses: Set<SimklListStatus>
        let searchName: String
    }
    private let prepared: [SimklMediaKind: [Prepared]]
    private let totals: [SimklMediaKind: [SimklListStatus: Int]]
    init(_ snapshot: SimklLibrarySnapshot, relations: [String: Set<String>] = [:]) {
        let items = Array(snapshot.items.values)
        var prepared: [SimklMediaKind: [Prepared]] = [:], totals: [SimklMediaKind: [SimklListStatus: Int]] = [:]
        for kind in SimklMediaKind.allCases {
            let groups = kind == .anime ? SimklCollection.franchises(items.filter(SimklCollection.isAnime), relations: relations)
                : items.filter { $0.kind == kind && !SimklCollection.isAnime($0) }.map { [$0] }
            for group in groups {
                let statuses = Set(group.map(\.status))
                for status in statuses { totals[kind, default: [:]][status, default: 0] += 1 }
                if let row = SimklCollection.row(group, kind: kind) {
                    prepared[kind, default: []].append(.init(row: row, statuses: statuses,
                        searchName: row.media.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)))
                }
            }
        }
        self.prepared = prepared; self.totals = totals
    }
    func counts(kind: SimklMediaKind) -> [SimklListStatus: Int] { totals[kind] ?? [:] }
    func rows(kind: SimklMediaKind, status: SimklListStatus, query: String = "") -> [SimklCollection.Row] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return (prepared[kind] ?? []).compactMap { item in
            item.statuses.contains(status) && (query.isEmpty || item.searchName.contains(query)) ? item.row : nil
        }
    }
}
