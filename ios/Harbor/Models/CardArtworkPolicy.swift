import Foundation

/// Desktop tmdb-image-lang.ts and pickLogo, including stable preference order.
struct CardArtworkPolicy: Sendable {
    let priority: [String?]
    let order: [String?]
    let posterOrder: [String?]
    let localizes: Bool
    init(languages: [String], metadataLanguage: String, originalLanguage: String?) {
        var priority: [String?] = []
        for value in languages {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = trimmed.lowercased() == "original" ? nil : SubtitleLanguages.normalize(trimmed)
            if code != "", !priority.contains(code) { priority.append(code) }
        }
        if priority.isEmpty { priority = ["en", nil] }
        let original = originalLanguage.flatMap { value -> String? in
            let code = SubtitleLanguages.normalize(value); return code.isEmpty ? nil : code
        }
        var order: [String?] = []
        func add(_ code: String?) { if !order.contains(code) { order.append(code) } }
        for code in priority {
            if let code { add(code) } else { if let original { add(original) }; add(nil) }
        }
        if let original { add(original) }; add(nil)
        let metadata = metadataLanguage.split(separator: "-").first?.lowercased() ?? ""
        self.priority = priority; self.order = order
        var posters: [String?] = []
        func addPoster(_ code: String?) { if !posters.contains(code) { posters.append(code) } }
        for code in priority {
            if let code { addPoster(code) } else { if let original { addPoster(original) }; addPoster(nil) }
        }
        if !metadata.isEmpty { addPoster(metadata) }
        addPoster("en"); if let original { addPoster(original) }; addPoster(nil)
        posterOrder = posters
        localizes = priority.first! == nil || priority.compactMap { $0 }.first.map { $0 != "en" } == true || (!metadata.isEmpty && metadata != "en")
    }
    var parameter: String { order.map { $0 ?? "null" }.joined(separator: ",") }
    func poster(_ entries: [JSONValue]) -> String? {
        func rank(_ entry: JSONValue) -> Int {
            let language = entry["iso_639_1"].string.flatMap { $0.isEmpty ? nil : $0 }
            return posterOrder.firstIndex(of: language).map { posterOrder.count - $0 } ?? -1
        }
        let best = entries.reduce(nil as JSONValue?) { best, entry in
            guard let best else { return entry }
            let votes = entry["vote_average"].textValue.flatMap(Double.init) ?? 0
            let previous = best["vote_average"].textValue.flatMap(Double.init) ?? 0
            return rank(entry) > rank(best) || (rank(entry) == rank(best) && votes > previous) ? entry : best
        }
        return Self.tmdbImage(best?["file_path"].string, size: "w500")
    }
    func logo(_ entries: [JSONValue]) -> String? {
        func score(_ entry: JSONValue) -> Double {
            let rank = order.firstIndex(of: entry["iso_639_1"].string).map { order.count - $0 } ?? 0
            let path = entry["file_path"].string ?? ""
            let votes = entry["vote_average"].textValue.flatMap(Double.init) ?? 0
            return Double(rank * 100 + (path.lowercased().hasSuffix(".png") ? 5 : 0)) + votes
        }
        let best = entries.reduce(nil as JSONValue?) { best, entry in
            guard let best else { return entry }; return score(entry) > score(best) ? entry : best
        }
        return Self.tmdbImage(best?["file_path"].string, size: "w500")
    }
    static func tmdbImage(_ path: String?, size: String) -> String? {
        guard let path, path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains(".."),
              path.range(of: #"^/[A-Za-z0-9_./-]+$"#, options: .regularExpression) != nil else { return nil }
        return "https://image.tmdb.org/t/p/" + size + path
    }
    static func image(_ raw: String?) -> String? {
        guard let raw, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return raw
    }
}

/// Original Desktop anime-art search acceptance and ranking, not just the first hit.
enum AnimeCardArtworkMatch {
    static func best(_ results: [JSONValue], name: String, year: String?, kind: String, exact: Bool) -> JSONValue? {
        let year = year.flatMap { $0.isEmpty ? nil : $0 }
        let stops: Set<String> = ["the", "a", "an", "of", "to", "and", "no", "wa", "ga", "wo", "season", "part"]
        func normalized(_ value: String) -> String { value.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression) }
        func tokens(_ value: String) -> Set<String> {
            Set(value.lowercased().replacingOccurrences(of: "[^a-z0-9\\s]+", with: " ", options: .regularExpression)
                .split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count > 1 && !stops.contains($0) })
        }
        var selected: JSONValue?, selectedScore = -Double.infinity
        for hit in results {
            let title = [hit[kind == "movie" ? "title" : "name"].string, hit[kind == "movie" ? "original_title" : "original_name"].string].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            let target = normalized(name), candidate = normalized(title)
            guard !target.isEmpty, !candidate.isEmpty, (hit["id"].integer ?? 0) > 0 else { continue }
            let hitYear = hit[kind == "movie" ? "release_date" : "first_air_date"].string.map { String($0.prefix(4)) }
            let yearMatch = year.flatMap(Int.init).flatMap { year in hitYear.flatMap(Int.init).map { abs(year - $0) <= 1 } } ?? false
            let exactTitle = target == candidate
            if exact {
                guard exactTitle && (year == nil || hitYear?.isEmpty != false || yearMatch) else { continue }
            } else {
                let queryTokens = tokens(name), hitTokens = tokens(title)
                if !queryTokens.subtracting(hitTokens).isEmpty && !yearMatch && !exactTitle { continue }
                guard exactTitle || candidate.contains(target) || target.contains(candidate) || !queryTokens.isDisjoint(with: hitTokens) else { continue }
            }
            let a = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), b = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            var score: Double = a == b ? 60 : b.hasPrefix(a) || a.hasPrefix(b) ? 30 : b.contains(a) ? 18 : 0
            let japanese = kind == "movie" ? hit["original_language"].string == "ja" : (hit["origin_country"].array.first?.string ?? (hit["original_language"].string == "ja" ? "JP" : "")) == "JP"
            if japanese { score += 25 }
            if hit["genre_ids"].array.contains(.integer(16)) { score += 15 }
            if let year, hitYear == year { score += 20 } else if yearMatch { score += 8 }
            score += min(10, log1p(hit["popularity"].textValue.flatMap(Double.init) ?? 0))
            if score > selectedScore { selected = hit; selectedScore = score }
        }
        return selected
    }
}
