import Foundation

/// Desktop's anime stream enrichment (`enhanceAnimeStreams` and `parseAnimeFilename` in
/// `src/lib/streams/anitomy.ts`) and its exact-episode pre-filter (`applyAnimeEpisodeFilter` in
/// `pipeline.ts`, `partitionByExactAnimeEpisode` in `anime-identity-core.ts`).
/// Enrichment reads the release filename of a parsed stream and replaces the fields it recognises:
/// title, episode, episode title, season, year, release group, resolution, file checksum and batch.
enum AnimeStreamEnrichment {
    /// What Desktop's `parseAnimeFilename` reads from one filename.
    struct Fields: Equatable, Sendable {
        var animeTitle: String?
        var episodeNumber: Int?
        var episodeTitle: String?
        var season: Int?
        var year: Int?
        var releaseGroup: String?
        var resolution: String?
        var fileChecksum: String?
        var isBatch = false
    }

    /// Desktop's enhanceAnimeStreams for one ParsedStream JSON. Only the fields Desktop writes change.
    static func enriched(_ parsed: JSONValue) -> JSONValue {
        let filename = primaryFilename(parsed)
        guard !filename.isEmpty, case .object(var fields) = parsed else { return parsed }
        let found = parse(filename)
        if let title = found.animeTitle { fields["parsedTitle"] = .string(title) }
        if let episode = found.episodeNumber { fields["episode"] = .integer(Int64(episode)) }
        if let title = found.episodeTitle { fields["episodeTitle"] = .string(title) }
        if let season = found.season { fields["season"] = .integer(Int64(season)) }
        if let year = found.year { fields["year"] = .integer(Int64(year)) }
        if let group = found.releaseGroup, !group.isEmpty {
            fields["releaseGroup"] = .string(group)
            fields["releaseGroupNormalized"] = .string(normalizedGroup(group))
        }
        if let resolution = found.resolution { fields["resolution"] = .string(resolution) }
        if let checksum = found.fileChecksum { fields["animeHash"] = .string(checksum) }
        if found.isBatch { fields["seasonPack"] = .bool(true) }
        return .object(fields)
    }

    /// Key under which a raw stream carries its filename fields to the ranker (`harbor-core` lib.rs `ANIME_FIELDS_KEY`).
    static let fieldsKey = "harborAnimeFields"

    /// Desktop's `animeAbsoluteFromScopedId`: the episode of a `kitsu:ID:EP` or `mal:ID:EP` id, otherwise nil.
    static func absoluteEpisode(_ videoID: String) -> Int? {
        let parts = videoID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "kitsu" || parts[0] == "mal" else { return nil }
        guard isAllDigits(parts[1]), isAllDigits(parts[2]) else { return nil }
        return Int(parts[2])
    }

    /// The fields `parse` finds, as the object the ranker reads. Only recognised fields are written.
    static func fieldsJSON(_ found: Fields) -> JSONValue {
        var out: [String: JSONValue] = ["isBatch": .bool(found.isBatch)]
        if let title = found.animeTitle { out["animeTitle"] = .string(title) }
        if let episode = found.episodeNumber { out["episodeNumber"] = .integer(Int64(episode)) }
        if let title = found.episodeTitle { out["episodeTitle"] = .string(title) }
        if let season = found.season { out["season"] = .integer(Int64(season)) }
        if let year = found.year { out["year"] = .integer(Int64(year)) }
        if let group = found.releaseGroup { out["releaseGroup"] = .string(group) }
        if let resolution = found.resolution { out["resolution"] = .string(resolution) }
        if let checksum = found.fileChecksum { out["fileChecksum"] = .string(checksum) }
        return .object(out)
    }

    /// A raw stream with its filename fields added under `fieldsKey`. Streams without a filename are unchanged.
    static func withFields(_ stream: JSONValue) -> JSONValue {
        guard case .object(var fields) = stream else { return stream }
        let filename = primaryFilename(stream)
        guard !filename.isEmpty else { return stream }
        fields[fieldsKey] = fieldsJSON(parse(filename))
        return .object(fields)
    }

    /// Desktop's `primaryFilename`: the behaviour hint's filename, else a filename line in the
    /// title, description or name, else the title or name.
    static func primaryFilename(_ stream: JSONValue) -> String {
        if let hinted = stream["behaviorHints"]["filename"].string { return hinted }
        if let line = filenameLine(stream) { return line }
        return stream["title"].string ?? stream["name"].string ?? ""
    }

    private static func filenameLine(_ stream: JSONValue) -> String? {
        let blocks = [stream["title"].string, stream["description"].string, stream["name"].string].compactMap { $0 }
        for block in blocks where !block.isEmpty {
            for line in block.components(separatedBy: CharacterSet.newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if matches(#"\.(mkv|mp4|m4v|avi|webm|mov|ts|wmv)\b"#, trimmed, insensitive: true) { return trimmed }
            }
        }
        return nil
    }

    /// Desktop's parseAnimeFilename, step by step in the same order.
    static func parse(_ raw: String) -> Fields {
        var out = Fields()
        var working = raw

        if let ext = groups(#"\.(mkv|mp4|m4v|avi|webm|mov|ts|wmv)$"#, working, insensitive: true) {
            working = String(working.dropLast(ext[0].count))
        }

        if let head = groups(#"^\[([^\]]+)\]\s*"#, working) {
            out.releaseGroup = head[1].trimmingCharacters(in: .whitespacesAndNewlines)
            working = String(working.dropFirst(head[0].count))
        }

        if let hash = groups(#"\[([0-9A-Fa-f]{8})\]"#, working) {
            out.fileChecksum = hash[1].uppercased()
            working = replaceFirst(working, NSRegularExpression.escapedPattern(for: hash[0]), " ")
        }

        if let res = groups(#"\b(2160p|1080p|720p|480p|4k|uhd)\b"#, working, insensitive: true) {
            out.resolution = mapResolution(res[1])
        }

        if let yearMatch = groups(#"(?:^|[^\d])((?:19|20)\d{2})(?:[^\d]|$)"#, working), let year = Int(yearMatch[1]), year >= 1900, year <= 2100 {
            out.year = year
        }

        if let sxe = groups(#"\b[Ss](\d{1,2})[\s._-]?[Ee](\d{1,4})\b"#, working), let season = Int(sxe[1]), let episode = Int(sxe[2]) {
            out.season = season
            out.episodeNumber = episode
        } else if let seasonOnly = groups(#"\b(?:Season|S)[\s._-]?(\d{1,2})\b"#, working, insensitive: true), let season = Int(seasonOnly[1]) {
            out.season = season
        }

        var stripped = replaceAll(working, #"\[[^\]]*\]"#, " ")
        stripped = replaceAll(stripped, #"\([^)]*\)"#, " ")
        stripped = replaceAll(stripped, #"\s+"#, " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if out.episodeNumber == nil {
            if let dash = groups(#"\s-\s(\d{1,4})(?:v\d)?(?:\s|$)"#, stripped), let episode = Int(dash[1]) {
                out.episodeNumber = episode
            } else if let anime = groups(#"(?:^|[\s._-])(?:Ep?(?:isode)?[\s._-]?)?(\d{1,4})(?:v\d)?(?=\s*(?:\[|\(|$|[\s._-]))"#, stripped, insensitive: true), let episode = Int(anime[1]) {
                out.episodeNumber = episode
            }
        }

        if out.releaseGroup == nil, let tail = groups(#"-([A-Za-z0-9_]+)(?:\.[a-z0-9]{2,4})?$"#, working, insensitive: true), !isAllDigits(tail[1]) {
            out.releaseGroup = tail[1]
        }

        if groups(#"\b(?:BATCH|COMPLETE|SEASON\s*PACK)\b"#, working, insensitive: true) != nil {
            out.isBatch = true
        } else if let range = groups(#"\b(\d{1,4})\s*[-~]\s*(\d{1,4})\b"#, stripped), let low = Int(range[1]), let high = Int(range[2]), high - low >= 2, high <= 999 {
            out.isBatch = true
        }

        out.animeTitle = extractTitle(stripped, out)
        out.episodeTitle = extractEpisodeTitle(stripped, out)
        return out
    }

    /// Desktop's applyAnimeEpisodeFilter and partitionByExactAnimeEpisode. Only for anime with a known
    /// absolute episode and trust filtering enabled. A stream with a concrete episode token that is
    /// neither the expected episode nor an alias is dropped. Packs and streams without an episode pass.
    /// `dropped` entries are `{stream, reason}` like the ranker's rejections.
    static func filterExactEpisode(_ parsed: [JSONValue], isAnime: Bool, expected: Int?, aliases: [Int], trustDisabled: Bool) -> (kept: [JSONValue], dropped: [JSONValue]) {
        guard !trustDisabled, isAnime, let expected else { return (parsed, []) }
        var valid: Set<Int> = [expected]
        for alias in aliases where alias >= 1 { valid.insert(alias) }
        var kept: [JSONValue] = [], dropped: [JSONValue] = []
        for stream in parsed {
            if let episode = stream["episode"].integer, stream["seasonPack"] != .bool(true), !valid.contains(episode) {
                dropped.append(.object(["stream": stream, "reason": .string("anime-episode-mismatch:\(episode)-vs-\(expected)")]))
            } else {
                kept.append(stream)
            }
        }
        return (kept, dropped)
    }

    /// Desktop's `normalizedGroup`: upper case, letters and digits only.
    static func normalizedGroup(_ group: String) -> String {
        String(group.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    private static func extractTitle(_ stripped: String, _ fields: Fields) -> String? {
        var text = stripped
        if let episode = fields.episodeNumber, let found = firstRange(#"\s-\s\#(episode)(?:v\d)?(?:\s|$)"#, text), found.location > 0 {
            text = (text as NSString).substring(to: found.location)
        }
        text = replaceFirst(text, #"\b[Ss](\d{1,2})[\s._-]?[Ee](\d{1,4})\b"#, " ")
        text = replaceFirst(text, #"\b(?:Season|S)[\s._-]?(\d{1,2})\b"#, " ", insensitive: true)
        text = replaceFirst(text, #"\b(2160p|1080p|720p|480p|4k|uhd)\b"#, " ", insensitive: true)
        text = replaceFirst(text, #"\.(mkv|mp4|m4v|avi|webm|mov|ts|wmv)$"#, "", insensitive: true)
        text = replaceAll(text, #"[._]+"#, " ")
        text = replaceAll(text, #"\s+"#, " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.utf16.count < 2 { return nil }
        return text
    }

    private static func extractEpisodeTitle(_ stripped: String, _ fields: Fields) -> String? {
        guard let episode = fields.episodeNumber else { return nil }
        let number = String(episode)
        guard let found = firstRange(#"\s-\s\#(number)(?:v\d)?(\s+-\s+)"#, stripped) else { return nil }
        let after = (stripped as NSString).substring(from: found.location)
        guard let match = groups(#"\s-\s\#(number)(?:v\d)?\s+-\s+(.+)"#, after) else { return nil }
        var title = match[1]
        if let split = firstRange(#"\s+\["#, title) { title = (title as NSString).substring(to: split.location) }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.utf16.count < 2 { return nil }
        return title
    }

    private static func mapResolution(_ value: String) -> String {
        let x = value.lowercased()
        if x.hasPrefix("2160") || x == "4k" || x == "uhd" { return "4K" }
        if x.hasPrefix("1080") { return "1080p" }
        if x.hasPrefix("720") { return "720p" }
        if x.hasPrefix("480") { return "480p" }
        return "SD"
    }

    private static func isAllDigits(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }

    private static func matches(_ pattern: String, _ text: String, insensitive: Bool = false) -> Bool {
        text.range(of: pattern, options: insensitive ? [.regularExpression, .caseInsensitive] : [.regularExpression]) != nil
    }

    private static func regex(_ pattern: String, insensitive: Bool) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: insensitive ? [.caseInsensitive] : [])
    }

    /// The whole match followed by each capture group; an unmatched group is empty.
    private static func groups(_ pattern: String, _ text: String, insensitive: Bool = false) -> [String]? {
        guard let regex = regex(pattern, insensitive: insensitive) else { return nil }
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return "" }
            return String(text[swiftRange])
        }
    }

    private static func firstRange(_ pattern: String, _ text: String, insensitive: Bool = false) -> NSRange? {
        guard let regex = regex(pattern, insensitive: insensitive) else { return nil }
        return regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text))?.range
    }

    private static func replaceFirst(_ text: String, _ pattern: String, _ replacement: String, insensitive: Bool = false) -> String {
        guard let regex = regex(pattern, insensitive: insensitive),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let swiftRange = Range(match.range, in: text) else { return text }
        return text.replacingCharacters(in: swiftRange, with: replacement)
    }

    private static func replaceAll(_ text: String, _ pattern: String, _ replacement: String, insensitive: Bool = false) -> String {
        guard let regex = regex(pattern, insensitive: insensitive) else { return text }
        return regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }
}
