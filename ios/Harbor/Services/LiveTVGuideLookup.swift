import Foundation

/// Desktop's guide lookup: `epgProgramsForChannel` and `computeTvgIdCounts` (`src/lib/iptv/epg-resolver.ts`),
/// `findCurrent` (`src/lib/iptv/xmltv.ts`) and the `tvg-shift` rule. The per-channel EPG override and the global
/// EPG offset preference are not ported, because iOS has no stored value for either.
enum LiveTVGuideLookup {
    private static let noiseWords: Set<String> = [
        "hd", "fhd", "uhd", "4k", "sd", "raw", "alt", "backup", "channel", "channels", "network", "tv", "the", "and", "of", "for",
        "us", "usa", "uk", "ca", "mx", "br", "am", "fm",
    ]
    private static let tvgSeparators = try! NSRegularExpression(pattern: #"[._\-:]+"#)
    private static let lowerUpper = try! NSRegularExpression(pattern: #"([a-z])([A-Z])"#)
    private static let upperUpper = try! NSRegularExpression(pattern: #"([A-Z]+)([A-Z][a-z])"#)
    private static let floatPrefix = try! NSRegularExpression(pattern: #"^\s*[+-]?(?:\d+\.?\d*|\.\d+)"#)

    /// Desktop's `computeTvgIdCounts`: how many loaded channels name each tvg id.
    static func tvgIDCounts(_ channels: [LiveChannel]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for channel in channels {
            guard let tvgID = channel.tvgID, !tvgID.isEmpty else { continue }
            counts[tvgID, default: 0] += 1
        }
        return counts
    }

    /// Desktop's `epgProgramsForChannel`: the programmes that belong to a channel, or nil when none match.
    static func programs(for channel: LiveChannel, guide: LiveTVGuide, tvgIDCounts: [String: Int]) -> [LiveProgram]? {
        let shift = shiftHours(channel)
        guard let tvgID = channel.tvgID, !tvgID.isEmpty else { return nameFallback(channel, guide: guide, shift: shift) }
        guard let programs = guide.programs[tvgID], !programs.isEmpty else { return nameFallback(channel, guide: guide, shift: shift) }
        if (tvgIDCounts[tvgID] ?? 0) <= 1 { return applyShift(programs, hours: shift) }
        // Several channels share this tvg id: only keep the guide when the id's words appear in this channel's name.
        let idTokens = tokenize(normalizeTvgID(tvgID))
        guard !idTokens.isEmpty else { return nil }
        let channelTokens = Set(tokenize(channel.name))
        let channelAlnum = nameKey(channel.name)
        for token in idTokens {
            if channelTokens.contains(token) { continue }
            if token.count >= 4, channelAlnum.contains(token) { continue }
            return nil
        }
        return applyShift(programs, hours: shift)
    }

    /// Desktop's `findCurrent`: the programme on air at `date` and the one after it. With nothing on air,
    /// `next` is the first programme that starts later. Programmes must be sorted and non-overlapping.
    static func nowNext(_ programs: [LiveProgram]?, at date: Date) -> (current: LiveProgram?, next: LiveProgram?) {
        guard let programs = programs, !programs.isEmpty else { return (nil, nil) }
        var low = 0, high = programs.count - 1, found = -1
        while low <= high {
            let middle = (low + high) / 2
            let program = programs[middle]
            if date < program.start { high = middle - 1 }
            else if date >= program.end { low = middle + 1 }
            else { found = middle; break }
        }
        if found < 0 { return (nil, low < programs.count ? programs[low] : nil) }
        return (programs[found], found + 1 < programs.count ? programs[found + 1] : nil)
    }

    /// Desktop's `sanitize`: drops empty windows, sorts by start, and keeps the longer of two overlapping programmes.
    static func sanitize(_ programs: [LiveProgram]) -> [LiveProgram] {
        let sorted = programs.filter { $0.end > $0.start }.sorted { first, second in
            if first.start != second.start { return first.start < second.start }
            return first.end > second.end
        }
        var output: [LiveProgram] = []
        for program in sorted {
            guard let last = output.last else { output.append(program); continue }
            if program.start >= last.end { output.append(program); continue }
            if program.end.timeIntervalSince(program.start) > last.end.timeIntervalSince(last.start) { output[output.count - 1] = program }
        }
        return output
    }

    /// Desktop's `nameKey` for names without Arabic: lowercase letters and digits only. Arabic normalisation is not ported.
    static func nameKey(_ value: String) -> String {
        value.lowercased().filter { isASCIIAlphanumeric($0) }
    }

    /// Desktop's `tokenize`: lowercase words of two or more characters (or any number), without the noise words.
    static func tokenize(_ name: String) -> [String] {
        let cleaned = String(name.lowercased().map { isASCIIAlphanumeric($0) ? $0 : " " })
        return cleaned.split(separator: " ").map { String($0) }.filter { word in
            (word.count >= 2 || word.allSatisfy { $0.isNumber }) && !noiseWords.contains(word)
        }
    }

    /// Desktop's `normalizeTvgId`: separators become spaces and camel-case words are split.
    static func normalizeTvgID(_ tvgID: String) -> String {
        var text = replace(tvgSeparators, in: tvgID, with: " ")
        text = replace(lowerUpper, in: text, with: "$1 $2")
        return replace(upperUpper, in: text, with: "$1 $2")
    }

    private static func nameFallback(_ channel: LiveChannel, guide: LiveTVGuide, shift: Double) -> [LiveProgram]? {
        let key = nameKey(channel.name)
        guard key.count >= 3, let tvgID = guide.nameIndex[key], let programs = guide.programs[tvgID], !programs.isEmpty else { return nil }
        return applyShift(programs, hours: shift)
    }

    /// Desktop's `shiftHours` for the channel's own `tvg-shift` attribute, which is read as `parseFloat` does it.
    private static func shiftHours(_ channel: LiveChannel) -> Double {
        guard let raw = channel.attributes["tvg-shift"], !raw.isEmpty else { return 0 }
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = floatPrefix.firstMatch(in: raw, range: range), let matched = Range(match.range, in: raw) else { return 0 }
        let value = Double(raw[matched].trimmingCharacters(in: .whitespaces)) ?? 0
        return value.isFinite ? value : 0
    }

    private static func applyShift(_ programs: [LiveProgram], hours: Double) -> [LiveProgram] {
        guard hours != 0 else { return sanitize(programs) }
        let seconds = hours * 3_600
        return sanitize(programs.map { program in
            LiveProgram(id: program.id, title: program.title, description: program.description,
                        start: program.start.addingTimeInterval(seconds), end: program.end.addingTimeInterval(seconds))
        })
    }

    private static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
