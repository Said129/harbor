import Foundation

/// Google Cast CASTv2 as Desktop's `cast.rs` drives it through the `rust_cast` crate: the length-prefixed `CastMessage`
/// frames, a minimal protobuf codec for that envelope, the JSON payloads Desktop sends and the parsers for the replies it
/// reads. Pure code with no I/O. `CastChromecastSession` writes these bytes over TLS.
enum CastChromecast {
    static let port: UInt16 = 8009
    static let senderID = "sender-0"
    static let receiverID = "receiver-0"
    /// Desktop's `HARBOR_RECEIVER_APP_ID` (`cast.rs`), launched for video. Desktop uses the default media receiver
    /// (`CC1AD845`) for audio only, and iOS casts video only.
    static let harborReceiverAppID = "120F754D"
    static let connectionNamespace = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeatNamespace = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let receiverNamespace = "urn:x-cast:com.google.cast.receiver"
    static let mediaNamespace = "urn:x-cast:com.google.cast.media"
    /// Replies that end a request with an error instead of a status.
    static let errorTypes: Set<String> = ["INVALID_REQUEST", "LOAD_FAILED", "LOAD_CANCELLED", "LAUNCH_ERROR", "INVALID_PLAYER_STATE"]
    /// A frame longer than this is treated as a broken stream.
    static let maxFrameLength = 1_048_576

    /// One `CastMessage`. Binary payloads are not used by Desktop's media flow, so they decode as an empty payload.
    struct Message: Equatable, Sendable {
        let sourceID: String
        let destinationID: String
        let namespace: String
        let payload: String
    }

    /// A parsed JSON payload: its `type`, its `requestId` when present, and the `reason` of an error reply.
    struct Inbound: Equatable, Sendable {
        let type: String
        let requestID: Int?
        let reason: String?
        let payload: String
    }

    /// One entry of a MEDIA_STATUS reply. `currentTime` is the position on the media timeline, in seconds.
    struct MediaEntry: Equatable, Sendable {
        let mediaSessionID: Int
        let playerState: String
        let currentTime: Double
        let durationSec: Double?
    }

    struct ReceiverApp: Equatable, Sendable {
        let appID: String
        let transportID: String
        let sessionID: String
    }

    struct ReceiverStatus: Equatable, Sendable {
        let apps: [ReceiverApp]
        let volumeLevel: Double?
    }

    // MARK: Framing

    /// The wire form of one message: a 4-byte big-endian length, then the protobuf body.
    static func frame(_ message: Message) -> [UInt8] {
        let body = CastProtobuf.encode(message)
        let length = body.count
        let prefix: [UInt8] = [
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF),
        ]
        return prefix + body
    }

    /// Collects bytes from the socket and returns each complete message, keeping a partial frame for the next chunk.
    struct FrameReader: Sendable {
        private var buffer: [UInt8] = []

        mutating func append(_ data: Data) throws -> [Message] {
            buffer.append(contentsOf: data)
            var messages: [Message] = []
            while buffer.count >= 4 {
                let length = (Int(buffer[0]) << 24) | (Int(buffer[1]) << 16) | (Int(buffer[2]) << 8) | Int(buffer[3])
                guard length <= CastChromecast.maxFrameLength else { throw CastProtocolError.transport }
                guard buffer.count >= 4 + length else { break }
                let body = Array(buffer[4..<(4 + length)])
                buffer.removeFirst(4 + length)
                guard let message = CastProtobuf.decode(body) else { throw CastProtocolError.transport }
                messages.append(message)
            }
            return messages
        }
    }

    // MARK: Payloads

    static func connectPayload() -> String {
        CastJSON.object([("type", CastJSON.string("CONNECT"))])
    }

    static func pingPayload() -> String {
        CastJSON.object([("type", CastJSON.string("PING"))])
    }

    static func pongPayload() -> String {
        CastJSON.object([("type", CastJSON.string("PONG"))])
    }

    /// Desktop's `launch_app`: LAUNCH with the receiver app id.
    static func launchPayload(requestID: Int, appID: String) -> String {
        command("LAUNCH", requestID: requestID, [("appId", CastJSON.string(appID))])
    }

    /// Desktop's `get_status`: GET_STATUS for one media session, or for all of them when `mediaSessionID` is nil.
    static func getStatusPayload(requestID: Int, mediaSessionID: Int?) -> String {
        let fields: [(String, String)] = mediaSessionID.map { [("mediaSessionId", "\($0)")] } ?? []
        return command("GET_STATUS", requestID: requestID, fields)
    }

    /// Desktop's `load` (`cast.rs`, `cast_load_chromecast`): a buffered Movie item with the start time, autoplay on.
    /// Unlike Desktop's HLS path, the start time is always sent, because iOS never serves a segmented stream.
    static func loadPayload(requestID: Int, sessionID: String, url: String, contentType: String, title: String?, poster: String?, startSeconds: Double) -> String {
        var metadata: [(String, String)] = [("metadataType", "1")]
        if let title {
            metadata.append(("title", CastJSON.string(title)))
        }
        if let poster {
            metadata.append(("images", CastJSON.array([CastJSON.object([("url", CastJSON.string(poster))])])))
        }
        let media = CastJSON.object([
            ("contentId", CastJSON.string(url)),
            ("streamType", CastJSON.string("BUFFERED")),
            ("contentType", CastJSON.string(contentType)),
            ("metadata", CastJSON.object(metadata)),
        ])
        // Desktop starts at the resume point only past half a second.
        let current: Double = startSeconds > 0.5 ? startSeconds : 0
        return command("LOAD", requestID: requestID, [
            ("sessionId", CastJSON.string(sessionID)),
            ("media", media),
            ("currentTime", CastJSON.number(current)),
            ("autoplay", "true"),
        ])
    }

    static func playPayload(requestID: Int, mediaSessionID: Int) -> String {
        command("PLAY", requestID: requestID, [("mediaSessionId", "\(mediaSessionID)")])
    }

    static func pausePayload(requestID: Int, mediaSessionID: Int) -> String {
        command("PAUSE", requestID: requestID, [("mediaSessionId", "\(mediaSessionID)")])
    }

    static func seekPayload(requestID: Int, mediaSessionID: Int, seconds: Double) -> String {
        command("SEEK", requestID: requestID, [
            ("mediaSessionId", "\(mediaSessionID)"),
            ("currentTime", CastJSON.number(seconds)),
        ])
    }

    /// Desktop's `stop_app`: STOP the receiver session.
    static func stopPayload(requestID: Int, sessionID: String) -> String {
        command("STOP", requestID: requestID, [("sessionId", CastJSON.string(sessionID))])
    }

    /// SET_VOLUME on the receiver. Desktop 0.9.132 has no Chromecast volume call; this is added for iOS. The level is 0 to 1.
    static func volumePayload(requestID: Int, level: Double) -> String {
        command("SET_VOLUME", requestID: requestID, [("volume", CastJSON.object([("level", CastJSON.number(level))]))])
    }

    private static func command(_ type: String, requestID: Int, _ fields: [(String, String)]) -> String {
        CastJSON.object([("type", CastJSON.string(type)), ("requestId", "\(requestID)")] + fields)
    }

    // MARK: Replies

    static func jsonObject(_ payload: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any]
    }

    static func parseInbound(_ payload: String) -> Inbound? {
        guard let object = jsonObject(payload), let type = object["type"] as? String else { return nil }
        return Inbound(type: type, requestID: object["requestId"] as? Int, reason: object["reason"] as? String, payload: payload)
    }

    /// Desktop's `status` for Chromecast: each entry of `status` in a MEDIA_STATUS reply.
    static func parseMediaStatus(_ payload: String) -> [MediaEntry] {
        guard let object = jsonObject(payload), let statuses = object["status"] as? [[String: Any]] else { return [] }
        var entries: [MediaEntry] = []
        for status in statuses {
            guard let id = status["mediaSessionId"] as? Int else { continue }
            let state = (status["playerState"] as? String) ?? "IDLE"
            let current = (status["currentTime"] as? Double) ?? 0
            let media = status["media"] as? [String: Any]
            let duration = media?["duration"] as? Double
            entries.append(MediaEntry(mediaSessionID: id, playerState: state.uppercased(), currentTime: current, durationSec: duration))
        }
        return entries
    }

    static func parseReceiverStatus(_ payload: String) -> ReceiverStatus {
        let status = jsonObject(payload)?["status"] as? [String: Any]
        let rawApps: [[String: Any]] = (status?["applications"] as? [[String: Any]]) ?? []
        var apps: [ReceiverApp] = []
        for app in rawApps {
            guard let appID = app["appId"] as? String,
                  let transportID = app["transportId"] as? String,
                  let sessionID = app["sessionId"] as? String else { continue }
            apps.append(ReceiverApp(appID: appID, transportID: transportID, sessionID: sessionID))
        }
        let volume = status?["volume"] as? [String: Any]
        return ReceiverStatus(apps: apps, volumeLevel: volume?["level"] as? Double)
    }

    // MARK: Rules

    /// Desktop's `chromecast_content_type` (`cast.rs`), with the same substring checks.
    static func contentType(url: String) -> String {
        let lower = url.lowercased()
        if lower.contains(".m3u8") { return "application/x-mpegURL" }
        if lower.contains(".ts") { return "video/mp2t" }
        return "video/mp4"
    }

    /// Containers the Chromecast cannot play as they are. Desktop remuxes them to HLS, which iOS cannot do, so they are refused.
    static func isUnsupportedContainer(url: String) -> Bool {
        let path = (url.components(separatedBy: "?").first ?? url).lowercased()
        return [".mkv", ".mks", ".avi", ".wmv"].contains { path.hasSuffix($0) }
    }

    /// Desktop's `humanize_cast_error` (`cast.rs`) copy for the Chromecast connection failures. nil for other errors.
    static func failureMessage(for error: Error) -> String? {
        switch error as? CastProtocolError {
        case .chromecastDropped?:
            return DesktopInterfaceText.value("Device dropped the connection. It may be busy with another app, asleep, or another phone is already casting to it. Wake the screen, stop other casts, and try again.")
        case .chromecastUnreachable?:
            return DesktopInterfaceText.value("Couldn't reach the device. Check it's on the same Wi-Fi as your computer.")
        case .chromecastRefused?:
            return DesktopInterfaceText.value("Device refused the connection. Try restarting it.")
        case .chromecastTLS?:
            return DesktopInterfaceText.value("Secure handshake failed. Make sure the TV is on the same network, and update its firmware if this keeps happening.")
        default:
            return nil
        }
    }
}

/// The CastMessage protobuf (`castchannel.proto`), hand-coded for the fields Desktop uses: protocol_version 1,
/// source_id 2, destination_id 3, namespace 4, payload_type 5 and payload_utf8 6. Field numbers and wire types are the proto2 ones.
enum CastProtobuf {
    static func encode(_ message: CastChromecast.Message) -> [UInt8] {
        var out: [UInt8] = []
        appendVarintField(&out, number: 1, value: 0)
        appendBytesField(&out, number: 2, Array(message.sourceID.utf8))
        appendBytesField(&out, number: 3, Array(message.destinationID.utf8))
        appendBytesField(&out, number: 4, Array(message.namespace.utf8))
        appendVarintField(&out, number: 5, value: 0)
        appendBytesField(&out, number: 6, Array(message.payload.utf8))
        return out
    }

    /// Reads the envelope. Unknown fields are skipped. Returns nil when the bytes are not a valid message.
    static func decode(_ bytes: [UInt8]) -> CastChromecast.Message? {
        var index = 0
        var sourceID = ""
        var destinationID = ""
        var namespace = ""
        var payload = ""
        while index < bytes.count {
            guard let key = readVarint(bytes, &index) else { return nil }
            let field = key >> 3
            let wireType = key & 0x7
            switch wireType {
            case 0:
                guard readVarint(bytes, &index) != nil else { return nil }
            case 1:
                guard bytes.count - index >= 8 else { return nil }
                index += 8
            case 2:
                guard let length = readVarint(bytes, &index), length <= UInt64(bytes.count - index) else { return nil }
                let end = index + Int(length)
                let text = String(decoding: bytes[index..<end], as: UTF8.self)
                index = end
                switch field {
                case 2: sourceID = text
                case 3: destinationID = text
                case 4: namespace = text
                case 6: payload = text
                default: break
                }
            case 5:
                guard bytes.count - index >= 4 else { return nil }
                index += 4
            default:
                return nil
            }
        }
        return CastChromecast.Message(sourceID: sourceID, destinationID: destinationID, namespace: namespace, payload: payload)
    }

    static func appendVarint(_ out: inout [UInt8], _ value: UInt64) {
        var rest = value
        while rest >= 0x80 {
            out.append(UInt8(rest & 0x7F) | 0x80)
            rest >>= 7
        }
        out.append(UInt8(rest))
    }

    private static func appendVarintField(_ out: inout [UInt8], number: UInt64, value: UInt64) {
        appendVarint(&out, (number << 3) | 0)
        appendVarint(&out, value)
    }

    private static func appendBytesField(_ out: inout [UInt8], number: UInt64, _ bytes: [UInt8]) {
        appendVarint(&out, (number << 3) | 2)
        appendVarint(&out, UInt64(bytes.count))
        out.append(contentsOf: bytes)
    }

    private static func readVarint(_ bytes: [UInt8], _ index: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            guard shift < 64 else { return nil }
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }
}

/// The JSON Desktop's Rust side writes for Cast payloads. Fields keep the order given, so the bytes are deterministic.
/// Each value is already encoded JSON.
enum CastJSON {
    static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0..<0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    static func number(_ value: Double) -> String {
        value.isFinite ? String(value) : "0"
    }

    static func object(_ fields: [(String, String)]) -> String {
        "{" + fields.map { string($0.0) + ":" + $0.1 }.joined(separator: ",") + "}"
    }

    static func array(_ items: [String]) -> String {
        "[" + items.joined(separator: ",") + "]"
    }
}
