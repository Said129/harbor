import XCTest
@testable import Harbor

/// Desktop's Chromecast CASTv2 path (`cast.rs`, through `rust_cast`): framing, protobuf bytes, JSON payloads, canned
/// replies and a scripted session. No network.
final class CastChromecastTests: XCTestCase {
    /// The device side of a conversation. Each client frame gets the replies `respond` returns, and `deliver` pushes a
    /// device-initiated message such as PING.
    private final class ScriptedCastStream: CastByteStream, @unchecked Sendable {
        let incoming: AsyncThrowingStream<Data, Error>
        private let sink: AsyncThrowingStream<Data, Error>.Continuation
        private let respond: @Sendable (CastChromecast.Message) -> [CastChromecast.Message]
        private let lock = NSLock()
        private var received: [CastChromecast.Message] = []

        init(respond: @escaping @Sendable (CastChromecast.Message) -> [CastChromecast.Message]) {
            let channel = AsyncThrowingStream<Data, Error>.makeStream()
            incoming = channel.stream
            sink = channel.continuation
            self.respond = respond
        }

        /// Every message the client wrote, in order.
        var sentMessages: [CastChromecast.Message] {
            lock.lock()
            defer { lock.unlock() }
            return received
        }

        func send(_ data: Data) async throws {
            var reader = CastChromecast.FrameReader()
            let messages = try reader.append(data)
            record(messages)
            for message in messages {
                for reply in respond(message) {
                    sink.yield(Data(CastChromecast.frame(reply)))
                }
            }
        }

        func close() {
            sink.finish()
        }

        /// Pushes a device-initiated message, such as PING.
        func deliver(_ message: CastChromecast.Message) {
            sink.yield(Data(CastChromecast.frame(message)))
        }

        private func record(_ messages: [CastChromecast.Message]) {
            lock.lock()
            defer { lock.unlock() }
            received += messages
        }
    }

    /// A receiver that launches the default media receiver with transport `web-5` and session `sess-1`, loads media 7, and
    /// answers the media controls with a paused status at 42.5 seconds.
    private static func deviceReply(to message: CastChromecast.Message) -> [CastChromecast.Message] {
        guard let inbound = CastChromecast.parseInbound(message.payload), let id = inbound.requestID else { return [] }
        switch inbound.type {
        case "LAUNCH":
            let app = "{\"appId\":\"CC1AD845\",\"sessionId\":\"sess-1\",\"transportId\":\"web-5\"}"
            return [reply(namespace: CastChromecast.receiverNamespace, "{\"type\":\"RECEIVER_STATUS\",\"requestId\":\(id),\"status\":{\"applications\":[\(app)]}}")]
        case "LOAD", "SEEK":
            return [reply(namespace: CastChromecast.mediaNamespace, "{\"type\":\"MEDIA_STATUS\",\"requestId\":\(id),\"status\":[{\"mediaSessionId\":7,\"playerState\":\"PLAYING\",\"currentTime\":0.0}]}")]
        case "GET_STATUS":
            return [reply(namespace: CastChromecast.mediaNamespace, "{\"type\":\"MEDIA_STATUS\",\"requestId\":\(id),\"status\":[{\"mediaSessionId\":7,\"playerState\":\"PAUSED\",\"currentTime\":42.5}]}")]
        case "STOP":
            return [reply(namespace: CastChromecast.receiverNamespace, "{\"type\":\"RECEIVER_STATUS\",\"requestId\":\(id),\"status\":{\"applications\":[]}}")]
        default:
            return []
        }
    }

    private static func reply(namespace: String, _ payload: String) -> CastChromecast.Message {
        CastChromecast.Message(sourceID: CastChromecast.receiverID, destinationID: CastChromecast.senderID, namespace: namespace, payload: payload)
    }

    // MARK: Framing and protobuf bytes

    func testConnectFrameMatchesTheCastV2ByteLayout() {
        let connect = CastChromecast.Message(
            sourceID: "sender-0",
            destinationID: "receiver-0",
            namespace: CastChromecast.connectionNamespace,
            payload: CastChromecast.connectPayload()
        )
        // Length 0x58 = 88 bytes of protobuf. Fields: 1 varint 0, 2 "sender-0", 3 "receiver-0", 4 namespace, 5 varint 0, 6 payload.
        var expected: [UInt8] = [0x00, 0x00, 0x00, 0x58, 0x08, 0x00, 0x12, 0x08]
        expected += Array("sender-0".utf8)
        expected += [0x1A, 0x0A]
        expected += Array("receiver-0".utf8)
        expected += [0x22, 0x28]
        expected += Array("urn:x-cast:com.google.cast.tp.connection".utf8)
        expected += [0x28, 0x00, 0x32, 0x12]
        expected += Array("{\"type\":\"CONNECT\"}".utf8)
        XCTAssertEqual(CastChromecast.frame(connect), expected)
    }

    func testPingFrameMatchesTheCastV2ByteLayout() {
        let ping = CastChromecast.Message(
            sourceID: "sender-0",
            destinationID: "receiver-0",
            namespace: CastChromecast.heartbeatNamespace,
            payload: CastChromecast.pingPayload()
        )
        // Length 0x54 = 84 bytes. The heartbeat namespace is 39 bytes long and the payload is 15.
        var expected: [UInt8] = [0x00, 0x00, 0x00, 0x54, 0x08, 0x00, 0x12, 0x08]
        expected += Array("sender-0".utf8)
        expected += [0x1A, 0x0A]
        expected += Array("receiver-0".utf8)
        expected += [0x22, 0x27]
        expected += Array("urn:x-cast:com.google.cast.tp.heartbeat".utf8)
        expected += [0x28, 0x00, 0x32, 0x0F]
        expected += Array("{\"type\":\"PING\"}".utf8)
        XCTAssertEqual(CastChromecast.frame(ping), expected)
    }

    func testFrameReaderWaitsForWholeFramesAcrossChunks() throws {
        let connect = CastChromecast.Message(
            sourceID: "sender-0",
            destinationID: "receiver-0",
            namespace: CastChromecast.connectionNamespace,
            payload: CastChromecast.connectPayload()
        )
        let frame = Data(CastChromecast.frame(connect))
        XCTAssertEqual(frame.count, 92)
        var reader = CastChromecast.FrameReader()
        XCTAssertEqual(try reader.append(frame.prefix(3)), [])
        XCTAssertEqual(try reader.append(frame.dropFirst(3).prefix(40)), [])
        XCTAssertEqual(try reader.append(frame.dropFirst(43)), [connect])
    }

    func testLoadPayloadMatchesDesktopFieldsAndRoundTripsThroughFraming() throws {
        let payload = CastChromecast.loadPayload(
            requestID: 2,
            sessionID: "sess-1",
            url: "https://cdn.example.com/movie.mp4",
            contentType: "video/mp4",
            title: "Night Movie",
            poster: nil,
            startSeconds: 125.5
        )
        XCTAssertEqual(
            payload,
            "{\"type\":\"LOAD\",\"requestId\":2,\"sessionId\":\"sess-1\",\"media\":{\"contentId\":\"https://cdn.example.com/movie.mp4\",\"streamType\":\"BUFFERED\",\"contentType\":\"video/mp4\",\"metadata\":{\"metadataType\":1,\"title\":\"Night Movie\"}},\"currentTime\":125.5,\"autoplay\":true}"
        )
        let load = CastChromecast.Message(sourceID: "sender-0", destinationID: "web-5", namespace: CastChromecast.mediaNamespace, payload: payload)
        var reader = CastChromecast.FrameReader()
        XCTAssertEqual(try reader.append(Data(CastChromecast.frame(load))), [load])
    }

    func testLoadStartsAtZeroUpToHalfASecond() {
        let payload = CastChromecast.loadPayload(requestID: 3, sessionID: "s", url: "https://cdn.example.com/a.mp4", contentType: "video/mp4", title: nil, poster: nil, startSeconds: 0.5)
        XCTAssertTrue(payload.contains("\"currentTime\":0.0,"))
        XCTAssertFalse(payload.contains("\"title\""))
    }

    // MARK: Replies

    func testMediaAndReceiverStatusParseCannedReplies() {
        let media = "{\"type\":\"MEDIA_STATUS\",\"requestId\":0,\"status\":[{\"mediaSessionId\":7,\"playbackRate\":1,\"playerState\":\"PAUSED\",\"currentTime\":42.5,\"media\":{\"contentId\":\"https://cdn.example.com/movie.mp4\",\"duration\":5400.0,\"streamType\":\"BUFFERED\"}}]}"
        XCTAssertEqual(
            CastChromecast.parseInbound(media),
            CastChromecast.Inbound(type: "MEDIA_STATUS", requestID: 0, reason: nil, payload: media)
        )
        XCTAssertEqual(
            CastChromecast.parseMediaStatus(media),
            [CastChromecast.MediaEntry(mediaSessionID: 7, playerState: "PAUSED", currentTime: 42.5, durationSec: 5400)]
        )

        let receiver = "{\"type\":\"RECEIVER_STATUS\",\"requestId\":1,\"status\":{\"applications\":[{\"appId\":\"CC1AD845\",\"displayName\":\"Default Media Receiver\",\"sessionId\":\"sess-1\",\"transportId\":\"web-5\"}],\"volume\":{\"level\":0.5,\"muted\":false}}}"
        let expectedApp = CastChromecast.ReceiverApp(appID: "CC1AD845", transportID: "web-5", sessionID: "sess-1")
        XCTAssertEqual(
            CastChromecast.parseReceiverStatus(receiver),
            CastChromecast.ReceiverStatus(apps: [expectedApp], volumeLevel: 0.5)
        )

        let failed = "{\"type\":\"LOAD_FAILED\",\"requestId\":3,\"reason\":\"INVALID_MEDIA\"}"
        XCTAssertEqual(CastChromecast.parseInbound(failed)?.reason, "INVALID_MEDIA")
    }

    // MARK: Rules

    func testContentTypeAndContainerRulesFollowDesktop() {
        XCTAssertEqual(CastChromecast.contentType(url: "https://cdn.example.com/live/index.m3u8?token=1"), "application/x-mpegURL")
        XCTAssertEqual(CastChromecast.contentType(url: "https://cdn.example.com/movie.mp4"), "video/mp4")
        XCTAssertTrue(CastChromecast.isUnsupportedContainer(url: "https://cdn.example.com/movie.mkv?x=1"))
        XCTAssertFalse(CastChromecast.isUnsupportedContainer(url: "https://cdn.example.com/movie.mp4"))
    }

    func testChromecastFailuresHaveCopyAndOtherErrorsDoNot() {
        XCTAssertNotNil(CastChromecast.failureMessage(for: CastProtocolError.chromecastDropped))
        XCTAssertNotNil(CastChromecast.failureMessage(for: CastProtocolError.chromecastUnreachable))
        XCTAssertNotNil(CastChromecast.failureMessage(for: CastProtocolError.chromecastRefused))
        XCTAssertNotNil(CastChromecast.failureMessage(for: CastProtocolError.chromecastTLS))
        XCTAssertNil(CastChromecast.failureMessage(for: CastProtocolError.transport))
    }

    // MARK: Session

    func testScriptedSessionLaunchesLoadsSeeksAndStops() async throws {
        let stream = ScriptedCastStream(respond: CastChromecastTests.deviceReply)
        let session = CastChromecastSession(stream: stream, requestTimeout: .seconds(5), heartbeatInterval: .seconds(3600))
        try await session.connect()
        try await session.launch(appID: CastChromecast.defaultMediaReceiverAppID)
        let mediaID = try await session.load(url: "https://cdn.example.com/movie.mp4", contentType: "video/mp4", title: "Night Movie", poster: nil, startSeconds: 0)
        XCTAssertEqual(mediaID, 7)
        try await session.seek(to: 30)
        let status = try await session.mediaStatus()
        XCTAssertEqual(status?.currentTime, 42.5)
        XCTAssertEqual(status?.playerState, "PAUSED")
        try await session.stopReceiver()
        await session.close()

        let sent = stream.sentMessages
        XCTAssertEqual(
            sent.map { CastChromecast.parseInbound($0.payload)?.type ?? "" },
            ["CONNECT", "PING", "LAUNCH", "CONNECT", "LOAD", "SEEK", "GET_STATUS", "STOP"]
        )
        XCTAssertEqual(
            sent.map(\.destinationID),
            ["receiver-0", "receiver-0", "receiver-0", "web-5", "web-5", "web-5", "web-5", "receiver-0"]
        )
        XCTAssertTrue(sent[4].payload.contains("\"sessionId\":\"sess-1\""))
        XCTAssertTrue(sent[5].payload.contains("\"mediaSessionId\":7"))
        XCTAssertTrue(sent[5].payload.contains("\"currentTime\":30.0"))
    }

    func testSessionAnswersTheReceiversPingWithPong() async throws {
        let stream = ScriptedCastStream { _ in [] }
        let session = CastChromecastSession(stream: stream, heartbeatInterval: .seconds(3600))
        try await session.connect()
        stream.deliver(CastChromecast.Message(
            sourceID: CastChromecast.receiverID,
            destinationID: CastChromecast.senderID,
            namespace: CastChromecast.heartbeatNamespace,
            payload: CastChromecast.pingPayload()
        ))
        for _ in 0..<50 {
            if stream.sentMessages.contains(where: { $0.payload == CastChromecast.pongPayload() }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let types = stream.sentMessages.map { CastChromecast.parseInbound($0.payload)?.type ?? "" }
        XCTAssertEqual(types, ["CONNECT", "PING", "PONG"])
        await session.close()
    }
}
