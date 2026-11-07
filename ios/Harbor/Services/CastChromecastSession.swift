import Foundation
import Network
import Security

/// The byte stream a Chromecast session runs on. The app uses `CastChromecastTLSStream`; tests script one.
protocol CastByteStream: Sendable {
    /// Bytes from the device, in order. The stream finishes or throws when the connection ends.
    var incoming: AsyncThrowingStream<Data, Error> { get }
    func send(_ data: Data) async throws
    func close()
}

/// One CASTv2 conversation: CONNECT, the heartbeat, LAUNCH, LOAD and the media controls, as Desktop's `cast.rs` runs them.
/// Requests are matched to their replies by `requestId`. MEDIA_STATUS and RECEIVER_STATUS also reach `updates`.
actor CastChromecastSession {
    enum Update: Equatable, Sendable {
        case media(CastChromecast.MediaEntry)
        case receiverVolume(Double)
    }

    let updates: AsyncStream<Update>

    private let stream: CastByteStream
    private let requestTimeout: Duration
    private let heartbeatInterval: Duration
    private let updateSink: AsyncStream<Update>.Continuation
    private var waiters: [Int: CheckedContinuation<CastChromecast.Inbound, Error>] = [:]
    private var nextRequestID = 1
    private var transportID: String?
    private var sessionID: String?
    private var mediaSessionID: Int?
    private var receiver: CastChromecast.ReceiverStatus?
    private var readTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var closed = false

    init(stream: CastByteStream, requestTimeout: Duration = .seconds(10), heartbeatInterval: Duration = .seconds(5)) {
        self.stream = stream
        self.requestTimeout = requestTimeout
        self.heartbeatInterval = heartbeatInterval
        // Status updates are only observed, so the newest few are kept rather than one per poll without limit.
        let channel = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(8))
        updates = channel.stream
        updateSink = channel.continuation
    }

    /// The receiver's volume from its last RECEIVER_STATUS, 0 to 1.
    var currentVolume: Double? {
        receiver?.volumeLevel
    }

    // MARK: Connection

    /// Starts reading and the heartbeat, then sends CONNECT and PING to the platform receiver (Desktop's `connect_device_once`).
    func connect() async throws {
        guard readTask == nil else { return }
        readTask = Task { await self.readLoop() }
        startHeartbeat()
        try await sendFrame(namespace: CastChromecast.connectionNamespace, destination: CastChromecast.receiverID, payload: CastChromecast.connectPayload())
        try await sendFrame(namespace: CastChromecast.heartbeatNamespace, destination: CastChromecast.receiverID, payload: CastChromecast.pingPayload())
    }

    /// Desktop's `launch_receiver_app`: LAUNCH the app, wait until RECEIVER_STATUS lists it, then CONNECT to its transport.
    func launch(appID: String) async throws {
        _ = try await request(namespace: CastChromecast.receiverNamespace, destination: CastChromecast.receiverID) { id in
            CastChromecast.launchPayload(requestID: id, appID: appID)
        }
        var app = findApp(appID)
        var attempts = 0
        while app == nil {
            attempts += 1
            guard attempts <= 40 else { throw CastProtocolError.chromecastRejected("launch") }
            try await Task.sleep(for: .milliseconds(250))
            app = findApp(appID)
        }
        if let app {
            transportID = app.transportID
            sessionID = app.sessionID
            try await sendFrame(namespace: CastChromecast.connectionNamespace, destination: app.transportID, payload: CastChromecast.connectPayload())
        } else {
            throw CastProtocolError.chromecastRejected("launch")
        }
    }

    /// Desktop's `load`: LOAD on the transport with the receiver's session id. Returns the media session id.
    func load(url: String, contentType: String, title: String?, poster: String?, startSeconds: Double) async throws -> Int {
        guard let transportID, let sessionID else { throw CastProtocolError.chromecastRejected("no session") }
        let reply = try await request(namespace: CastChromecast.mediaNamespace, destination: transportID) { id in
            CastChromecast.loadPayload(requestID: id, sessionID: sessionID, url: url, contentType: contentType, title: title, poster: poster, startSeconds: startSeconds)
        }
        guard let entry = CastChromecast.parseMediaStatus(reply.payload).first else { throw CastProtocolError.chromecastRejected("load") }
        mediaSessionID = entry.mediaSessionID
        return entry.mediaSessionID
    }

    // MARK: Media controls

    func play() async throws {
        _ = try await mediaRequest { CastChromecast.playPayload(requestID: $0, mediaSessionID: $1) }
    }

    func pause() async throws {
        _ = try await mediaRequest { CastChromecast.pausePayload(requestID: $0, mediaSessionID: $1) }
    }

    func seek(to seconds: Double) async throws {
        _ = try await mediaRequest { CastChromecast.seekPayload(requestID: $0, mediaSessionID: $1, seconds: seconds) }
    }

    /// Desktop's `status`: GET_STATUS for the media session. nil when the receiver reports no entry.
    func mediaStatus() async throws -> CastChromecast.MediaEntry? {
        guard let transportID else { throw CastProtocolError.chromecastRejected("no session") }
        let mediaID = mediaSessionID
        let reply = try await request(namespace: CastChromecast.mediaNamespace, destination: transportID) { id in
            CastChromecast.getStatusPayload(requestID: id, mediaSessionID: mediaID)
        }
        return CastChromecast.parseMediaStatus(reply.payload).first
    }

    /// SET_VOLUME on the receiver. The level is clamped to 0 to 1.
    func setVolume(_ level: Double) async throws {
        let clamped = min(max(level, 0), 1)
        _ = try await request(namespace: CastChromecast.receiverNamespace, destination: CastChromecast.receiverID) { id in
            CastChromecast.volumePayload(requestID: id, level: clamped)
        }
    }

    /// Desktop's `stop_app`: STOP the receiver session. A half-open socket must not hold up the local hand-back, so it gets a
    /// 2-second wait instead of the full request timeout.
    func stopReceiver() async throws {
        guard let sessionID else { throw CastProtocolError.chromecastRejected("no session") }
        _ = try await request(namespace: CastChromecast.receiverNamespace, destination: CastChromecast.receiverID, within: .seconds(2)) { id in
            CastChromecast.stopPayload(requestID: id, sessionID: sessionID)
        }
    }

    /// Ends the read loop and the heartbeat, and fails any request still waiting.
    func close() {
        readTask?.cancel()
        finish(with: CastProtocolError.chromecastDropped)
    }

    // MARK: Requests

    private func mediaRequest(_ build: (Int, Int) -> String) async throws -> CastChromecast.Inbound {
        guard let transportID, let mediaSessionID else { throw CastProtocolError.chromecastRejected("no media session") }
        return try await request(namespace: CastChromecast.mediaNamespace, destination: transportID) { id in
            build(id, mediaSessionID)
        }
    }

    /// Sends one request and waits for the reply with the same `requestId`. The waiter is registered before the frame is
    /// written, so a fast reply cannot arrive first. A reply that never comes fails as unreachable after `requestTimeout`.
    private func request(namespace: String, destination: String, within: Duration? = nil, build: (Int) -> String) async throws -> CastChromecast.Inbound {
        try ensureOpen()
        let id = nextRequestID
        nextRequestID += 1
        let message = CastChromecast.Message(sourceID: CastChromecast.senderID, destinationID: destination, namespace: namespace, payload: build(id))
        let frame = CastChromecast.frame(message)
        let timeout = within ?? requestTimeout
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CastChromecast.Inbound, Error>) in
            waiters[id] = continuation
            Task { await self.transmit(frame, requestID: id) }
            Task {
                try? await Task.sleep(for: timeout)
                await self.expire(requestID: id)
            }
        }
    }

    private func transmit(_ frame: [UInt8], requestID: Int) async {
        do {
            try await stream.send(Data(frame))
        } catch {
            waiters.removeValue(forKey: requestID)?.resume(throwing: error)
        }
    }

    private func expire(requestID: Int) {
        waiters.removeValue(forKey: requestID)?.resume(throwing: CastProtocolError.chromecastUnreachable)
    }

    private func sendFrame(namespace: String, destination: String, payload: String) async throws {
        try ensureOpen()
        let message = CastChromecast.Message(sourceID: CastChromecast.senderID, destinationID: destination, namespace: namespace, payload: payload)
        try await stream.send(Data(CastChromecast.frame(message)))
    }

    private func ensureOpen() throws {
        if closed { throw CastProtocolError.chromecastDropped }
    }

    private func findApp(_ appID: String) -> CastChromecast.ReceiverApp? {
        receiver?.apps.first { $0.appID == appID }
    }

    // MARK: Inbound

    private func readLoop() async {
        var reader = CastChromecast.FrameReader()
        do {
            for try await chunk in stream.incoming {
                for message in try reader.append(chunk) {
                    await handle(message)
                }
            }
            finish(with: CastProtocolError.chromecastDropped)
        } catch {
            finish(with: error)
        }
    }

    /// Status messages update the session and reach `updates`. A reply with a known `requestId` resolves its waiter.
    private func handle(_ message: CastChromecast.Message) async {
        guard let inbound = CastChromecast.parseInbound(message.payload) else { return }
        switch inbound.type {
        case "PING":
            try? await sendFrame(namespace: CastChromecast.heartbeatNamespace, destination: CastChromecast.receiverID, payload: CastChromecast.pongPayload())
            return
        case "MEDIA_STATUS":
            for entry in CastChromecast.parseMediaStatus(inbound.payload) {
                mediaSessionID = entry.mediaSessionID
                updateSink.yield(.media(entry))
            }
        case "RECEIVER_STATUS":
            let status = CastChromecast.parseReceiverStatus(inbound.payload)
            receiver = status
            if let level = status.volumeLevel {
                updateSink.yield(.receiverVolume(level))
            }
        default:
            break
        }
        guard let requestID = inbound.requestID, let waiter = waiters.removeValue(forKey: requestID) else { return }
        if CastChromecast.errorTypes.contains(inbound.type) {
            waiter.resume(throwing: CastProtocolError.chromecastRejected(inbound.reason ?? inbound.type))
        } else {
            waiter.resume(returning: inbound)
        }
    }

    private func finish(with error: Error) {
        closed = true
        heartbeatTask?.cancel()
        heartbeatTask = nil
        for waiter in waiters.values {
            waiter.resume(throwing: error)
        }
        waiters.removeAll()
        updateSink.finish()
        stream.close()
    }

    // MARK: Heartbeat

    /// Desktop's heartbeat answers the receiver's PING with PONG. This client also sends PING every `heartbeatInterval`, as Rust's `rust_cast` keeps the channel alive.
    private func startHeartbeat() {
        let interval = heartbeatInterval
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                await self.pingIfOpen()
            }
        }
    }

    private func pingIfOpen() async {
        guard !closed else { return }
        try? await sendFrame(namespace: CastChromecast.heartbeatNamespace, destination: CastChromecast.receiverID, payload: CastChromecast.pingPayload())
    }
}

/// The real `CastByteStream`: TLS to the receiver on port 8009 through `NWConnection`. Chromecasts present a self-signed
/// certificate, so the verify block accepts every chain. Desktop does the same with `connect_without_host_verification` (`cast.rs`).
final class CastChromecastTLSStream: CastByteStream, @unchecked Sendable {
    let incoming: AsyncThrowingStream<Data, Error>
    private let incomingSink: AsyncThrowingStream<Data, Error>.Continuation
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "site.harbor.cast.chromecast.tls")
    /// Touched only on `queue`.
    private var readyContinuation: CheckedContinuation<Void, Error>?

    /// Connects and returns once the TLS session is ready. A host that stays silent fails as unreachable after `timeout` seconds.
    static func open(host: String, port: UInt16 = CastChromecast.port, timeout: TimeInterval = 5) async throws -> CastChromecastTLSStream {
        let stream = try CastChromecastTLSStream(host: host, port: port)
        try await stream.start(timeout: timeout)
        return stream
    }

    private init(host: String, port: UInt16) throws {
        let endpointPort: NWEndpoint.Port? = NWEndpoint.Port(rawValue: port)
        guard let endpointPort else { throw CastProtocolError.invalidURL }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, DispatchQueue.global(qos: .utility))
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
        let channel = AsyncThrowingStream<Data, Error>.makeStream()
        incoming = channel.stream
        incomingSink = channel.continuation
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: CastChromecastTLSStream.mapped(error))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func close() {
        connection.cancel()
        incomingSink.finish()
    }

    private func start(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.readyContinuation = continuation
                self.connection.stateUpdateHandler = { state in self.handleState(state) }
                self.connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    guard self.readyContinuation != nil else { return }
                    self.finishReady(CastProtocolError.chromecastUnreachable)
                    self.connection.cancel()
                }
            }
        }
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            finishReady(nil)
            receiveNext()
        case .failed(let error):
            let mapped = CastChromecastTLSStream.mapped(error)
            finishReady(mapped)
            incomingSink.finish(throwing: mapped)
        case .cancelled:
            finishReady(CastProtocolError.chromecastDropped)
            incomingSink.finish()
        default:
            break
        }
    }

    private func finishReady(_ error: Error?) {
        guard let continuation = readyContinuation else { return }
        readyContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.incomingSink.yield(data)
            }
            if let error {
                self.incomingSink.finish(throwing: CastChromecastTLSStream.mapped(error))
                return
            }
            if isComplete {
                self.incomingSink.finish()
                return
            }
            self.receiveNext()
        }
    }

    /// Desktop's `humanize_cast_error` cases (`cast.rs`), by POSIX code. Anything else stays generic.
    static func mapped(_ error: NWError) -> CastProtocolError {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNRESET: return .chromecastDropped
            case .ECONNREFUSED: return .chromecastRefused
            case .ETIMEDOUT, .EHOSTUNREACH, .ENETUNREACH: return .chromecastUnreachable
            default: return .transport
            }
        case .tls:
            return .chromecastTLS
        default:
            return .transport
        }
    }
}
