import Foundation

// Desktop Watch Together, pure part (0.9.132): `src/lib/together/protocol.ts`, `room-derive.ts`, `invite.ts`,
// `build-invite.ts`, `source-descriptor.ts`, `source-match.ts`, `seek-coalesce.ts`, `relay-version.ts`, and the
// relay clock estimate in `client.ts`. Nothing here touches the network or the player.
// Cursor, drawing and presence frames are not ported (see the report); unknown frames decode to nil.

enum TogetherProtocol {
    /// `WT_PROTO` (protocol.ts).
    static let version = 2
    /// `REQUIRED_RELAY_VERSION` (relay-version.ts).
    static let requiredRelayVersion = 11
    /// `HARBOR_PUBLIC_RELAY` (relay-version.ts), Desktop's published default relay.
    static let publicRelayURL = "wss://pub.harbor.site"
    /// Web join base of `buildInviteUrl` (`HARBOR_RELAY_BASE` default in config/endpoints.ts).
    static let inviteBaseURL = "https://app.harbor.site"
    /// `ROOM_CODE_ALPHABET` and `ROOM_CODE_LENGTH` (protocol.ts).
    static let roomCodeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let roomCodeLength = 6
    /// `CHAT_HISTORY_LIMIT` (provider-events.ts).
    static let chatHistoryLimit = 200
    /// `AVATAR_MAX_CHARS` (client.ts), in UTF-16 units like JavaScript's `length`.
    static let avatarMaxUnits = 590_000
}

/// Timing constants of `client.ts`, in milliseconds.
enum TogetherTiming {
    static let pingIntervalMs = 25_000.0
    static let livenessTimeoutMs = 40_000.0
    static let reconnectBaseMs = 1_000.0
    static let reconnectMaxMs = 30_000.0
    static let renameAttemptsMax = 8
    static let renameReconnectMs = 60.0
    static let connectTimeoutMs = 10_000.0
    static let failStreakLimit = 4
    static let failStreakAfterJoinMultiplier = 3
    /// `recordPong` ignores round trips longer than this.
    static let rttCeilingMs = 10_000.0
}

enum TogetherClock {
    static func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }
}

extension String {
    /// Trims whitespace and newlines, like JavaScript's `trim()` for the values Watch Together reads.
    var togetherTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - JSON helpers

/// Reads and writes relay frames as dictionaries. Desktop's `JSON.stringify` drops `undefined` keys and keeps `null`,
/// so optional fields use `put` (omitted when nil) and nullable fields use `putNullable` (always present).
enum TogetherJSON {
    static func object(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func text(from object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func string(_ o: [String: Any], _ key: String) -> String? { o[key] as? String }
    static func number(_ o: [String: Any], _ key: String) -> Double? { (o[key] as? NSNumber)?.doubleValue }
    static func int(_ o: [String: Any], _ key: String) -> Int? { (o[key] as? NSNumber)?.intValue }
    static func bool(_ o: [String: Any], _ key: String) -> Bool? { o[key] as? Bool }
    static func object(_ o: [String: Any], _ key: String) -> [String: Any]? { o[key] as? [String: Any] }

    static func array(_ o: [String: Any], _ key: String) -> [[String: Any]] {
        let raw = o[key] as? [Any] ?? []
        var out: [[String: Any]] = []
        for item in raw {
            if let dict = item as? [String: Any] { out.append(dict) }
        }
        return out
    }

    static func put(_ o: inout [String: Any], _ key: String, _ value: Any?) {
        if let value = value { o[key] = value }
    }

    static func putNullable(_ o: inout [String: Any], _ key: String, _ value: String?) {
        if let value = value { o[key] = value } else { o[key] = NSNull() }
    }

    static func nullable(_ value: String?) -> Any {
        if let value = value { return value }
        return NSNull()
    }
}

// MARK: - Room codes

enum TogetherRoomCode {
    /// `normalizeRoomCode`: uppercase, keep A-Z and 0-9 only, at most six characters.
    static func normalize(_ input: String) -> String {
        var out = ""
        for character in input.uppercased() where isRoomCharacter(character) {
            out.append(character)
        }
        return String(out.prefix(TogetherProtocol.roomCodeLength))
    }

    /// `generateRoomCode`, with an injectable generator so tests can pin the output.
    static func generate<G: RandomNumberGenerator>(using generator: inout G) -> String {
        let alphabet = TogetherProtocol.roomCodeAlphabet
        var out = ""
        for _ in 0..<TogetherProtocol.roomCodeLength {
            let index = Int.random(in: 0..<alphabet.count, using: &generator)
            out.append(alphabet[index])
        }
        return out
    }

    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    private static func isRoomCharacter(_ character: Character) -> Bool {
        (character >= "A" && character <= "Z") || (character >= "0" && character <= "9")
    }
}

// MARK: - Shared records

struct TogetherParticipant: Equatable, Sendable {
    var id: String
    var name: String
    var joinedAt: Double
    var ready: Bool
    var avatar: String?
    var color: String?
}

extension TogetherParticipant {
    init?(json o: [String: Any]) {
        guard let id = TogetherJSON.string(o, "id"), let name = TogetherJSON.string(o, "name") else { return nil }
        self.init(id: id, name: name, joinedAt: TogetherJSON.number(o, "joinedAt") ?? 0,
                  ready: TogetherJSON.bool(o, "ready") ?? false, avatar: TogetherJSON.string(o, "avatar"),
                  color: TogetherJSON.string(o, "color"))
    }
}

struct TogetherEpisodeRef: Equatable, Sendable {
    var season: Int
    var episode: Int
    var name: String?
    var kitsuStreamId: String?
    var imdbId: String?
    var imdbSeason: Int?
    var imdbEpisode: Int?
    var absoluteNumber: Int?
    var tvdbEpisodeId: Int?
}

extension TogetherEpisodeRef {
    init?(json o: [String: Any]) {
        guard let season = TogetherJSON.int(o, "season"), let episode = TogetherJSON.int(o, "episode") else { return nil }
        self.init(season: season, episode: episode, name: TogetherJSON.string(o, "name"),
                  kitsuStreamId: TogetherJSON.string(o, "kitsuStreamId"), imdbId: TogetherJSON.string(o, "imdbId"),
                  imdbSeason: TogetherJSON.int(o, "imdbSeason"), imdbEpisode: TogetherJSON.int(o, "imdbEpisode"),
                  absoluteNumber: TogetherJSON.int(o, "absoluteNumber"), tvdbEpisodeId: TogetherJSON.int(o, "tvdbEpisodeId"))
    }

    var json: [String: Any] {
        var o: [String: Any] = ["season": season, "episode": episode]
        TogetherJSON.put(&o, "name", name)
        TogetherJSON.put(&o, "kitsuStreamId", kitsuStreamId)
        TogetherJSON.put(&o, "imdbId", imdbId)
        TogetherJSON.put(&o, "imdbSeason", imdbSeason)
        TogetherJSON.put(&o, "imdbEpisode", imdbEpisode)
        TogetherJSON.put(&o, "absoluteNumber", absoluteNumber)
        TogetherJSON.put(&o, "tvdbEpisodeId", tvdbEpisodeId)
        return o
    }
}

struct TogetherSourceDescriptor: Equatable, Sendable {
    var title: String?
    var resolution: String?
    var sizeBytes: Int?
    var infoHash: String?
    var fileIdx: Int?
    var durationSec: Double?

    var isEmpty: Bool {
        title == nil && resolution == nil && sizeBytes == nil && infoHash == nil && fileIdx == nil && durationSec == nil
    }

    /// `normalizeResolution` (source-descriptor.ts): lowercase, 4K and UHD map to 2160p, at most 16 characters.
    static func normalizeResolution(_ value: String?) -> String? {
        guard let raw = value else { return nil }
        let text = raw.togetherTrimmed.lowercased()
        if text.isEmpty { return nil }
        if text == "4k" || text == "2160p" || text == "uhd" { return "2160p" }
        return String(text.prefix(16))
    }

    var json: [String: Any] {
        var o: [String: Any] = [:]
        TogetherJSON.put(&o, "title", title)
        TogetherJSON.put(&o, "resolution", resolution)
        TogetherJSON.put(&o, "sizeBytes", sizeBytes)
        TogetherJSON.put(&o, "infoHash", infoHash)
        TogetherJSON.put(&o, "fileIdx", fileIdx)
        TogetherJSON.put(&o, "durationSec", durationSec)
        return o
    }
}

extension TogetherSourceDescriptor {
    init(json o: [String: Any]) {
        self.init(title: TogetherJSON.string(o, "title"), resolution: TogetherJSON.string(o, "resolution"),
                  sizeBytes: TogetherJSON.int(o, "sizeBytes"), infoHash: TogetherJSON.string(o, "infoHash"),
                  fileIdx: TogetherJSON.int(o, "fileIdx"), durationSec: TogetherJSON.number(o, "durationSec"))
    }
}

/// Desktop `SyncState`: the host's playback snapshot, relayed to the room.
struct TogetherSyncState: Equatable, Sendable {
    var mediaId: String?
    var mediaTitle: String?
    var episode: TogetherEpisodeRef?
    var posterUrl: String?
    var positionSeconds: Double
    var playing: Bool
    var speed: Double?
    var source: TogetherSourceDescriptor?
    var guestPick: Bool?
    var updatedAt: Double
    var updatedBy: String
    var hostClientId: String?
}

extension TogetherSyncState {
    init(json o: [String: Any]) {
        let episode = TogetherJSON.object(o, "episode").flatMap { TogetherEpisodeRef(json: $0) }
        let source = TogetherJSON.object(o, "source").map { TogetherSourceDescriptor(json: $0) }
        self.init(mediaId: TogetherJSON.string(o, "mediaId"), mediaTitle: TogetherJSON.string(o, "mediaTitle"),
                  episode: episode, posterUrl: TogetherJSON.string(o, "posterUrl"),
                  positionSeconds: TogetherJSON.number(o, "positionSeconds") ?? 0,
                  playing: TogetherJSON.bool(o, "playing") ?? false, speed: TogetherJSON.number(o, "speed"),
                  source: source, guestPick: TogetherJSON.bool(o, "guestPick"),
                  updatedAt: TogetherJSON.number(o, "updatedAt") ?? 0,
                  updatedBy: TogetherJSON.string(o, "updatedBy") ?? "",
                  hostClientId: TogetherJSON.string(o, "hostClientId"))
    }

    var json: [String: Any] {
        var o: [String: Any] = ["positionSeconds": positionSeconds, "playing": playing,
                                "updatedAt": updatedAt, "updatedBy": updatedBy]
        TogetherJSON.putNullable(&o, "mediaId", mediaId)
        TogetherJSON.putNullable(&o, "mediaTitle", mediaTitle)
        TogetherJSON.putNullable(&o, "posterUrl", posterUrl)
        TogetherJSON.putNullable(&o, "hostClientId", hostClientId)
        if let episode = episode { o["episode"] = episode.json } else { o["episode"] = NSNull() }
        TogetherJSON.put(&o, "speed", speed)
        TogetherJSON.put(&o, "source", source?.json)
        TogetherJSON.put(&o, "guestPick", guestPick)
        return o
    }
}

/// Desktop `PlayInvite`: "watch this title now" sent to the room.
struct TogetherPlayInvite: Equatable, Sendable {
    var mediaId: String
    var mediaType: String
    var mediaTitle: String
    var releaseInfo: String?
    var posterUrl: String?
    var backgroundUrl: String?
    var logoUrl: String?
    var episode: TogetherEpisodeRef?
    var proto: Int?
    var guestPick: Bool?
    var source: TogetherSourceDescriptor?
}

extension TogetherPlayInvite {
    init?(json o: [String: Any]) {
        guard let mediaId = TogetherJSON.string(o, "mediaId"), !mediaId.isEmpty else { return nil }
        let episode = TogetherJSON.object(o, "episode").flatMap { TogetherEpisodeRef(json: $0) }
        let source = TogetherJSON.object(o, "source").map { TogetherSourceDescriptor(json: $0) }
        self.init(mediaId: mediaId, mediaType: TogetherJSON.string(o, "mediaType") ?? "movie",
                  mediaTitle: TogetherJSON.string(o, "mediaTitle") ?? "", releaseInfo: TogetherJSON.string(o, "releaseInfo"),
                  posterUrl: TogetherJSON.string(o, "posterUrl"), backgroundUrl: TogetherJSON.string(o, "backgroundUrl"),
                  logoUrl: TogetherJSON.string(o, "logoUrl"), episode: episode, proto: TogetherJSON.int(o, "proto"),
                  guestPick: TogetherJSON.bool(o, "guestPick"), source: source)
    }

    var json: [String: Any] {
        var o: [String: Any] = ["mediaId": mediaId, "mediaType": mediaType, "mediaTitle": mediaTitle]
        TogetherJSON.put(&o, "releaseInfo", releaseInfo)
        TogetherJSON.put(&o, "posterUrl", posterUrl)
        TogetherJSON.put(&o, "backgroundUrl", backgroundUrl)
        TogetherJSON.put(&o, "logoUrl", logoUrl)
        TogetherJSON.put(&o, "episode", episode?.json)
        TogetherJSON.put(&o, "proto", proto)
        TogetherJSON.put(&o, "guestPick", guestPick)
        TogetherJSON.put(&o, "source", source?.json)
        return o
    }
}

/// Desktop `SummonTarget`: "come look at this" pointer sent by a member.
struct TogetherSummonTarget: Equatable, Sendable {
    var mediaId: String?
    var mediaType: String?
    var mediaTitle: String?
    var posterUrl: String?
    var backgroundUrl: String?
    var releaseInfo: String?
    /// One of `home`, `discover`, `anime`, `queue`, `addons` (SummonView in protocol.ts).
    var view: String?
    var addonId: String?
    var label: String?
}

extension TogetherSummonTarget {
    init(json o: [String: Any]) {
        self.init(mediaId: TogetherJSON.string(o, "mediaId"), mediaType: TogetherJSON.string(o, "mediaType"),
                  mediaTitle: TogetherJSON.string(o, "mediaTitle"), posterUrl: TogetherJSON.string(o, "posterUrl"),
                  backgroundUrl: TogetherJSON.string(o, "backgroundUrl"), releaseInfo: TogetherJSON.string(o, "releaseInfo"),
                  view: TogetherJSON.string(o, "view"), addonId: TogetherJSON.string(o, "addonId"),
                  label: TogetherJSON.string(o, "label"))
    }

    var json: [String: Any] {
        var o: [String: Any] = [:]
        TogetherJSON.put(&o, "mediaId", mediaId)
        TogetherJSON.put(&o, "mediaType", mediaType)
        TogetherJSON.put(&o, "mediaTitle", mediaTitle)
        TogetherJSON.put(&o, "posterUrl", posterUrl)
        TogetherJSON.put(&o, "backgroundUrl", backgroundUrl)
        TogetherJSON.put(&o, "releaseInfo", releaseInfo)
        TogetherJSON.put(&o, "view", view)
        TogetherJSON.put(&o, "addonId", addonId)
        TogetherJSON.put(&o, "label", label)
        return o
    }
}

/// Desktop `RoomCommand`: play, pause, or a seek with the coalescer's sequence number and send time.
enum TogetherRoomCommand: Equatable, Sendable {
    case play
    case pause
    case seek(positionSeconds: Double, seq: Int?, at: Double?)
}

extension TogetherRoomCommand {
    init?(json o: [String: Any]) {
        switch TogetherJSON.string(o, "action") ?? "" {
        case "play":
            self = .play
        case "pause":
            self = .pause
        case "seek":
            guard let position = TogetherJSON.number(o, "positionSeconds") else { return nil }
            self = .seek(positionSeconds: position, seq: TogetherJSON.int(o, "seq"), at: TogetherJSON.number(o, "at"))
        default:
            return nil
        }
    }

    var json: [String: Any] {
        switch self {
        case .play:
            return ["action": "play"]
        case .pause:
            return ["action": "pause"]
        case .seek(let position, let seq, let at):
            var o: [String: Any] = ["action": "seek", "positionSeconds": position]
            TogetherJSON.put(&o, "seq", seq)
            TogetherJSON.put(&o, "at", at)
            return o
        }
    }
}

// MARK: - Client frames (ClientMessage in protocol.ts)

/// Every client-to-relay message this port sends. `cursor`, `draw` and `presence` are intentionally absent.
enum TogetherClientMessage: Equatable, Sendable {
    case hello(name: String, avatar: String?, color: String?)
    case profile(name: String, avatar: String?, color: String?)
    case leave
    case state(TogetherSyncState)
    case command(TogetherRoomCommand)
    case chat(String)
    case invite(TogetherPlayInvite)
    case ready(Bool)
    case hostLeaving
    case claimHost(fresh: Bool)
    case start
    case summon(TogetherSummonTarget)
    case ping

    var type: String {
        switch self {
        case .hello: return "hello"
        case .profile: return "profile"
        case .leave: return "leave"
        case .state: return "state"
        case .command: return "cmd"
        case .chat: return "chat"
        case .invite: return "invite"
        case .ready: return "ready"
        case .hostLeaving: return "host-leaving"
        case .claimHost: return "claim-host"
        case .start: return "start"
        case .summon: return "summon"
        case .ping: return "ping"
        }
    }

    /// Dropped rather than queued while the socket is down (`send` in client.ts).
    var isVolatile: Bool {
        switch self {
        case .hello, .profile, .leave, .claimHost, .ping: return true
        default: return false
        }
    }

    var isState: Bool {
        if case .state = self { return true }
        return false
    }

    func json(room: String, clientId: String) -> [String: Any] {
        var o: [String: Any] = ["t": type, "room": room, "clientId": clientId]
        switch self {
        case .hello(let name, let avatar, let color), .profile(let name, let avatar, let color):
            o["name"] = name
            o["avatar"] = TogetherJSON.nullable(avatar)
            o["color"] = TogetherJSON.nullable(color)
        case .leave, .hostLeaving, .start, .ping:
            break
        case .state(let state):
            o["state"] = state.json
        case .command(let command):
            o["command"] = command.json
        case .chat(let text):
            o["text"] = text
        case .invite(let invite):
            o["invite"] = invite.json
        case .ready(let ready):
            o["ready"] = ready
        case .claimHost(let fresh):
            o["fresh"] = fresh
        case .summon(let target):
            o["target"] = target.json
        }
        return o
    }
}

// MARK: - Server frames (ServerMessage in protocol.ts)

struct TogetherJoined: Equatable, Sendable {
    var room: String
    var participants: [TogetherParticipant]
    var state: TogetherSyncState?
    var hostClientId: String?
    var started: Bool
    var srvAt: Double?
    var relayVersion: Int?
}

/// Every relay-to-client message this port understands. Cursor, draw and presence frames decode to nil.
enum TogetherServerMessage: Equatable, Sendable {
    case joined(TogetherJoined)
    case participantJoined(TogetherParticipant)
    case participantLeft(clientId: String, name: String?)
    case started(Bool)
    case participantReady(clientId: String, ready: Bool)
    case participantProfile(id: String, name: String, avatar: String?, color: String?)
    case host(String?)
    case hostLeaving(from: String, name: String, at: Double)
    case summon(from: String, name: String, target: TogetherSummonTarget, at: Double)
    case state(TogetherSyncState, srvAt: Double?)
    case command(from: String, command: TogetherRoomCommand)
    case chat(from: String, name: String, text: String, at: Double)
    case invite(from: String, name: String, invite: TogetherPlayInvite, at: Double)
    case error(code: String, message: String)
    case pong(srvAt: Double?)

    static func decode(_ text: String) -> TogetherServerMessage? {
        guard let o = TogetherJSON.object(from: text), let type = TogetherJSON.string(o, "t") else { return nil }
        switch type {
        case "joined": return decodeJoined(o)
        case "participant-joined": return decodeParticipantJoined(o)
        case "participant-left": return decodeParticipantLeft(o)
        case "started": return .started(TogetherJSON.bool(o, "started") ?? false)
        case "participant-ready": return decodeParticipantReady(o)
        case "participant-profile": return decodeParticipantProfile(o)
        case "host": return .host(TogetherJSON.string(o, "hostClientId"))
        case "host-leaving": return decodeHostLeaving(o)
        case "summon": return decodeSummon(o)
        case "state": return decodeState(o)
        case "cmd": return decodeCommand(o)
        case "chat": return decodeChat(o)
        case "invite": return decodeInvite(o)
        case "error":
            return .error(code: TogetherJSON.string(o, "code") ?? "", message: TogetherJSON.string(o, "message") ?? "")
        case "pong": return .pong(srvAt: TogetherJSON.number(o, "srvAt"))
        default: return nil
        }
    }

    private static func decodeJoined(_ o: [String: Any]) -> TogetherServerMessage? {
        guard let room = TogetherJSON.string(o, "room") else { return nil }
        let participants = TogetherJSON.array(o, "participants").compactMap { TogetherParticipant(json: $0) }
        var state: TogetherSyncState?
        if let raw = TogetherJSON.object(o, "state") { state = TogetherSyncState(json: raw) }
        let joined = TogetherJoined(room: room, participants: participants, state: state,
                                    hostClientId: TogetherJSON.string(o, "hostClientId"),
                                    started: TogetherJSON.bool(o, "started") ?? false,
                                    srvAt: TogetherJSON.number(o, "srvAt"),
                                    relayVersion: TogetherJSON.int(o, "relayVersion"))
        return .joined(joined)
    }

    private static func decodeParticipantJoined(_ o: [String: Any]) -> TogetherServerMessage? {
        guard let raw = TogetherJSON.object(o, "participant"), let participant = TogetherParticipant(json: raw) else { return nil }
        return .participantJoined(participant)
    }

    private static func decodeParticipantLeft(_ o: [String: Any]) -> TogetherServerMessage? {
        guard let id = TogetherJSON.string(o, "clientId") else { return nil }
        return .participantLeft(clientId: id, name: TogetherJSON.string(o, "name"))
    }

    private static func decodeParticipantReady(_ o: [String: Any]) -> TogetherServerMessage? {
        guard let id = TogetherJSON.string(o, "clientId") else { return nil }
        return .participantReady(clientId: id, ready: TogetherJSON.bool(o, "ready") ?? false)
    }

    private static func decodeParticipantProfile(_ o: [String: Any]) -> TogetherServerMessage? {
        guard let raw = TogetherJSON.object(o, "participant"), let id = TogetherJSON.string(raw, "id"),
              let name = TogetherJSON.string(raw, "name") else { return nil }
        return .participantProfile(id: id, name: name, avatar: TogetherJSON.string(raw, "avatar"),
                                   color: TogetherJSON.string(raw, "color"))
    }

    private static func decodeHostLeaving(_ o: [String: Any]) -> TogetherServerMessage? {
        guard let sender = TogetherJSON.string(o, "from") else { return nil }
        return .hostLeaving(from: sender, name: TogetherJSON.string(o, "name") ?? "",
                            at: TogetherJSON.number(o, "at") ?? 0)
    }

    private static func decodeSummon(_ o: [String: Any]) -> TogetherServerMessage? {
        guard let sender = TogetherJSON.string(o, "from"), let raw = TogetherJSON.object(o, "target") else { return nil }
        return .summon(from: sender, name: TogetherJSON.string(o, "name") ?? "",
                       target: TogetherSummonTarget(json: raw), at: TogetherJSON.number(o, "at") ?? 0)
    }

    private static func decodeState(_ o: [String: Any]) -> TogetherServerMessage? {
        guard let raw = TogetherJSON.object(o, "state") else { return nil }
        return .state(TogetherSyncState(json: raw), srvAt: TogetherJSON.number(o, "srvAt"))
    }

    private static func decodeCommand(_ o: [String: Any]) -> TogetherServerMessage? {
        guard let sender = TogetherJSON.string(o, "from"), let raw = TogetherJSON.object(o, "command"),
              let command = TogetherRoomCommand(json: raw) else { return nil }
        return .command(from: sender, command: command)
    }

    private static func decodeChat(_ o: [String: Any]) -> TogetherServerMessage? {
        guard let sender = TogetherJSON.string(o, "from"), let text = TogetherJSON.string(o, "text") else { return nil }
        return .chat(from: sender, name: TogetherJSON.string(o, "name") ?? "", text: text,
                     at: TogetherJSON.number(o, "at") ?? 0)
    }

    private static func decodeInvite(_ o: [String: Any]) -> TogetherServerMessage? {
        guard let sender = TogetherJSON.string(o, "from"), let raw = TogetherJSON.object(o, "invite"),
              let invite = TogetherPlayInvite(json: raw) else { return nil }
        return .invite(from: sender, name: TogetherJSON.string(o, "name") ?? "", invite: invite,
                       at: TogetherJSON.number(o, "at") ?? 0)
    }
}

// MARK: - Relay URLs and failures

enum TogetherRelay {
    /// `openSocket` in client.ts: https to wss, http to ws, no trailing slash, then `/r/<room>`.
    static func websocketURL(relay: String, room: String) -> URL? {
        URL(string: websocketBase(relay) + "/r/" + room)
    }

    static func websocketBase(_ relay: String) -> String {
        var base = replacingScheme(relay.togetherTrimmed, from: "https://", to: "wss://")
        base = replacingScheme(base, from: "http://", to: "ws://")
        while base.hasSuffix("/") { base.removeLast() }
        return hasWebSocketScheme(base) ? base : "wss://" + base
    }

    /// `httpBase` in client.ts, used for the `/health` probe.
    static func healthBase(_ relay: String) -> String {
        var base = replacingScheme(relay.togetherTrimmed, from: "wss://", to: "https://")
        base = replacingScheme(base, from: "ws://", to: "http://")
        while base.hasSuffix("/") { base.removeLast() }
        return hasHTTPScheme(base) ? base : "https://" + base
    }

    /// `isPublicRelay` (relay-version.ts): the host is exactly Desktop's public relay.
    static func isPublic(_ url: String) -> Bool {
        var host = url.togetherTrimmed.lowercased()
        if let scheme = ["wss://", "ws://", "https://", "http://"].first(where: { host.hasPrefix($0) }) {
            host = String(host.dropFirst(scheme.count))
        }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        return host == "pub.harbor.site"
    }

    static func hasWebSocketScheme(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("wss://") || lower.hasPrefix("ws://")
    }

    static func hasHTTPScheme(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://")
    }

    static func replacingScheme(_ value: String, from: String, to: String) -> String {
        guard value.lowercased().hasPrefix(from) else { return value }
        return to + String(value.dropFirst(from.count))
    }
}

/// `relayOutdated` (relay-version.ts). The public relay is never reported as outdated.
enum TogetherRelayVersion {
    static func isOutdated(_ version: Int?, relay: String) -> Bool {
        if TogetherRelay.isPublic(relay) { return false }
        guard let version = version else { return true }
        return version < TogetherProtocol.requiredRelayVersion
    }
}

/// `diagnoseRelayFailure` (client-types.ts), as English keys for `DesktopInterfaceText`. `nil` means unreachable.
enum TogetherRelayDiagnosis {
    static func message(healthStatus: Int?) -> String {
        guard let status = healthStatus else {
            return "The watch together relay is unreachable. Check the relay URL in Settings or your connection."
        }
        if status == 429 {
            return "The watch together relay is over its daily limit right now. Try again later, or point it at another relay in Settings."
        }
        if (200..<300).contains(status) {
            return "The relay is reachable but refused the room, most likely over its daily limit. Try again later, or switch relays in Settings."
        }
        return "The relay returned an error (HTTP \(status)). Check the relay URL in Settings."
    }
}

/// `reconnect` delay of client.ts: exponential from 1 s to 30 s, plus up to 30% jitter (`jitter` in 0..<1).
enum TogetherReconnect {
    static func delayMs(attempt: Int, jitter: Double) -> Double {
        let exponential = min(TogetherTiming.reconnectBaseMs * pow(2, Double(attempt)), TogetherTiming.reconnectMaxMs)
        let clamped = max(0, min(jitter, 1))
        return exponential + clamped * 0.3 * exponential
    }
}

// MARK: - Invites and join input

struct TogetherJoinLink: Equatable, Sendable {
    var relayURL: String
    var roomCode: String
}

/// `buildInviteUrl` and `parseInviteFromLocation` (invite.ts). The link is `<base>/?harbor-relay=...&harbor-room=...`.
enum TogetherInviteLink {
    static let relayParam = "harbor-relay"
    static let roomParam = "harbor-room"

    static func build(relayURL: String, roomCode: String, base: String = TogetherProtocol.inviteBaseURL) -> String {
        let relay = TogetherFormEncoding.encode(relayURL)
        let room = TogetherFormEncoding.encode(roomCode.uppercased())
        return base + "/?" + relayParam + "=" + relay + "&" + roomParam + "=" + room
    }

    /// Accepts a full link, a bare query string, or raw text containing the two parameters. Returns nil unless the
    /// relay is ws or wss and the room code normalises to something non-empty.
    static func parse(_ text: String) -> TogetherJoinLink? {
        guard let query = queryString(text) else { return nil }
        let params = parameters(query)
        guard let relayRaw = params[relayParam], let roomRaw = params[roomParam] else { return nil }
        let relay = relayRaw.togetherTrimmed
        guard relay.hasPrefix("wss://") || relay.hasPrefix("ws://") else { return nil }
        let room = TogetherRoomCode.normalize(roomRaw.togetherTrimmed)
        if room.isEmpty { return nil }
        return TogetherJoinLink(relayURL: relay, roomCode: room)
    }

    static func queryString(_ text: String) -> String? {
        var rest = text.togetherTrimmed
        if let hash = rest.firstIndex(of: "#") { rest = String(rest[..<hash]) }
        if let question = rest.firstIndex(of: "?") {
            return String(rest[rest.index(after: question)...])
        }
        return rest.contains("=") ? rest : nil
    }

    /// Like `URLSearchParams.get`: the first occurrence of a key wins.
    static func parameters(_ query: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let first = parts.first else { continue }
            let key = TogetherFormEncoding.decode(String(first))
            let value = parts.count > 1 ? TogetherFormEncoding.decode(String(parts[1])) : ""
            if out[key] == nil { out[key] = value }
        }
        return out
    }
}

/// `application/x-www-form-urlencoded` as `URLSearchParams` writes it: unreserved bytes stay, space is `+`.
enum TogetherFormEncoding {
    static func encode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            if isUnreserved(byte) {
                out.append(Character(UnicodeScalar(byte)))
            } else if byte == 0x20 {
                out.append("+")
            } else {
                out += String(format: "%%%02X", Int(byte))
            }
        }
        return out
    }

    static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
            || byte == 0x2A || byte == 0x2D || byte == 0x2E || byte == 0x5F
    }
}

/// What the Join field means: a pasted link (which also switches the relay, as Desktop does), a room code, or nothing.
enum TogetherJoinInput {
    enum Resolution: Equatable, Sendable {
        case link(TogetherJoinLink)
        case room(String)
        case empty
    }

    static func resolve(_ text: String) -> Resolution {
        let value = text.togetherTrimmed
        if value.isEmpty { return .empty }
        let lower = value.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || value.contains("harbor-relay=") {
            if let link = TogetherInviteLink.parse(value) { return .link(link) }
        }
        let room = TogetherRoomCode.normalize(value)
        return room.isEmpty ? .empty : .room(room)
    }
}

enum TogetherInviteBuilder {
    /// `buildPlayInvite` (build-invite.ts) for an already resolved title.
    static func playInvite(mediaId: String, isSeries: Bool, title: String, releaseInfo: String?, poster: String?,
                           background: String?, logo: String?, episode: TogetherEpisodeRef?) -> TogetherPlayInvite {
        TogetherPlayInvite(mediaId: mediaId, mediaType: isSeries ? "series" : "movie", mediaTitle: title,
                           releaseInfo: releaseInfo, posterUrl: poster, backgroundUrl: background, logoUrl: logo,
                           episode: episode, proto: nil, guestPick: nil, source: nil)
    }
}

// MARK: - Source descriptor and matching

/// The fields of a playable stream that a descriptor is built from (`PlayerStreamRef` on Desktop).
struct TogetherSourceInput: Equatable, Sendable {
    var parsedTitle: String?
    var title: String?
    var resolution: String?
    var sizeBytes: Double?
    var infoHash: String?
    var fileIdx: Int?
}

enum TogetherSourceBuilder {
    /// `buildSourceDescriptor` (source-descriptor.ts). Hashes must be 16 to 64 lowercase hex digits.
    static func descriptor(from input: TogetherSourceInput?, durationSec: Double?) -> TogetherSourceDescriptor? {
        var out = TogetherSourceDescriptor()
        let picked = nonEmpty(input?.parsedTitle) ?? nonEmpty(input?.title) ?? ""
        let title = picked.togetherTrimmed
        if !title.isEmpty { out.title = String(title.prefix(200)) }
        out.resolution = TogetherSourceDescriptor.normalizeResolution(input?.resolution)
        if let size = input?.sizeBytes, size.isFinite, size > 0 {
            out.sizeBytes = Int(size.rounded(.toNearestOrAwayFromZero))
        }
        if let hash = validHash(input?.infoHash) {
            out.infoHash = hash
            if let index = input?.fileIdx, index >= 0 { out.fileIdx = index }
        }
        if let duration = durationSec, duration.isFinite, duration > 0 {
            out.durationSec = (duration * 10).rounded(.toNearestOrAwayFromZero) / 10
        }
        return out.isEmpty ? nil : out
    }

    static func validHash(_ value: String?) -> String? {
        guard let raw = value else { return nil }
        let hash = raw.togetherTrimmed.lowercased()
        if hash.count < 16 || hash.count > 64 { return nil }
        for character in hash where !character.isHexDigit { return nil }
        return hash
    }

    private static func nonEmpty(_ value: String?) -> String? {
        if let value = value, !value.isEmpty { return value }
        return nil
    }
}

/// The fields of a candidate stream that matching reads (`ScoredStream` on Desktop).
struct TogetherMatchCandidate: Equatable, Sendable {
    var infoHash: String?
    var fileIdx: Int?
    var resolution: String?
    var sizeBytes: Double?
    /// `parsedTitle || title`.
    var title: String?
    /// `releaseGroupNormalized || releaseGroup`.
    var releaseGroup: String?
}

enum TogetherSourceMatch {
    static let sameFileScore = 1000.0
    static let closeScore = 300.0

    /// `scoreSourceMatch` (source-match.ts).
    static func score(_ candidate: TogetherMatchCandidate, host: TogetherSourceDescriptor) -> Double {
        var total = 0.0
        if let hostHash = host.infoHash, let candidateHash = candidate.infoHash, candidateHash.lowercased() == hostHash {
            total += 1000
            if let hostIndex = host.fileIdx, let candidateIndex = candidate.fileIdx, hostIndex == candidateIndex {
                total += 50
            }
        }
        let hostResolution = TogetherSourceDescriptor.normalizeResolution(host.resolution)
        let candidateResolution = TogetherSourceDescriptor.normalizeResolution(candidate.resolution)
        if let a = hostResolution, let b = candidateResolution, a == b { total += 200 }
        if let hostSize = host.sizeBytes, hostSize > 0, let candidateSize = candidate.sizeBytes, candidateSize > 0 {
            let drift = abs(candidateSize - Double(hostSize)) / (Double(hostSize) * 0.35)
            total += 150 * max(0, 1 - drift)
        }
        if let hostTitle = host.title {
            total += titleScore(hostTitle: hostTitle, candidate: candidate)
        }
        return total
    }

    private static func titleScore(hostTitle: String, candidate: TogetherMatchCandidate) -> Double {
        var total = 0.0
        let hostTokens = tokens(hostTitle)
        let candidateTokens = tokens(candidate.title ?? "")
        if !hostTokens.isEmpty && !candidateTokens.isEmpty {
            var shared = 0
            for token in candidateTokens where hostTokens.contains(token) { shared += 1 }
            let union = hostTokens.count + candidateTokens.count - shared
            if union > 0 { total += 120 * Double(shared) / Double(union) }
        }
        let group = normalizedGroup(candidate.releaseGroup)
        if !group.isEmpty && hostTokens.contains(group) { total += 40 }
        return total
    }

    /// `[a-z0-9]+` runs of the lowercased text.
    static func tokens(_ text: String) -> Set<String> {
        var out = Set<String>()
        var current = ""
        for character in text.lowercased() {
            if isASCIIAlphanumeric(character) {
                current.append(character)
            } else if !current.isEmpty {
                out.insert(current)
                current = ""
            }
        }
        if !current.isEmpty { out.insert(current) }
        return out
    }

    static func normalizedGroup(_ value: String?) -> String {
        guard let value = value else { return "" }
        var out = ""
        for character in value.lowercased() where isASCIIAlphanumeric(character) {
            out.append(character)
        }
        return out
    }

    /// `matchBadge`: "same", "close", or nil.
    static func badge(_ score: Double?) -> String? {
        guard let score = score else { return nil }
        if score >= sameFileScore { return "same" }
        if score >= closeScore { return "close" }
        return nil
    }

    /// `sortByHostMatch`, stable like the JavaScript sort: equal scores keep their original order.
    static func sorted<T>(_ items: [T], host: TogetherSourceDescriptor, candidate: (T) -> TogetherMatchCandidate) -> [T] {
        var scored: [TogetherIndexedScore<T>] = []
        for (index, item) in items.enumerated() {
            scored.append(TogetherIndexedScore(index: index, item: item, score: score(candidate(item), host: host)))
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.index < rhs.index
        }
        return scored.map { $0.item }
    }

    private static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        (character >= "a" && character <= "z") || (character >= "0" && character <= "9")
    }
}

struct TogetherIndexedScore<T> {
    let index: Int
    let item: T
    let score: Double
}

// MARK: - Room derivation (room-derive.ts)

struct TogetherHostSource: Equatable, Sendable {
    var descriptor: TogetherSourceDescriptor
    var mediaId: String?
    var episode: TogetherEpisodeRef?
}

struct TogetherLastInvite: Equatable, Sendable {
    var key: String
    var at: Double
    var proto: Int
    var guestPick: Bool
}

enum TogetherRoomDerive {
    /// The host's source, only when the latest state was written by the host.
    static func hostSource(_ snapshot: TogetherRoomSnapshot) -> TogetherHostSource? {
        guard let state = snapshot.syncState, let source = state.source else { return nil }
        guard let host = snapshot.hostClientId, state.updatedBy == host else { return nil }
        return TogetherHostSource(descriptor: source, mediaId: state.mediaId, episode: state.episode)
    }

    static func hostSourceMatchesMedia(_ info: TogetherHostSource?, mediaId: String, episode: TogetherEpisodeRef?) -> Bool {
        guard let info = info, info.mediaId == mediaId else { return false }
        if (info.episode == nil) != (episode == nil) { return false }
        if let hostEpisode = info.episode, let episode = episode {
            if hostEpisode.season != episode.season || hostEpisode.episode != episode.episode { return false }
        }
        return true
    }

    /// `isDifferentMedia` (use-room-sync.ts): a state for another title or episode.
    static func isDifferentMedia(_ state: TogetherSyncState, mediaId: String, episode: TogetherEpisodeRef?) -> Bool {
        guard let stateMedia = state.mediaId else { return false }
        if stateMedia != mediaId { return true }
        if (state.episode == nil) != (episode == nil) { return true }
        if let stateEpisode = state.episode, let episode = episode {
            if stateEpisode.season != episode.season || stateEpisode.episode != episode.episode { return true }
        }
        return false
    }

    /// `inviteMediaKey` (provider-events.ts).
    static func inviteKey(_ invite: TogetherPlayInvite) -> String {
        let season = invite.episode.map { String($0.season) } ?? ""
        let episode = invite.episode.map { String($0.episode) } ?? ""
        return invite.mediaId + "|" + season + "|" + episode
    }

    /// `deriveRoomGuestPick`: whether the host's latest word asks guests to pick their own source.
    static func guestPick(_ snapshot: TogetherRoomSnapshot, clientId: String, lastInvite: TogetherLastInvite?) -> Bool {
        guard let host = snapshot.hostClientId, host != clientId else { return false }
        let state = snapshot.syncState
        let stateAt = (state != nil && state?.updatedBy == host) ? (state?.updatedAt ?? 0) : 0
        let inviteAt = lastInvite?.at ?? 0
        if stateAt == 0 && inviteAt == 0 { return false }
        if inviteAt >= stateAt { return lastInvite?.guestPick == true }
        return state?.guestPick == true
    }
}

// MARK: - Clock alignment (client.ts relay offset)

/// Estimates the relay clock offset from ping round trips (`recordPong`, `localizeStateClock`).
/// Times are milliseconds. The first sample is taken as-is; later samples blend 70/30.
struct TogetherClockSync: Equatable, Sendable {
    private(set) var relayOffset: Double?
    private(set) var pingSentAt: Double = 0
    private(set) var haveRttOffset = false

    mutating func markPing(at nowMs: Double) {
        pingSentAt = nowMs
    }

    mutating func recordPong(srvAt: Double?, nowMs: Double) {
        guard let serverAt = srvAt, pingSentAt != 0 else { return }
        let rtt = nowMs - pingSentAt
        if rtt < 0 || rtt > TogetherTiming.rttCeilingMs { return }
        let sample = serverAt - (pingSentAt + rtt / 2)
        if haveRttOffset {
            relayOffset = (relayOffset ?? sample) * 0.7 + sample * 0.3
        } else {
            relayOffset = sample
            haveRttOffset = true
        }
        pingSentAt = 0
    }

    /// Converts a relay timestamp to local milliseconds. The first relay timestamp fixes the offset if none is known.
    mutating func localize(srvAt: Double, nowMs: Double) -> Double {
        if relayOffset == nil { relayOffset = srvAt - nowMs }
        return srvAt - (relayOffset ?? 0)
    }

    mutating func reset() {
        pingSentAt = 0
        relayOffset = nil
        haveRttOffset = false
    }
}

/// Playback thresholds of `player-utils.ts`, in seconds unless the name says otherwise.
enum TogetherSync {
    static let driftToleranceSec = 0.6
    static let suppressMs = 1_400.0
    static let playLookaheadSec = 0.4
    static let maxAgeSec = 30.0
    static let seekJumpSec = 10.0
    static let heartbeatMs = 1_000.0
    static let seekApplyDebounceMs = 120.0

    /// `syncRate`: the host's speed when it is a positive number, otherwise 1.
    static func rate(_ state: TogetherSyncState) -> Double {
        if let speed = state.speed, speed.isFinite, speed > 0 { return speed }
        return 1
    }

    /// `syncTarget`: the host's position projected forward by its age (capped) while it plays, clamped to the duration.
    static func target(_ state: TogetherSyncState, durationSec: Double, nowMs: Double) -> Double {
        let ageSec = min(maxAgeSec, max(0, (nowMs - state.updatedAt) / 1000))
        var target = state.positionSeconds
        if state.playing {
            target += (ageSec + playLookaheadSec) * rate(state)
        }
        if durationSec > 0 {
            target = min(target, max(0, durationSec - 0.25))
        }
        return target
    }
}

// MARK: - Seek coalescing (seek-coalesce.ts)

struct TogetherSeekSend: Equatable, Sendable {
    var positionSeconds: Double
    var seq: Int
    var at: Double
}

/// Sends at most one seek per interval, always the latest position. The owner calls `tick` on a timer; `push` and
/// `flush` return what should go out now. Times are milliseconds.
struct TogetherSeekCoalescer: Equatable, Sendable {
    let intervalMs: Double
    private(set) var seq: Int
    private(set) var timerDue: Double?
    private(set) var pending: Double?
    private(set) var lastSentAt: Double = 0

    init(seed: Int, intervalMs: Double = 250) {
        self.seq = seed
        self.intervalMs = intervalMs
    }

    mutating func push(_ position: Double, nowMs now: Double) -> TogetherSeekSend? {
        if timerDue == nil && now - lastSentAt >= intervalMs {
            let sent = fire(position, nowMs: now)
            timerDue = now + intervalMs
            return sent
        }
        pending = position
        if timerDue == nil {
            timerDue = now + max(0, intervalMs - (now - lastSentAt))
        }
        return nil
    }

    mutating func tick(nowMs now: Double) -> TogetherSeekSend? {
        guard let due = timerDue, now >= due else { return nil }
        timerDue = nil
        guard let position = pending else { return nil }
        pending = nil
        let sent = fire(position, nowMs: now)
        timerDue = now + intervalMs
        return sent
    }

    mutating func flush(nowMs now: Double) -> TogetherSeekSend? {
        timerDue = nil
        guard let position = pending else { return nil }
        pending = nil
        return fire(position, nowMs: now)
    }

    mutating func dispose() {
        timerDue = nil
        pending = nil
    }

    private mutating func fire(_ position: Double, nowMs now: Double) -> TogetherSeekSend {
        seq += 1
        lastSentAt = now
        return TogetherSeekSend(positionSeconds: position, seq: seq, at: now)
    }
}

/// `createCommandSender`: seeks go through the coalescer. Any other command first flushes a pending seek, so the
/// relay sees them in order.
struct TogetherCommandSender: Equatable, Sendable {
    private(set) var coalescer: TogetherSeekCoalescer

    init(seed: Int) {
        coalescer = TogetherSeekCoalescer(seed: seed)
    }

    /// The commands to transmit now, in order.
    mutating func send(_ command: TogetherRoomCommand, nowMs now: Double) -> [TogetherRoomCommand] {
        if case .seek(let position, _, _) = command {
            guard let sent = coalescer.push(position, nowMs: now) else { return [] }
            return [seekCommand(sent)]
        }
        var out: [TogetherRoomCommand] = []
        if let sent = coalescer.flush(nowMs: now) { out.append(seekCommand(sent)) }
        out.append(command)
        return out
    }

    mutating func tick(nowMs now: Double) -> [TogetherRoomCommand] {
        guard let sent = coalescer.tick(nowMs: now) else { return [] }
        return [seekCommand(sent)]
    }

    mutating func dispose() {
        coalescer.dispose()
    }

    private func seekCommand(_ sent: TogetherSeekSend) -> TogetherRoomCommand {
        .seek(positionSeconds: sent.positionSeconds, seq: sent.seq, at: sent.at)
    }
}

// MARK: - Room snapshot (client-types.ts)

enum TogetherConnectionState: String, Equatable, Sendable {
    case disconnected
    case connecting
    case joined
    case error
}

struct TogetherRoomSnapshot: Equatable, Sendable {
    var state: TogetherConnectionState = .disconnected
    var room: String?
    var participants: [TogetherParticipant] = []
    var syncState: TogetherSyncState?
    var hostClientId: String?
    var started = false
    var relayVersion: Int?
    var lastError: String?
}
