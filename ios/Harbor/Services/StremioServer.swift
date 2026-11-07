import Foundation

/// Desktop's remote streaming server (`lib/stremio-server.ts`, `lib/streams/resolve.ts`,
/// `lib/torrent/stremio-stream.ts`). A Stremio server on another machine turns an info hash into an
/// HTTP stream. iPhone and iPad cannot run one, so this is the only way torrent streams play there.
enum StremioServerPolicy {
    /// Desktop's probe (`httpProbe`, `PROBE_TIMEOUT_MS`) waits 1.5 seconds for `/settings`.
    static let probeTimeout: TimeInterval = 1.5
    /// Desktop's `REMOTE_CREATE_TIMEOUT_MS` (resolve.ts) for creating a torrent on the server.
    static let createTimeout: TimeInterval = 15
    /// Desktop's `peerSearch` bounds in `createAndListFiles` (stremio-stream.ts).
    static let peerSearchMin = 40
    static let peerSearchMax = 200

    // MARK: Address

    /// Desktop's `remoteStreamServerUrl()`: trimmed, with trailing slashes removed.
    static func storedAddress(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// Desktop's `normalizeServerUrl` in the settings row: an address without a scheme gets http://.
    static func normalized(_ raw: String) -> String {
        let value = storedAddress(raw)
        guard !value.isEmpty else { return "" }
        if value.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil { return value }
        return "http://" + value
    }

    /// Desktop saves whatever it is given and reports an unusable address as unreachable. This only says
    /// whether the address could work at all: an http or https scheme and a host.
    static func isWellFormed(_ address: String) -> Bool {
        guard let url = URL(string: storedAddress(address)), let scheme = url.scheme?.lowercased() else { return false }
        guard scheme == "http" || scheme == "https" else { return false }
        return !(url.host ?? "").isEmpty
    }

    // MARK: Strict policy

    /// Desktop's `remoteStreamServerStrict()`: strict only counts while an address is saved.
    static func isStrict(address: String, flag: Bool) -> Bool {
        !storedAddress(address).isEmpty && flag
    }

    /// Desktop's `tryLocalEngine` returns nothing while strict, so no local P2P engine starts.
    static func localFallbackAllowed(address: String, flag: Bool) -> Bool {
        !isStrict(address: address, flag: flag)
    }

    /// Desktop's `engineFailureCode` when the saved server cannot be reached.
    static func unreachableFailureCode(strict: Bool) -> String {
        strict ? "remote-server-unreachable-strict" : "remote-server-unreachable"
    }

    /// The base URL that torrent and transcode requests use: the saved server, or nil when none is saved.
    /// Desktop falls back to its bundled engine here, which iOS does not have.
    static func engineBase(address: String) -> String? {
        let value = storedAddress(address)
        return value.isEmpty ? nil : value
    }

    // MARK: Connection state

    /// The status pill of Desktop's `RemoteServerSection`.
    enum Connection: Equatable, Sendable {
        case notSet, checking, connected, unreachable
    }

    static func connection(address: String, reachable: Bool?) -> Connection {
        if storedAddress(address).isEmpty { return .notSet }
        guard let reachable else { return .checking }
        return reachable ? .connected : .unreachable
    }

    // MARK: Stream and transcode URLs

    /// Desktop's `buildTorrentStreamUrl`: `<base>/<infoHash>/<fileIdx>?tr=…&f=…`. A missing or negative
    /// file index is written as -1, and the hash is lowercased.
    static func streamURL(base: String, infoHash: String, fileIdx: Int?, trackers: [String], filename: String?) -> String {
        let index = max(fileIdx ?? -1, -1)
        var pairs: [String] = trackers.map { "tr=" + formEncode($0) }
        if let filename, !filename.isEmpty { pairs.append("f=" + formEncode(filename)) }
        let query = pairs.isEmpty ? "" : "?" + pairs.joined(separator: "&")
        return "\(base)/\(infoHash.lowercased())/\(index)\(query)"
    }

    /// Desktop's `buildTranscodedUrl`: an HLS master playlist on the server with H.264 video and stereo AAC.
    static func transcodeURL(base: String, sourceURL: String, id: String) -> String {
        let parameters: [(String, String)] = [
            ("mediaURL", sourceURL), ("videoCodecs", "h264"), ("audioCodecs", "aac"), ("audioChannels", "2"),
        ]
        let query = parameters.map { $0.0 + "=" + formEncode($0.1) }.joined(separator: "&")
        return "\(base)/hlsv2/\(id)/master.m3u8?\(query)"
    }

    /// A fresh 32-character hex id, as Desktop's `randomId()` makes for each transcode session.
    static func newTranscodeID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// `URLSearchParams` encoding: letters, digits and `*-._` stay, a space becomes `+`, other bytes are escaped.
    static func formEncode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2A, 0x2D, 0x2E, 0x5F:
                out.append(Character(UnicodeScalar(byte)))
            case 0x20:
                out.append("+")
            default:
                let hex = String(byte, radix: 16, uppercase: true)
                out += "%" + (hex.count == 1 ? "0" + hex : hex)
            }
        }
        return out
    }

    /// Desktop's `trackersFromSources`: `tracker:` entries and bare udp, http, https, ws or wss URLs. DHT entries are skipped.
    static func trackers(fromSources sources: [String]) -> [String] {
        var out: [String] = []
        for source in sources {
            if source.hasPrefix("tracker:") {
                out.append(String(source.dropFirst("tracker:".count)))
            } else if source.hasPrefix("dht:") {
                continue
            } else if source.range(of: "^(udp|https?|wss?)://", options: .regularExpression) != nil {
                out.append(source)
            }
        }
        return out
    }

    // MARK: Create and list files

    /// Desktop's `createAndListFiles` body: the hash, a DHT source plus trackers, and an episode guess when both numbers are known.
    static func createBody(infoHash: String, trackers: [String], season: Int?, episode: Int?) -> JSONValue {
        let hash = infoHash.lowercased()
        var guess: [String: JSONValue] = [:]
        if let season, let episode {
            guess["season"] = .integer(Int64(season))
            guess["episode"] = .integer(Int64(episode))
        }
        var sources: [JSONValue] = [.string("dht:" + hash)]
        sources.append(contentsOf: trackers.map { JSONValue.string($0) })
        var peerSearch: [String: JSONValue] = [:]
        peerSearch["sources"] = .array(sources)
        peerSearch["min"] = .integer(Int64(peerSearchMin))
        peerSearch["max"] = .integer(Int64(peerSearchMax))
        var torrent: [String: JSONValue] = [:]
        torrent["infoHash"] = .string(hash)
        var body: [String: JSONValue] = [:]
        body["torrent"] = .object(torrent)
        body["peerSearch"] = .object(peerSearch)
        body["guessFileIdx"] = .object(guess)
        return .object(body)
    }

    struct CreatedFile: Equatable, Sendable {
        let idx: Int
        let name: String
        let length: Int
    }

    struct CreatedTorrent: Equatable, Sendable {
        let files: [CreatedFile]
        let guessedFileIdx: Int?
    }

    /// Desktop's reading of the create response: `files`, or `torrent.files` when nested. Each file takes its
    /// index, name (or the last part of its path) and length or size.
    static func parseCreated(_ json: JSONValue) -> CreatedTorrent? {
        let list: [JSONValue]
        if case .array(let values) = json["files"] {
            list = values
        } else if case .array(let values) = json["torrent"]["files"] {
            list = values
        } else {
            return nil
        }
        var files: [CreatedFile] = []
        for (position, raw) in list.enumerated() {
            let idx = raw["idx"].integer ?? position
            let length = raw["length"].integer ?? raw["size"].integer ?? 0
            files.append(CreatedFile(idx: idx, name: fileName(raw), length: length))
        }
        let guessed = json["guessedFileIdx"].integer.flatMap { $0 >= 0 ? $0 : nil }
        return CreatedTorrent(files: files, guessedFileIdx: guessed)
    }

    private static func fileName(_ raw: JSONValue) -> String {
        if let name = raw["name"].string, !name.isEmpty { return name }
        if let path = raw["path"].string, !path.isEmpty {
            let parts = path.split(omittingEmptySubsequences: false) { $0 == "/" || $0 == "\\" }
            if let last = parts.last, !last.isEmpty { return String(last) }
            return path
        }
        return "Unknown file"
    }

    // MARK: Health

    /// The outcome of Desktop's `probeServer` / `httpProbe`: a 2xx answer from `/settings` counts as reachable.
    enum Health: Equatable, Sendable {
        case reachable(milliseconds: Int)
        case badStatus(Int)
        case unreachable
    }
}

/// One HTTP answer from the streaming server.
struct StremioServerReply: Sendable {
    let status: Int
    let data: Data
}

/// Sends a request to the streaming server. Tests supply canned replies; the app uses `StremioServerHTTPTransport`.
protocol StremioServerTransport: Sendable {
    func send(_ request: URLRequest) async throws -> StremioServerReply
}

struct StremioServerHTTPTransport: StremioServerTransport {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func send(_ request: URLRequest) async throws -> StremioServerReply {
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return StremioServerReply(status: status, data: data)
    }
}

/// Desktop's calls to the streaming server: the health probe (`GET /settings`) and the torrent create call
/// (`POST /<hash>/create`). Failures become nil or `.unreachable`, as on Desktop, and are never thrown.
struct StremioServerClient: Sendable {
    let transport: any StremioServerTransport
    var clock: @Sendable () -> Date = { Date() }

    func health(base: String) async -> StremioServerPolicy.Health {
        guard let url = URL(string: base + "/settings"), isHTTP(url) else { return .unreachable }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: StremioServerPolicy.probeTimeout)
        request.httpMethod = "GET"
        let started = clock()
        guard let reply = try? await transport.send(request) else { return .unreachable }
        guard (200..<300).contains(reply.status) else { return .badStatus(reply.status) }
        let elapsed = clock().timeIntervalSince(started) * 1_000
        return .reachable(milliseconds: max(1, Int(elapsed.rounded())))
    }

    func createTorrent(base: String, infoHash: String, trackers: [String], season: Int? = nil, episode: Int? = nil) async -> StremioServerPolicy.CreatedTorrent? {
        let hash = infoHash.lowercased()
        guard let url = URL(string: "\(base)/\(hash)/create"), isHTTP(url) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: StremioServerPolicy.createTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = StremioServerPolicy.createBody(infoHash: hash, trackers: trackers, season: season, episode: episode)
        guard let encoded = try? JSONEncoder().encode(body) else { return nil }
        request.httpBody = encoded
        guard let reply = try? await transport.send(request), (200..<300).contains(reply.status),
              let json = try? JSONDecoder().decode(JSONValue.self, from: reply.data) else { return nil }
        return StremioServerPolicy.parseCreated(json)
    }

    private func isHTTP(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https"
    }
}
