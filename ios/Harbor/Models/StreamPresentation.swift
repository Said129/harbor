import Foundation

/// Display the parser's claims without turning them into verified playback facts.
extension StreamOffer {
    var pickerInstance: String {
        raw["addonUrl"].string ?? (addonID ?? source) + "#" + String(raw["addonPriority"].integer ?? 0)
    }
    var pickerFilename: String {
        for value in [raw["behaviorHints"]["filename"].string, raw["behaviorHints"]["fileName"].string] {
            if let value = trimmed(value) { return value }
        }
        return raw["title"].string?.split(separator: "\n").compactMap { trimmed(String($0)) }.first ?? ""
    }
    func pickerTitle(media: Media, episode: Episode?) -> String {
        if let name = trimmed(raw["name"].string) { return name }
        guard let episode else {
            return trimmed(pickerFilename) ?? trimmed(media.name) ?? raw["parsedTitle"].string ?? ""
        }
        let coordinates = String(format: "S%02dE%02d", episode.season ?? 1, episode.episode ?? 0)
        return [media.name, coordinates, episode.name ?? episode.title ?? raw["episodeTitle"].string ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var pickerLanguages: [String] {
        var seen = Set<String>()
        return raw["audioLanguages"].array.compactMap(\.string).map(SubtitleLanguages.normalize)
            .filter { !["", "unknown", "und"].contains($0) && seen.insert($0).inserted }
    }
    var pickerContributor: String {
        let names = raw["contributors"].array.compactMap { $0["name"].string }
        if names.count == 2 { return names.joined(separator: " + ") }
        if let first = names.first, names.count > 2 {
            return DesktopInterfaceText.value("{name} + {n} more").replacingOccurrences(of: "{name}", with: first).replacingOccurrences(of: "{n}", with: String(names.count - 1))
        }
        return source
    }
    var pickerSummary: [String] {
        var parts: [String] = []
        if let size = pickerSize { parts.append(size) }
        let audio = raw["audio"]
        if let codec = audio["codec"].string, codec != "Other" { parts.append(codec) }
        if let channels = audio["channels"].integer, channels >= 6 { parts.append(channels == 8 ? "7.1" : channels == 7 ? "6.1" : "5.1") }
        if let codec = raw["codec"].string, codec != "Other" { parts.append(codec) }
        if let hdr = raw["hdrFormat"].string { parts.append(hdr) }
        if let seeds = raw["seeders"].integer { parts.append(DesktopInterfaceText.value("{n} seeds").replacingOccurrences(of: "{n}", with: String(seeds))) }
        return parts
    }
    var pickerSize: String? {
        let bytes: Double
        switch raw["size"] {
        case .integer(let value): bytes = Double(value)
        case .unsigned(let value): bytes = Double(value)
        case .number(let value): bytes = value
        default: return nil
        }
        guard bytes.isFinite, bytes >= 0 else { return nil }
        if bytes >= 1_073_741_824 { return String(format: "%.2f GB", bytes / 1_073_741_824) }
        if bytes >= 1_048_576 { return String(format: "%.0f MB", bytes / 1_048_576) }
        return String(format: "%.0f B", bytes)
    }
    private var pickerText: String { [raw["name"].string, raw["title"].string, raw["description"].string].compactMap { $0 }.joined(separator: " ") }
    private var pickerUncached: Bool {
        pickerText.range(of: "(?i)\\b(?:rd|ad|pm|dl|tb|oc)\\s*download\\b|\\buncached\\b|[⬇⏳⌛⏬🔽📥☁]", options: .regularExpression) != nil
    }
    var pickerCached: Bool {
        raw["cached"].objectValue.values.contains(.bool(true)) || pickerText.contains("⚡") || pickerText.contains("✅")
    }
    var pickerStatus: String? {
        if automaticallyPlayable && trimmed(raw["infoHash"].string) == nil && !pickerUncached { return "Instant" }
        if pickerCached { return "Cached" }
        return nil
    }
    var pickerExternalURL: URL? {
        guard trimmed(raw["url"].string) == nil, trimmed(raw["infoHash"].string) == nil else { return nil }
        if let value = raw["externalUrl"].string, let url = URLComponents(string: value),
           ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
           url.user == nil, url.password == nil { return url.url }
        if let key = raw["ytId"].string, key.range(of: "^[a-zA-Z0-9_-]{11}$", options: .regularExpression) != nil {
            return URL(string: "https://www.youtube.com/watch?v=" + key)
        }
        return nil
    }
    private var qualityUnlabeled: Bool {
        raw["resolution"].string == "SD" && raw["source"].string == "Other" && raw["codec"].string == "Other" && raw["hdrFormat"] == .null && raw["audio"]["codec"].string == "Other"
    }
    private var qualityUnverified: Bool {
        let signals = raw["reasons"].array.compactMap { $0["signal"].string }
        if signals.contains(where: { $0.hasPrefix("fresh-fake-") || ["fresh-soft-flag", "fresh-prerelease-soft", "fresh-prebluray-suspect", "size-mismatch", "title-says-hires-filename-says-cam"].contains($0) }) { return true }
        return ["4K", "1080p"].contains(raw["resolution"].string ?? "") && raw["size"] == .null && raw["source"].string == "Other" && !(automaticallyPlayable && trimmed(raw["infoHash"].string) == nil)
    }
    private var sourceBadge: String? {
        switch raw["source"].string {
        case "CAM": "cam"
        case "TS", "HDTS": "telesync"
        case "TC": "telecine"
        default: nil
        }
    }
    var pickerLeadBadge: String {
        if let sourceBadge { return sourceBadge }
        if qualityUnlabeled { return "no-label" }
        if qualityUnverified { return "unknown" }
        switch raw["resolution"].string {
        case "4K": return "4k-uhd"
        case "1080p": return "1080p"
        case "720p": return "720p"
        case "480p": return raw["source"].string == "DVDRip" ? "dvd" : "480p"
        default: return raw["source"].string == "DVDRip" ? "dvd" : "sd"
        }
    }
    var pickerLeadLabel: String {
        switch raw["source"].string {
        case "CAM": return "Cam Recording"
        case "TS", "HDTS": return "Telesync"
        case "TC": return "Telecine"
        case "SCR": return "Screener"
        default: break
        }
        if qualityUnlabeled { return "No Label" }
        if qualityUnverified { return "Unverified" }
        switch quality {
        case "4K_DV": return "Ultra HD · Dolby Vision"
        case "4K_HDR": return "Ultra HD · HDR"
        case "4K": return "Ultra HD"
        case "1080p_HDR": return "Full HD · HDR"
        case "1080p": return "Full HD"
        case "720p": return "HD"
        case "ROUGH": return "Theater Capture"
        default: return "Standard Def"
        }
    }
    var pickerTierBadges: [String] {
        var badges = [pickerLeadBadge]
        if sourceBadge == nil, let releaseBadge { badges.append(releaseBadge) }
        if let hdrBadge { badges.append(hdrBadge) }
        return badges
    }
    var pickerBadges: [String] {
        var badges = pickerTierBadges
        if let codec = raw["codec"].string, ["HEVC", "AV1"].contains(codec) { badges.append(codec.lowercased()) }
        let audio = raw["audio"]
        let audioBadges = ["Atmos": "atmos", "TrueHD": "truehd", "DTS-HD MA": "dts-hd", "DTS": "dts", "DD+": "ddp", "FLAC": "flac", "AAC": "aac"]
        if let codec = audio["codec"].string, let badge = audioBadges[codec] { badges.append(badge) }
        else if audio["channels"].integer == 1 { badges.append("mono") }
        if let edition = raw["edition"].string?.uppercased() {
            if edition.contains("IMAX") { badges.append("imax") }
            else if edition.contains("EXTENDED") { badges.append("extended") }
            else if edition.contains("REMASTERED") { badges.append("remastered") }
        }
        if (raw["repackIteration"].integer ?? 0) > 0 { badges.append("repack") }
        return badges
    }
    private var releaseBadge: String? {
        if raw["remux"] == .bool(true) { return "remux" }
        switch raw["source"].string {
        case "BluRay", "BDRip": return "bluray"
        case "WEB-DL", "WEBRip", "HDRip": return "webdl"
        case "HDTV": return "hdtv"
        default: return nil
        }
    }
    private var hdrBadge: String? {
        switch raw["hdrFormat"].string {
        case "DV", "DV+HDR10": "dv"
        case "HDR10+": "hdr10-plus"
        case "HDR10": "hdr10"
        case "HLG": "hlg"
        default: nil
        }
    }
    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
