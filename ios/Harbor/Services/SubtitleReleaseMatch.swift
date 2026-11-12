import Foundation

/// Desktop's `lib/subtitles/release-match.ts`: what a release name says about a video (source, resolution, group, cut, episode) and how
/// well a subtitle's own release name fits it. Pure text rules, used to rank subtitle candidates against the stream being played.
enum SubtitleReleaseMatch {
    enum SourceClass: String, Sendable {
        case remux, bluray, webdl, webrip, hdtv, dvd, cam
    }

    struct Tags: Equatable, Sendable {
        var group: String? = nil
        var source: SourceClass? = nil
        var resolution: String? = nil
        var hdr: [String] = []
        var edition: [String] = []
        var season: Int? = nil
        var episode: Int? = nil
        var episodeEnd: Int? = nil
        var proper = false
        var repack = false
    }

    struct Affinity: Equatable, Sendable {
        let score: Int
        let reasons: [String]
        /// 3 for the same source family, 2 for a close one, 1 for anything else (Desktop keeps fallbacks usable at rank 1).
        let sourceRank: Int
        let level: SubtitleMatchLevel
    }

    // MARK: Parsing

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let knownGroups: [String] = [
        "EVO", "RARBG", "YTS", "YIFY", "FGT", "PSA", "TBS", "GALAXYRG", "GALAXYTV", "MEGUSTA", "ION10", "EZTV", "NTB", "FLUX",
        "TEPES", "KOGI", "SMURF", "RZEROX", "D3G", "TGX", "SPARKS", "AMIABLE", "GECKOS", "DRONES", "CMRG", "PAHE", "QXR",
        "TIGOLE", "JOY", "FRAMESTOR", "HDMANIACS", "WIKI", "DON", "EBP", "BLURANIUM", "3L", "BMF", "TRUFFLE", "SICFOI", "PMTP",
        "KINGS", "CAKES", "SUCCESSFULCRAB", "ELITE", "TOMMY", "MZABI", "PLAYWEB", "XEBEC", "SEV", "NOSIVID", "TVSMASH", "MINX",
        "EDITH", "TEAMHD"
    ]

    private static let notAGroup: Set<String> = [
        "MKV", "MP4", "AVI", "SRT", "ASS", "SSA", "VTT", "1080P", "720P", "2160P", "X264", "X265", "H264", "H265", "HEVC", "AAC",
        "DTS", "DDP5", "WEB"
    ]

    private static let sourcePatterns: [(SourceClass, NSRegularExpression)] = [
        (.remux, regex(#"\bremux\b"#)),
        (.bluray, regex(#"\b(blu-?ray|bd-?rip|br-?rip|bd(?:25|50)|bdmv)\b"#)),
        (.webrip, regex(#"\bweb-?rip\b"#)),
        (.webdl, regex(#"\b(web-?dl|webdl|web|amzn|dsnp|hmax|atvp|nflx|pcok|itunes)\b"#)),
        (.hdtv, regex(#"\b(hdtv|pdtv|dsr)\b"#)),
        (.dvd, regex(#"\b(dvd-?rip|dvd-?r|dvd5|dvd9)\b"#)),
        (.cam, regex(#"\b(hd-?cam|hd-?ts|telesync|telecine|screener|\bcamrip\b)\b"#))
    ]

    private static let editionPatterns: [(String, NSRegularExpression)] = [
        ("extended", regex(#"\bextended\b"#)),
        ("directors", regex(#"\b(director'?s?[. _-]?cut|dc)\b"#)),
        ("uncut", regex(#"\buncut\b"#)),
        ("unrated", regex(#"\bunrated\b"#)),
        ("theatrical", regex(#"\btheatrical\b"#)),
        ("imax", regex(#"\bimax\b"#)),
        ("criterion", regex(#"\bcriterion\b"#)),
        ("remastered", regex(#"\bremaster(?:ed)?\b"#)),
        ("finalcut", regex(#"\bfinal[. _-]?cut\b"#))
    ]

    private static let hdrPatterns: [(String, NSRegularExpression)] = [
        ("dv", regex(#"\b(dv|dovi|dolby[. _-]?vision)\b"#)),
        ("hdr10plus", regex(#"\b(hdr10\+|hdr10plus)\b"#)),
        ("hdr", regex(#"\bhdr(?!10\+)\b"#)),
        ("hlg", regex(#"\bhlg\b"#)),
        ("sdr", regex(#"\bsdr\b"#))
    ]

    private static let resolutionPattern = regex(#"\b(2160p|1080p|720p|576p|480p)\b"#)
    private static let fourKPattern = regex(#"\b(4k|uhd)\b"#)
    private static let properPattern = regex(#"\bproper\b"#)
    private static let repackPattern = regex(#"\brepack\b"#)
    private static let standardEpisode = regex(#"(?:^|[^a-z0-9])s(\d{1,2})[ ._-]*e(\d{1,3})(?:(?:[ ._-]*-?[ ._-]*e?)(\d{1,3}))?(?:[^a-z0-9]|$)"#)
    private static let alternateEpisode = regex(#"(?:^|[^a-z0-9])(\d{1,2})x(\d{1,3})(?:[ ._-]*-?[ ._-]*(\d{1,3}))?(?:[^a-z0-9]|$)"#)
    private static let trailingGroup = try! NSRegularExpression(pattern: #"[-.]([A-Za-z0-9]{3,20})(?:\.[a-z0-9]{2,4})?\s*$"#)

    private static func found(_ expression: NSRegularExpression, in text: String) -> Bool {
        expression.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    /// Desktop `detectGroup`: a known release group as a whole word, else the last dash or dot word when it is not a format or codec.
    static func detectGroup(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        var tokens = Set<String>()
        var current = ""
        for scalar in text.uppercased().unicodeScalars {
            let value = scalar.value
            if (value >= 48 && value <= 57) || (value >= 65 && value <= 90) {
                current.unicodeScalars.append(scalar)
            } else {
                if !current.isEmpty { tokens.insert(current) }
                current = ""
            }
        }
        if !current.isEmpty { tokens.insert(current) }
        for group in knownGroups where tokens.contains(group) { return group }
        let range = NSRange(text.startIndex..., in: text)
        if let match = trailingGroup.firstMatch(in: text, options: [], range: range), let word = capture(match, 1, in: text) {
            let candidate = word.uppercased()
            if !notAGroup.contains(candidate) { return candidate }
        }
        return nil
    }

    /// Desktop `detectSource`: the first source family whose words appear.
    static func detectSource(_ text: String?) -> SourceClass? {
        guard let text, !text.isEmpty else { return nil }
        for (source, expression) in sourcePatterns where found(expression, in: text) { return source }
        return nil
    }

    /// Desktop `parseEpisodeRange`: `S01E02`, `S01E02-E04` or `1x02`.
    static func parseEpisodeRange(_ text: String) -> (season: Int, episode: Int, episodeEnd: Int)? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = standardEpisode.firstMatch(in: text, options: [], range: range)
                ?? alternateEpisode.firstMatch(in: text, options: [], range: range),
              let seasonText = capture(match, 1, in: text), let season = Int(seasonText),
              let episodeText = capture(match, 2, in: text), let episode = Int(episodeText) else { return nil }
        let end = capture(match, 3, in: text).flatMap { Int($0) } ?? episode
        return (season: season, episode: episode, episodeEnd: max(episode, end))
    }

    /// Desktop `parseRelease`.
    static func parse(_ text: String?) -> Tags {
        let value = text ?? ""
        var tags = Tags()
        tags.group = detectGroup(value)
        tags.source = detectSource(value)
        let range = NSRange(value.startIndex..., in: value)
        if let match = resolutionPattern.firstMatch(in: value, options: [], range: range), let word = capture(match, 1, in: value) {
            tags.resolution = word.lowercased()
        } else if found(fourKPattern, in: value) {
            tags.resolution = "2160p"
        }
        tags.hdr = hdrPatterns.filter { found($0.1, in: value) }.map { $0.0 }
        tags.edition = editionPatterns.filter { found($0.1, in: value) }.map { $0.0 }
        if let episode = parseEpisodeRange(value) {
            tags.season = episode.season
            tags.episode = episode.episode
            tags.episodeEnd = episode.episodeEnd
        }
        tags.proper = found(properPattern, in: value)
        tags.repack = found(repackPattern, in: value)
        return tags
    }

    // MARK: Affinity

    /// Desktop `sourceAffinity`: 1 for the same family, 0.85 remux and Blu-ray, 0.75 WEB-DL and WEB-Rip, 0.25 other web and disc pairs.
    static func sourceAffinity(want: SourceClass?, got: SourceClass?) -> Double {
        guard let want, let got else { return 0 }
        if want == got { return 1 }
        switch (want, got) {
        case (.remux, .bluray), (.bluray, .remux): return 0.85
        case (.remux, .webdl), (.bluray, .webdl), (.webdl, .bluray), (.webdl, .remux): return 0.25
        case (.webdl, .webrip), (.webrip, .webdl): return 0.75
        default: return 0
        }
    }

    private static func sourceRank(want: SourceClass?, got: SourceClass?) -> Int {
        guard want != nil, got != nil else { return 1 }
        let affinity = sourceAffinity(want: want, got: got)
        if affinity >= 1 { return 3 }
        if affinity >= 0.75 { return 2 }
        return 1
    }

    /// Desktop `releaseAffinity(stream, subText)`.
    static func affinity(stream: Tags, subtitleText: String) -> Affinity {
        let sub = parse(subtitleText)
        var reasons: [String] = []
        var score = 0
        let rank = sourceRank(want: stream.source, got: sub.source)
        var incompatible = false
        var episodeMatch = false
        var editionMatch = false

        if let streamSeason = stream.season, let streamEpisode = stream.episode, let subSeason = sub.season, let subEpisode = sub.episode {
            let subEnd = sub.episodeEnd ?? subEpisode
            if streamSeason == subSeason && streamEpisode >= subEpisode && streamEpisode <= subEnd {
                score += 80
                episodeMatch = true
                reasons.append("S\(streamSeason)E\(streamEpisode) matches")
            } else {
                score -= 300
                incompatible = true
                reasons.append("subtitle is for S\(subSeason)E\(subEpisode)")
            }
        }

        if let streamGroup = stream.group, let subGroup = sub.group, streamGroup == subGroup {
            score += 120
            reasons.append("same release group \(subGroup)")
        }

        if let streamSource = stream.source, let subSource = sub.source {
            let value = sourceAffinity(want: streamSource, got: subSource)
            if value >= 1 {
                score += 45
                reasons.append("\(subSource.rawValue) matches the stream")
            } else if value >= 0.75 {
                score += Int((45 * value).rounded())
                reasons.append("\(subSource.rawValue) is close to \(streamSource.rawValue)")
            } else {
                score -= 30
                incompatible = true
                reasons.append("\(subSource.rawValue) timing differs from \(streamSource.rawValue)")
            }
        } else if stream.source != nil && sub.source == nil {
            score += 2
        }

        if let streamResolution = stream.resolution, let subResolution = sub.resolution {
            if streamResolution == subResolution {
                score += 8
                reasons.append(subResolution)
            } else {
                score -= 4
                reasons.append("subtitle is \(subResolution), video is \(streamResolution)")
            }
        }

        if !stream.hdr.isEmpty && !sub.hdr.isEmpty {
            let shared = sub.hdr.filter { stream.hdr.contains($0) }
            if !shared.isEmpty {
                score += 10
                reasons.append(shared.joined(separator: " "))
            }
        }

        let streamEdition = stream.edition.filter { $0 != "remastered" }
        let subEdition = sub.edition.filter { $0 != "remastered" }
        if !streamEdition.isEmpty && !subEdition.isEmpty {
            let shared = subEdition.filter { streamEdition.contains($0) }
            if let first = shared.first {
                score += 25
                editionMatch = true
                reasons.append("\(first) edition")
            } else {
                score -= 25
                incompatible = true
                reasons.append("different edition (\(subEdition[0]))")
            }
        } else if !streamEdition.isEmpty && subEdition.isEmpty {
            score -= 10
        } else if streamEdition.isEmpty && !subEdition.isEmpty {
            score -= 15
            reasons.append("\(subEdition[0]) cut, stream is not")
        }

        if stream.proper == sub.proper && stream.proper {
            score += 6
        } else if sub.proper != stream.proper {
            score -= 3
        }
        if stream.repack == sub.repack && stream.repack { score += 4 }

        let groupMatch = stream.group != nil && sub.group != nil && stream.group == sub.group
        let corroboratedSource = rank == 3 && (episodeMatch || editionMatch)
        let level: SubtitleMatchLevel
        if incompatible {
            level = .incompatible
        } else if groupMatch || corroboratedSource {
            level = .high
        } else if rank >= 2 {
            level = .medium
        } else {
            level = .low
        }
        return Affinity(score: score, reasons: reasons, sourceRank: rank, level: level)
    }
}
