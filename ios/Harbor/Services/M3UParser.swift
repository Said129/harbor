import Foundation

enum M3UParser {
    private struct Entry { var title: String; var duration: Double?; var attrs: [String: String] }
    private static let attributePattern = try! NSRegularExpression(pattern: #"([^\s=]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s]+))"#)
    static func parse(_ data: Data, source: String) throws -> [LiveChannel] {
        guard data.count <= LivePlaylistService.maximumBytes, let text = String(data: data, encoding: .utf8) else { throw HarborError(code: "iptv-format") }
        var pending: Entry?, stickyGroup: String?, channels: [LiveChannel] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            try Task.checkCancellation()
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard line.utf8.count <= 64 * 1024, channels.count < 100_000 else { throw HarborError(code: "iptv-size") }
            if line.hasPrefix("#EXTINF:") {
                let rest = String(line.dropFirst(8))
                var quoted = false, comma: String.Index?
                for index in rest.indices { if rest[index] == "\"" { quoted.toggle() } else if rest[index] == ",", !quoted { comma = index; break } }
                let head = comma.map { String(rest[..<$0]) } ?? rest
                let title = comma.map { String(rest[rest.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
                let duration = head.split(whereSeparator: \.isWhitespace).first.flatMap { Double($0) }
                var attrs: [String: String] = [:]
                for match in attributePattern.matches(in: head, range: NSRange(head.startIndex..., in: head)) {
                    guard let keyRange = Range(match.range(at: 1), in: head) else { continue }
                    for part in 2...4 { if let valueRange = Range(match.range(at: part), in: head) { attrs[String(head[keyRange]).lowercased()] = String(head[valueRange]); break } }
                }
                pending = Entry(title: title, duration: duration.flatMap { $0 > 0 ? $0 : nil }, attrs: attrs)
            } else if line.hasPrefix("#EXTGRP:") {
                let group = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                stickyGroup = group.isEmpty ? nil : group; pending?.attrs["group-title"] = group
            } else if line.hasPrefix("#EXTVLCOPT:") {
                if var entry = pending { option(String(line.dropFirst(11)), kind: "vlc", entry: &entry); pending = entry }
            } else if line.hasPrefix("#KODIPROP:") {
                if var entry = pending { option(String(line.dropFirst(10)), kind: "kodi", entry: &entry); pending = entry }
            } else if !line.hasPrefix("#") {
                let pieces = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                let url = String(pieces[0])
                guard let scheme = URL(string: url)?.scheme?.lowercased(), ["http", "https", "rtsp", "rtmp", "udp", "rtp"].contains(scheme) else { pending = nil; continue }
                var entry = pending ?? Entry(title: "Canal \(channels.count + 1)", attrs: [:])
                if pieces.count > 1 { for pair in pieces[1].split(separator: "&") { option(String(pair), kind: "pipe", entry: &entry) } }
                let name = entry.attrs["tvg-name"] ?? (entry.title.isEmpty ? "Canal \(channels.count + 1)" : entry.title)
                if name.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
                    let tvgID = entry.attrs["tvg-id"] ?? entry.attrs["tvg-chno"]
                    let identity = tvgID ?? entry.attrs["tvg-name"] ?? name
                    channels.append(LiveChannel(id: source + "::" + identity + "::\(channels.count)", source: source, tvgID: tvgID, name: name, logo: entry.attrs["tvg-logo"] ?? entry.attrs["logo"], group: entry.attrs["group-title"] ?? entry.attrs["group"] ?? stickyGroup, url: url, catchup: entry.attrs["catchup-source"] ?? entry.attrs["catchup"], duration: entry.duration, attributes: entry.attrs))
                }
                pending = nil
            }
        }
        guard !channels.isEmpty else { throw HarborError(code: "iptv-empty") }
        return channels
    }
    private static func option(_ raw: String, kind: String, entry: inout Entry) {
        guard let equals = raw.firstIndex(of: "=") else { return }
        let key = raw[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
        let encoded = raw[raw.index(after: equals)...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let value = kind == "pipe" ? encoded.removingPercentEncoding ?? encoded : encoded
        guard !value.isEmpty else { return }
        let target: String?
        if kind == "kodi" { target = ["inputstream.adaptive.license_type": "kodiprop-license-type", "inputstream.adaptive.license_key": "kodiprop-license-key"][key] }
        else { target = ["http-user-agent": "vlcopt-user-agent", "user-agent": "vlcopt-user-agent", "http-referrer": "vlcopt-referrer", "http-referer": "vlcopt-referrer", "referer": "vlcopt-referrer", "referrer": "vlcopt-referrer", "cookie": "vlcopt-cookie"][key] }
        if let target, kind != "pipe" || entry.attrs[target] == nil { entry.attrs[target] = value }
    }
}
