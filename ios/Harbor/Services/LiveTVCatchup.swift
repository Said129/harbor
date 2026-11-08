import Foundation

/// Desktop's catch-up URL builder (`src/lib/iptv/catchup.ts`). The channel's catch-up type and template come from its
/// attributes: `catchup` or `catchup-type`, plus `catchup-source`. Nothing here plays the URL.
enum LiveTVCatchup {
    enum Kind: Equatable, Sendable { case standard, append, shift, flussonic, xtream }

    /// Desktop's `detectCatchupType`.
    static func kind(for channel: LiveChannel) -> Kind? {
        let raw = (value(channel, "catchup") ?? value(channel, "catchup-type") ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        switch raw {
        case "flussonic", "fs": return .flussonic
        case "xc", "xtream": return .xtream
        case "append": return .append
        case "shift", "timeshift": return .shift
        case "default": return .standard
        default: break
        }
        if value(channel, "catchup-source") != nil { return .standard }
        if xtreamLive(channel.url) != nil { return .xtream }
        return nil
    }

    /// Desktop's `buildCatchupUrl`, with `start` and `end` as the programme window and `now` as the request time.
    static func url(for channel: LiveChannel, start startDate: Date, end endDate: Date, now nowDate: Date = Date()) -> String? {
        guard let detected = Self.kind(for: channel) else { return nil }
        let start = Int(startDate.timeIntervalSince1970.rounded(.down))
        let end = Int(endDate.timeIntervalSince1970.rounded(.down))
        let now = Int(nowDate.timeIntervalSince1970.rounded(.down))
        let duration = max(60, end - start)
        let base = channel.url
        switch detected {
        case .flussonic:
            return flussonicURL(base, start: start, duration: duration)
        case .xtream:
            guard let live = xtreamLive(base) else { return nil }
            let minutes = Int((Double(duration) / 60).rounded(.up))
            let stamp = strftime("Y-m-d:H-M", Date(timeIntervalSince1970: TimeInterval(start)))
            return "\(live.host)/timeshift/\(live.user)/\(live.password)/\(minutes)/\(stamp)/\(live.id).ts"
        case .standard, .append, .shift:
            if let source = value(channel, "catchup-source") {
                if source.range(of: #"^https?://"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    return fillTemplate(source, start: start, end: end, now: now, duration: duration)
                }
                let separator = base.contains("?") ? "&" : "?"
                let joiner = source.hasPrefix("?") || source.hasPrefix("&") ? "" : separator
                let body = source.hasPrefix("?") || source.hasPrefix("&") ? String(source.dropFirst()) : source
                return base + joiner + fillTemplate(body, start: start, end: end, now: now, duration: duration)
            }
            let separator = base.contains("?") ? "&" : "?"
            return "\(base)\(separator)utc=\(start)&lutc=\(now)"
        }
    }

    private static func value(_ channel: LiveChannel, _ key: String) -> String? {
        guard let value = channel.attributes[key], !value.isEmpty else { return nil }
        return value
    }

    /// Desktop's `XTREAM_LIVE_RX`: host, user, password and stream id of an Xtream live link.
    private static func xtreamLive(_ url: String) -> (host: String, user: String, password: String, id: String)? {
        guard let groups = firstGroups(url, pattern: #"^(https?://[^/]+)/(?:live/)?([^/]+)/([^/]+)/(\d+)\.(\w+)(?:\?|$)"#, caseInsensitive: true) else { return nil }
        return (host: groups[1], user: groups[2], password: groups[3], id: groups[4])
    }

    private static func flussonicURL(_ base: String, start: Int, duration: Int) -> String {
        let split = base.firstIndex(of: "?")
        let path = split.map { String(base[..<$0]) } ?? base
        let query = split.map { String(base[$0...]) } ?? ""
        if let groups = firstGroups(path, pattern: #"^(.*)/([^/]+)\.(m3u8|ts|mpd)$"#, caseInsensitive: true) {
            let directory = groups[1], file = groups[2], ext = groups[3]
            let stem = file == "mpegts" || file == "mono" ? "index" : file
            return "\(directory)/\(stem)-\(start)-\(duration).\(ext)\(query)"
        }
        var trimmed = path
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return "\(trimmed)/archive-\(start)-\(duration).ts\(query)"
    }

    /// Desktop's `fillTemplate`: `${start:FORMAT}` and `{utc:FORMAT}` first, then the named values.
    private static func fillTemplate(_ template: String, start: Int, end: Int, now: Int, duration: Int) -> String {
        let startDate = Date(timeIntervalSince1970: TimeInterval(start))
        var output = replacing(template, pattern: #"\$\{(start|utc):([^}]+)\}"#) { strftime($0[2], startDate) }
        output = replacing(output, pattern: #"\{(?:utc|start):([^}]+)\}"#) { strftime($0[1], startDate) }
        let values: [String: String] = [
            "start": String(start), "utc": String(start), "timestamp": String(start),
            "end": String(end), "utcend": String(end),
            "now": String(now), "lutc": String(now), "timenow": String(now),
            "duration": String(duration), "dur": String(duration),
            "offset": String(max(0, now - start)),
            "duration-minutes": String(Int((Double(duration) / 60).rounded(.up))),
        ]
        output = replacing(output, pattern: #"\$\{(\w[\w-]*)\}"#) { values[$0[1].lowercased()] ?? $0[0] }
        output = replacing(output, pattern: #"\{(\w[\w-]*)\}"#) { values[$0[1].lowercased()] ?? $0[0] }
        return output
    }

    /// Desktop's `strftime` for the UTC fields Desktop uses: Y, m, d, H, M and S.
    private static func strftime(_ format: String, _ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        return format
            .replacingOccurrences(of: "Y", with: String(parts.year ?? 0))
            .replacingOccurrences(of: "m", with: pad(parts.month))
            .replacingOccurrences(of: "d", with: pad(parts.day))
            .replacingOccurrences(of: "H", with: pad(parts.hour))
            .replacingOccurrences(of: "M", with: pad(parts.minute))
            .replacingOccurrences(of: "S", with: pad(parts.second))
    }

    /// The groups of the first match (index 0 is the whole match), or nil when the pattern does not match.
    private static func firstGroups(_ text: String, pattern: String, caseInsensitive: Bool) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
        return groups(of: match, in: text)
    }

    /// Replaces every match of `pattern` (case-insensitive) with `transform(groups)`.
    private static func replacing(_ text: String, pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let source = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += transform(groups(of: match, in: text))
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    private static func groups(of match: NSTextCheckingResult, in text: String) -> [String] {
        let source = text as NSString
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : source.substring(with: range)
        }
    }
}
