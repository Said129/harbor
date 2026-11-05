import Foundation

struct ParsedMagnet: Equatable, Sendable {
    let infoHash: String
    let name: String?
    let trackers: [String]
}

/// What Search was given: a title to look for, or a link Desktop plays directly
/// (`search-overlay.tsx`: a magnet or info hash, or a direct video URL).
enum SearchInput: Hashable, Sendable {
    case query(String)
    case magnet(String)
    case directURL(String)

    static func classify(_ raw: String) -> SearchInput {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if TorrentLink.isMagnetInput(value) { return .magnet(value) }
        if TorrentLink.isDirectVideoURL(value) { return .directURL(value) }
        return .query(raw)
    }
}

/// Desktop's `lib/torrent/magnet.ts` for what the iPhone needs: recognising and reading magnet links,
/// bare info hashes (40 hex or 32 base32 characters) and direct video URLs.
enum TorrentLink {
    private static func matches(_ pattern: String, _ text: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
    private static let hex40 = "^[a-fA-F0-9]{40}$"
    private static let base32 = "^[a-zA-Z2-7]{32}$"
    private static let videoExtension = "(?i)\\.(mp4|m4v|mkv|webm|mov|avi|ts|m3u8|mpd|flv|wmv|mpg|mpeg|m2ts)(\\?|#|$)"

    static func isMagnetInput(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.lowercased().hasPrefix("magnet:") || matches(hex40, v) || matches(base32, v)
    }

    static func isDirectVideoURL(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matches("(?i)^https?://", v), let url = URL(string: v), url.host?.isEmpty == false else { return false }
        return matches(videoExtension, url.path)
    }

    /// The last path component of a link, decoded, or `fallback`.
    static func fileTitle(_ link: String, fallback: String) -> String {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let last = url.pathComponents.last(where: { $0 != "/" && !$0.isEmpty }) else { return fallback }
        return last
    }

    static func parseMagnet(_ value: String) -> ParsedMagnet? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if matches(hex40, v) { return ParsedMagnet(infoHash: v.lowercased(), name: nil, trackers: []) }
        if matches(base32, v) { return base32ToHex(v).map { ParsedMagnet(infoHash: $0, name: nil, trackers: []) } }
        guard v.lowercased().hasPrefix("magnet:"), let mark = v.firstIndex(of: "?") else { return nil }
        let query = v[v.index(after: mark)...].split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let items = Self.queryItems(query)
        var infoHash: String?
        for (key, raw) in items where key == "xt" {
            guard let range = raw.range(of: "(?i)urn:btih:([a-zA-Z0-9]+)", options: .regularExpression) else { continue }
            let candidate = String(raw[range].dropFirst("urn:btih:".count))
            if matches(hex40, candidate) { infoHash = candidate.lowercased(); break }
            if matches(base32, candidate), let converted = base32ToHex(candidate) { infoHash = converted; break }
        }
        guard let infoHash else { return nil }
        let name = items.first { $0.0 == "dn" }?.1
        return ParsedMagnet(infoHash: infoHash, name: name?.isEmpty == false ? name : nil, trackers: items.filter { $0.0 == "tr" && !$0.1.isEmpty }.map(\.1))
    }

    /// `URLSearchParams` decoding: `+` is a space and percent escapes are decoded.
    private static func queryItems(_ query: Substring) -> [(String, String)] {
        func decode(_ text: Substring) -> String {
            let spaced = text.replacingOccurrences(of: "+", with: " ")
            return spaced.removingPercentEncoding ?? spaced
        }
        return query.split(separator: "&", omittingEmptySubsequences: true).map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (decode(parts[0]), parts.count > 1 ? decode(parts[1]) : "")
        }
    }

    /// 32 base32 characters are 20 bytes, the 40 hex digits of an info hash.
    static func base32ToHex(_ input: String) -> String? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = ""
        for character in input.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "=")) {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            let binary = String(index, radix: 2)
            bits += String(repeating: "0", count: 5 - binary.count) + binary
        }
        var hex = ""
        var start = bits.startIndex
        while bits.distance(from: start, to: bits.endIndex) >= 8 {
            let end = bits.index(start, offsetBy: 8)
            let byte = String(UInt8(bits[start..<end], radix: 2) ?? 0, radix: 16)
            hex += byte.count == 1 ? "0" + byte : byte
            start = end
        }
        return hex.count == 40 ? hex : nil
    }
}
