import Foundation

/// Desktop's Roku ECP client (`src-tauri/src/roku.rs`). Pure request builders and parsers; `CastController` sends them.
enum CastRoku {
    static let ecpPort = 8060
    static let channelID = "782875"

    struct DeviceInfo: Equatable, Sendable {
        let name: String
        let model: String?
    }

    struct App: Equatable, Sendable {
        let id: String
        let name: String
    }

    struct MediaStatus: Equatable, Sendable {
        let positionSec: Double
        let durationSec: Double?
        /// Desktop's `player_state`: the raw ECP state, uppercased.
        let playerState: String
        let error: Bool
    }

    /// Keys Desktop presses: pause and resume both send `Play` (a toggle), stop sends `Home`.
    enum Key {
        static let play = "Play"
        static let home = "Home"
    }

    /// The ECP base Desktop keeps, with its trailing slash: `http://host:8060/`.
    static func ecpBase(forHost host: String) -> String {
        "http://\(host):\(ecpPort)/"
    }

    /// A typed address (`192.168.1.20` or `http://192.168.1.20:8060`) as an ECP base. nil when the port is not 8060, the same rule as Desktop's `ecp_url_uses_roku_port`.
    static func normalizedEcpBase(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let url = URL(string: withScheme), let host = url.host, !host.isEmpty else { return nil }
        guard (url.port ?? ecpPort) == ecpPort else { return nil }
        return ecpBase(forHost: host)
    }

    static func deviceInfoRequest(base: String, timeout: TimeInterval = 3) -> URLRequest? {
        CastNet.request(base + "query/device-info", method: "GET", timeout: timeout)
    }

    /// Desktop's `fetch_device_info`: the friendly name, falling back to the user name, then the model name.
    static func parseDeviceInfo(_ xml: String) -> DeviceInfo {
        let model = CastXML.tag(xml, "model-name")
        let name = CastXML.tag(xml, "friendly-device-name")
            ?? CastXML.tag(xml, "user-device-name")
            ?? model
            ?? "Roku"
        return DeviceInfo(name: name, model: model)
    }

    static func queryAppsRequest(base: String, timeout: TimeInterval = 3) -> URLRequest? {
        CastNet.request(base + "query/apps", method: "GET", timeout: timeout)
    }

    static func iconProbeRequest(base: String, channel: String, timeout: TimeInterval = 3) -> URLRequest? {
        CastNet.request(base + "query/icon/" + channel, method: "GET", timeout: timeout)
    }

    /// Desktop's `iter_apps`: each `<app id="...">Name</app>` with a non-empty id and name.
    static func parseApps(_ xml: String) -> [App] {
        var apps: [App] = []
        var rest = Substring(xml)
        while let start = rest.range(of: "<app ") {
            guard let close = rest[start.lowerBound...].firstIndex(of: ">") else { break }
            let header = String(rest[start.lowerBound..<close])
            let after = rest[rest.index(after: close)...]
            guard let end = after.range(of: "</app>") else { break }
            let id = CastXML.attributeValue(in: header, name: "id") ?? ""
            let name = String(after[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty && !name.isEmpty {
                apps.append(App(id: id, name: name))
            }
            rest = after[end.upperBound...]
        }
        return apps
    }

    /// Desktop's channel lookup: a name containing "media assistant", or the channel id 782875.
    static func mediaAssistantChannel(in apps: [App]) -> String? {
        apps.first { $0.name.lowercased().contains("media assistant") || $0.id == channelID }?.id
    }

    /// Desktop's `guess_format`: the Media Assistant format keyword from the content type first, then the URL path.
    static func guessFormat(url: String, contentType: String?) -> String {
        if let contentType {
            let lower = contentType.lowercased()
            if lower.contains("dash+xml") { return "dash" }
            if lower.contains("mpegurl") { return "hls" }
            if lower.contains("matroska") { return "mkv" }
            if lower.contains("video/mp4") || lower.contains("video/quicktime") || lower.contains("m4v") { return "mp4" }
            if lower.contains("vnd.ms-sstr+xml") || lower.contains("smoothstreaming") { return "ism" }
        }
        let lower = url.lowercased()
        let path = lower.components(separatedBy: "?").first ?? lower
        if path.hasSuffix(".m3u8") { return "hls" }
        if path.hasSuffix(".mpd") || path.hasSuffix(".dash") { return "dash" }
        if path.hasSuffix(".mkv") || path.hasSuffix(".mks") { return "mkv" }
        if path.hasSuffix(".m4v") || path.hasSuffix(".mov") { return "mp4" }
        if path.hasSuffix(".ism") || path.contains("/manifest") { return "ism" }
        return "mp4"
    }

    /// Desktop's `launch/<channel>` POST. `startMS` is added only past one second, as Desktop does.
    static func launchRequest(base: String, channel: String, url: String, title: String?, contentType: String?, startSeconds: Double?) -> URLRequest? {
        let format = guessFormat(url: url, contentType: contentType)
        let displayTitle = title ?? "Harbor"
        var launch = base + "launch/" + channel
            + "?u=" + CastNet.percentEncode(url)
            + "&t=v&k=(null)"
            + "&videoName=" + CastNet.percentEncode(displayTitle)
            + "&videoFormat=" + format
            + "&streamformat=" + format
        if let seconds = startSeconds, seconds.isFinite, seconds > 1 {
            launch += "&startMS=\(Int(seconds * 1000))"
        }
        return CastNet.request(launch, method: "POST", timeout: 6, headers: ["Content-Length": "0"], body: "")
    }

    static func mediaPlayerRequest(base: String, timeout: TimeInterval = 3) -> URLRequest? {
        CastNet.request(base + "query/media-player", method: "GET", timeout: timeout)
    }

    /// Desktop's `status`: player state, error flag, position and duration from `query/media-player`.
    static func parseMediaPlayer(_ xml: String) -> MediaStatus {
        let state = CastXML.attribute(xml, tag: "player", name: "state") ?? "unknown"
        let error = CastXML.attribute(xml, tag: "player", name: "error")?.lowercased() == "true"
        let position = CastXML.tag(xml, "position").flatMap(CastNet.parseMilliseconds).map { $0 / 1000 } ?? 0
        let duration = CastXML.tag(xml, "duration").flatMap(CastNet.parseMilliseconds).map { $0 / 1000 }
        return MediaStatus(positionSec: position, durationSec: duration, playerState: state.uppercased(), error: error)
    }

    /// Desktop's `keypress/<key>` POST with an empty body and a 4 s timeout.
    static func keypressRequest(base: String, key: String) -> URLRequest? {
        CastNet.request(base + "keypress/" + key, method: "POST", timeout: 4, body: "")
    }

    /// Desktop's `ecp_error` mapping for a failed `query/apps` response.
    static func error(forStatus status: Int) -> CastProtocolError {
        switch status {
        case 401, 403: return .rokuBlocked
        case 404: return .rokuNotFound
        default: return .rokuHTTP(status)
        }
    }
}
