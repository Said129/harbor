import Foundation

struct TraktWatchlistProjection {
    let saved: [LibraryRecord]
    let keys: Set<String>
    static func keys(_ media: Media) -> Set<String> {
        let kind: TraktLibraryTarget.Kind = media.type == "movie" ? .movie : .show
        var result: Set<String> = [kind.rawValue + "|" + media.id]
        if let imdb = TrackerShowIDs(.object(["imdb": media.imdbID.map(JSONValue.string) ?? .null])).json["imdb"].string {
            result.insert(kind.rawValue + "|" + imdb)
        }
        return result
    }
    static func keys(_ item: TraktLibraryItem) -> Set<String> {
        var result = Set<String>()
        if let imdb = item.ids.json["imdb"].string { result.insert(item.type.rawValue + "|" + imdb) }
        if let tmdb = item.ids.json["tmdb"].integer { result.insert(item.type.rawValue + "|tmdb:\(item.type == .movie ? "movie" : "tv"):\(tmdb)") }
        return result
    }
    init(local: [LibraryRecord], remote: [TraktLibraryItem], decisionKey: String, fingerprint: String) {
        var saved: [LibraryRecord] = [], keys = Set<String>(), localByKey: [String: LibraryRecord] = [:], removedAt: [String: Double] = [:]
        for record in local {
            guard let media = record.media else { continue }; let aliases = Self.keys(media)
            for key in aliases where localByKey[key] == nil { localByKey[key] = record }
            let decision = record.raw["nativeTraktWatchlist"][decisionKey]
            if decision["fingerprint"].string == fingerprint, decision["saved"] == .bool(false), let date = decision["at"].numericValue {
                for key in aliases { removedAt[key] = max(removedAt[key] ?? 0, date) }
            }
            if record.bookmarked {
                if keys.isDisjoint(with: aliases) { saved.append(record) }; keys.formUnion(aliases)
            }
        }
        for item in remote {
            let aliases = Self.keys(item); guard !aliases.isEmpty else { continue }
            let date = LibraryRecord.timestamp(item.contextDate) ?? 0
            guard !aliases.contains(where: { (removedAt[$0] ?? -1) >= date }) else { continue }
            if keys.isDisjoint(with: aliases) {
                if let record = aliases.sorted().compactMap({ localByKey[$0] }).first {
                    var fields = record.raw.objectValue; fields["removed"] = .bool(false); fields["temp"] = .bool(false)
                    saved.append(.init(raw: .object(fields)))
                } else if let record = item.record() { saved.append(record) }
            }
            keys.formUnion(aliases)
        }
        self.saved = saved; self.keys = keys
    }
}
