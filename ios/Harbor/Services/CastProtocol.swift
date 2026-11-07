import Foundation

/// The network seam for the casting protocols, shaped like `AniListTransport`. Tests supply canned replies; the app uses `CastURLTransport`.
protocol CastTransport: Sendable {
    func send(_ request: URLRequest) async throws -> CastReply
}

struct CastReply: Equatable, Sendable {
    let status: Int
    let body: String
}

struct CastURLTransport: CastTransport {
    func send(_ request: URLRequest) async throws -> CastReply {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return CastReply(status: status, body: String(decoding: data, as: UTF8.self))
    }
}

/// Failures the protocols report by code. The sheet turns them into Desktop's wording (`CastController`).
enum CastProtocolError: Error, Equatable, Sendable {
    case invalidURL
    case transport
    /// Roku ECP answered 401 or 403: network access for mobile control is disabled on the device.
    case rokuBlocked
    /// Roku ECP answered 404 or the device-info document was missing.
    case rokuNotFound
    case rokuHTTP(Int)
    case mediaAssistantMissing
    /// A DLNA SOAP call failed; `upnpCode` is the `errorCode` element when the renderer sent one.
    case soap(action: String, status: Int, upnpCode: String?)
    case noAVTransport
    case unsupported
    /// Chromecast (CASTv2): the device dropped the connection, Desktop's "Device dropped the connection" case.
    case chromecastDropped
    case chromecastUnreachable
    case chromecastRefused
    case chromecastTLS
    /// The receiver answered with an error (LOAD_FAILED, INVALID_REQUEST, no app launched), or a request had no session.
    case chromecastRejected(String)
}

/// A renderer Harbor can cast to. `endpoint` is the Roku ECP base (`http://host:8060/`) or the DLNA AVTransport control URL.
struct CastTarget: Equatable, Identifiable, Sendable {
    let id: String
    let kind: CastProtocolKind
    let name: String
    let model: String?
    let host: String
    let endpoint: String
    /// DLNA only: the RenderingControl URL used for SetVolume.
    var volumeEndpoint: String? = nil
    var vendor: DLNAVendor = .other
    /// Chromecast only: the CASTv2 port that the Bonjour resolve reported.
    var port: UInt16 = CastChromecast.port
}

/// Desktop's `CastDeviceInfo` kinds that iOS can reach. Chromecast is found by Bonjour, Roku by ECP probes, DLNA by a description URL.
enum CastProtocolKind: String, Equatable, Sendable {
    case roku
    case dlna
    case chromecast
}

/// Request builders and string helpers shared by the Roku and DLNA protocols.
enum CastNet {
    static func request(_ url: String, method: String, timeout: TimeInterval, headers: [String: String] = [:], body: String? = nil) -> URLRequest? {
        guard let parsed = URL(string: url) else { return nil }
        var request = URLRequest(url: parsed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body { request.httpBody = Data(body.utf8) }
        return request
    }

    /// The host and port of an http(s) URL as Desktop's `host_from_url` returns them.
    static func hostPort(of url: String) -> String? {
        guard let schemeRange = url.range(of: "://") else { return nil }
        let rest = url[schemeRange.upperBound...]
        let end = rest.firstIndex(of: "/") ?? rest.endIndex
        return String(rest[..<end])
    }

    /// Desktop's `resolve_url` (`dlna.rs`): joins a relative control URL onto the description URL's origin.
    static func resolve(_ base: String, _ relative: String) -> String {
        if relative.hasPrefix("http://") || relative.hasPrefix("https://") { return relative }
        let schemeEnd = base.range(of: "://")?.upperBound ?? base.startIndex
        let pathStart = base[schemeEnd...].firstIndex(of: "/") ?? base.endIndex
        let origin = String(base[..<pathStart])
        return relative.hasPrefix("/") ? origin + relative : origin + "/" + relative
    }

    /// Desktop's `percent_encode` (`roku.rs`): every byte outside the unreserved set becomes `%XX`.
    static func percentEncode(_ text: String) -> String {
        var out = ""
        for byte in text.utf8 {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x5F, 0x2E, 0x7E:
                out.append(Character(Unicode.Scalar(byte)))
            default:
                let hex = String(byte, radix: 16, uppercase: true)
                out += "%" + (hex.count == 1 ? "0" + hex : hex)
            }
        }
        return out
    }

    /// Desktop's `xml_escape` (`dlna.rs`).
    static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Desktop's entity reversal for `CurrentURI` (`dlna.rs`, `current_uri`), in the same order.
    static func xmlUnescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    /// Desktop's `format_hms`: `HH:MM:SS` for REL_TIME, never negative.
    static func formatHMS(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00:00" }
        let total = Int(min(max(seconds, 0), 1_000_000_000))
        return twoDigits(total / 3600) + ":" + twoDigits((total % 3600) / 60) + ":" + twoDigits(total % 60)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    /// Desktop's `parse_hms`: three colon-separated numbers, anything else is zero.
    static func parseHMS(_ text: String) -> Double {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return 0 }
        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0
        let seconds = Double(parts[2]) ?? 0
        return hours * 3600 + minutes * 60 + seconds
    }

    /// Desktop's `parse_ms` (`roku.rs`): `1234`, `1234 ms` or `1234ms`.
    static func parseMilliseconds(_ text: String) -> Double? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(" ms") {
            value.removeLast(3)
        } else if value.hasSuffix("ms") {
            value.removeLast(2)
        }
        guard let number = UInt64(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Double(number)
    }
}

/// Minimal XML reads used by the Roku and DLNA documents: the same first-match rules as Desktop's `extract_tag` and `extract_attr`.
enum CastXML {
    static func tag(_ xml: String, _ name: String) -> String? {
        guard let open = xml.range(of: "<\(name)>") else { return nil }
        guard let close = xml.range(of: "</\(name)>", range: open.upperBound..<xml.endIndex) else { return nil }
        return String(xml[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The value of `attribute` inside the first `<tag ...>` header.
    static func attribute(_ xml: String, tag: String, name: String) -> String? {
        guard let open = xml.range(of: "<\(tag)") else { return nil }
        guard let end = xml.range(of: ">", range: open.upperBound..<xml.endIndex) else { return nil }
        return attributeValue(in: String(xml[open.upperBound..<end.lowerBound]), name: name)
    }

    /// `name="value"` inside a header string, as Desktop's `attr_value`.
    static func attributeValue(in header: String, name: String) -> String? {
        guard let start = header.range(of: "\(name)=\"") else { return nil }
        guard let end = header[start.upperBound...].firstIndex(of: "\"") else { return nil }
        return String(header[start.upperBound..<end])
    }
}
