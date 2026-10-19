import Foundation

enum TVDBEpisodeOrderKind: String, CaseIterable, Hashable, Sendable {
    case aired, dvd, absolute, tvdbabsolute, alternate, regional

    init?(setting: String) { self.init(rawValue: setting == "official" ? "aired" : setting) }
    var slug: String {
        switch self {
        case .aired, .absolute: return "default"
        case .tvdbabsolute: return "absolute"
        default: return rawValue
        }
    }
    var seasonNameSlug: String { [.aired, .absolute, .tvdbabsolute].contains(self) ? "official" : rawValue }
    var joined: Bool { self == .absolute || self == .tvdbabsolute }
    var label: String {
        switch self {
        case .aired: return "Aired Order"
        case .dvd: return "DVD Order"
        case .absolute: return "Absolute Order"
        case .tvdbabsolute: return "TVDB Absolute Order"
        case .alternate: return "Alternate Order"
        case .regional: return "Regional Order"
        }
    }
}

struct TVDBEpisodeOrderOption: Identifiable, Equatable, Sendable {
    let kind: TVDBEpisodeOrderKind
    let label: String
    var id: String { kind.rawValue }

    static func advertised(in series: JSONValue) -> [Self] {
        var labels: [TVDBEpisodeOrderKind: String] = [:]
        for season in series["seasons"].array {
            guard let slug = season["type"]["type"].string, let kind = TVDBEpisodeOrderKind(setting: slug), labels[kind] == nil else { continue }
            labels[kind] = season["type"]["name"].string.flatMap { $0.isEmpty ? nil : $0 } ?? kind.label
        }
        if labels[.absolute] != nil { labels[.tvdbabsolute] = TVDBEpisodeOrderKind.tvdbabsolute.label }
        return TVDBEpisodeOrderKind.allCases.compactMap { kind in labels[kind].map { Self(kind: kind, label: $0) } }
    }
}

/// Provider rows remain separate from playable episodes. TVDB order coordinates
/// must never replace Stremio video IDs or the coordinates used by watched bits.
struct TVDBOrderEpisode: Sendable {
    let id: Int
    let season: Int
    let number: Int
    let absolute: Int?
    let name: String?
    let overview: String?
    let aired: String?
    let runtime: Int?
    let image: String?

    init?(_ value: JSONValue) {
        guard let id = value["id"].integer, id > 0, let number = value["number"].integer else { return nil }
        self.id = id; self.number = number
        season = value["seasonNumber"].integer ?? 0
        absolute = value["absoluteNumber"].integer
        name = value["name"].string; overview = value["overview"].string
        aired = value["aired"].string; runtime = value["runtime"].integer
        let raw = value["image"].string
        image = TVDBEpisodeMetadata.imageURL(raw.flatMap { $0.isEmpty ? nil : ($0.hasPrefix("http") || $0.hasPrefix("/") ? $0 : "/" + $0) })
    }
}

struct TVDBOrderSlot: Identifiable, Sendable {
    let id: Int
    let canonicalSeason: Int
    let canonicalEpisode: Int
    let alternativeSeason: Int
    let alternativeEpisode: Int
    var season: Int
    var number: Int
    let absolute: Int?
    let name: String
    let overview: String
    let nameEn: String?
    let overviewEn: String?
    let image: String?
    let aired: String?
    let runtime: Int?
}

struct TVDBOrderSeason: Identifiable, Sendable {
    let id: Int
    /// Nil means the interface supplies a localized Season/Specials/All Episodes label.
    let name: String?
    let joined: Bool
    let episodes: [TVDBOrderSlot]
    var count: Int { episodes.count }
    var from: String? { episodes.compactMap(\.aired).filter { !$0.isEmpty }.min() }
    var to: String? { episodes.compactMap(\.aired).filter { !$0.isEmpty }.max() }
}

struct TVDBEpisodeOrder: Sendable {
    let seriesID: Int
    let kind: TVDBEpisodeOrderKind
    let seasons: [TVDBOrderSeason]
    let absoluteByID: [Int: Int]
    let imageByAbsolute: [Int: String]

    static func build(seriesID: Int, kind: TVDBEpisodeOrderKind, canonical: [TVDBOrderEpisode],
                      alternative: [TVDBOrderEpisode], series: JSONValue,
                      translated: [TVDBOrderEpisode] = [], english: [TVDBOrderEpisode] = []) -> Self? {
        guard seriesID > 0, !alternative.isEmpty else { return nil }
        // Like Desktop, later canonical/translation rows replace earlier rows;
        // the ordered list itself uses only the first occurrence of each ID.
        var byID: [Int: TVDBOrderEpisode] = [:], localized: [Int: TVDBOrderEpisode] = [:], en: [Int: TVDBOrderEpisode] = [:]
        for row in canonical where row.season >= 1 { byID[row.id] = row }
        for row in translated { localized[row.id] = row }
        for row in english { en[row.id] = row }
        var buckets: [Int: [TVDBOrderSlot]] = [:], seen = Set<Int>()
        for row in alternative where seen.insert(row.id).inserted {
            let reference = byID[row.id] ?? row
            if kind == .absolute, reference.season < 1 { continue }
            let bucket = kind.joined ? 1 : row.season
            let translation = localized[row.id], fallback = en[row.id]
            buckets[bucket, default: []].append(TVDBOrderSlot(id: row.id,
                canonicalSeason: reference.season, canonicalEpisode: reference.number,
                alternativeSeason: row.season, alternativeEpisode: row.number,
                season: reference.season, number: reference.number, absolute: row.absolute,
                name: firstText(translation?.name, fallback?.name, row.name) ?? "",
                overview: firstText(translation?.overview, fallback?.overview, row.overview) ?? "",
                nameEn: fallback?.name, overviewEn: fallback?.overview, image: row.image, aired: row.aired, runtime: row.runtime))
        }
        guard !buckets.isEmpty else { return nil }
        for key in Array(buckets.keys) {
            guard var rows = buckets[key] else { continue }
            let canonicalPairs = Set(rows.map { "\($0.season):\($0.number)" })
            let alternativePairs = Set(rows.map { "\($0.alternativeSeason):\($0.alternativeEpisode)" })
            if canonicalPairs.count < rows.count, alternativePairs.count == rows.count {
                for index in rows.indices { rows[index].season = rows[index].alternativeSeason; rows[index].number = rows[index].alternativeEpisode }
            }
            if kind == .absolute { rows.sort { $0.season == $1.season ? $0.number < $1.number : $0.season < $1.season } }
            buckets[key] = rows
        }
        let names = seasonNames(in: series, slug: kind.seasonNameSlug)
        let keys = buckets.keys.sorted { lhs, rhs in
            if (lhs > 0) != (rhs > 0) { return lhs > 0 }
            return lhs < rhs
        }
        var absoluteByID: [Int: Int] = [:], imageByAbsolute: [Int: String] = [:]
        for row in alternative {
            if let absolute = row.absolute {
                absoluteByID[row.id] = absolute
                if let image = row.image { imageByAbsolute[absolute] = image }
            }
        }
        return Self(seriesID: seriesID, kind: kind,
            seasons: keys.map { TVDBOrderSeason(id: $0, name: kind.joined ? nil : names[$0], joined: kind.joined, episodes: buckets[$0] ?? []) },
            absoluteByID: absoluteByID, imageByAbsolute: imageByAbsolute)
    }

    static func seasonNames(in series: JSONValue, slug: String) -> [Int: String] {
        var result: [Int: String] = [:]
        for season in series["seasons"].array where season["type"]["type"].string == slug {
            guard let number = season["number"].integer,
                  let name = season["name"].string?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  !name.unicodeScalars.contains(where: { (0x3040...0x30ff).contains($0.value) || (0x3400...0x9fff).contains($0.value) || (0xac00...0xd7af).contains($0.value) }) else { continue }
            result[number] = name
        }
        return result
    }

    static func language(_ iso: String?) -> String {
        let codes = ["en": "eng", "es": "spa", "fr": "fra", "de": "deu", "it": "ita", "ja": "jpn", "ko": "kor", "ru": "rus", "pt": "por", "zh": "zho", "ar": "ara", "nl": "nld", "pl": "pol", "tr": "tur", "sv": "swe", "da": "dan", "fi": "fin", "no": "nor", "cs": "ces", "hu": "hun", "el": "ell", "he": "heb", "th": "tha", "vi": "vie", "id": "ind", "uk": "ukr", "ro": "ron", "hi": "hin"]
        return codes[(iso ?? "").split(separator: "-").first.map { String($0).lowercased() } ?? ""] ?? "eng"
    }

    private static func firstText(_ values: String?...) -> String? { values.compactMap { $0 }.first { !$0.isEmpty } }
}
