import Foundation

// Desktop `src/lib/together/client.ts` as a state machine over an abstract socket. Time comes from `nowProvider`
// and timers are deadlines that `tick()` checks, so tests drive the clock and the socket without sleeping.
// The only real network code is `TogetherURLSessionSocket` at the bottom of this file.

enum TogetherRoomEvent: Equatable, Sendable {
    case snapshot(TogetherRoomSnapshot)
    case incomingState(TogetherSyncState)
    case incomingCommand(from: String, command: TogetherRoomCommand)
    case chat(from: String, name: String, text: String, at: Double)
    case invite(from: String, name: String, invite: TogetherPlayInvite, at: Double)
    case hostLeaving(from: String, name: String, at: Double)
    case summon(from: String, name: String, target: TogetherSummonTarget, at: Double)
    case participantLeft(clientId: String, name: String)
    case started(Bool)
}

/// One open relay connection. Real sockets and test fakes both implement this.
@MainActor protocol TogetherSocket: AnyObject {
    func send(_ text: String)
    func close()
}

/// Receives the socket's lifecycle. Callers must ignore callbacks from sockets they no longer own.
@MainActor protocol TogetherSocketDelegate: AnyObject {
    func togetherSocketDidOpen(_ socket: TogetherSocket)
    func togetherSocket(_ socket: TogetherSocket, didReceive text: String)
    func togetherSocketDidClose(_ socket: TogetherSocket)
}

@MainActor protocol TogetherSocketFactory {
    func makeSocket(url: URL, delegate: TogetherSocketDelegate) -> TogetherSocket
}

@MainActor final class TogetherClient: TogetherSocketDelegate {
    let events: AsyncStream<TogetherRoomEvent>
    let clientId: String
    private(set) var snapshot = TogetherRoomSnapshot()
    private(set) var isOpen = false

    private let continuation: AsyncStream<TogetherRoomEvent>.Continuation
    private let relayURL: String
    private let factory: TogetherSocketFactory
    private var name: String
    private var originalName: String
    private var avatar: String?
    private var color: String?
    private var renameAttempts = 0
    private var room: String?
    private var socket: TogetherSocket?
    private var outQueue: [TogetherClientMessage] = []
    private var lastSentInvite: TogetherPlayInvite?
    private var claimedHost = false
    private var intentional = false
    private var terminal = false
    private var everJoined = false
    private var joinedThisAttempt = false
    private var attemptResolved = false
    private var failStreak = 0
    private var reconnectAttempt = 0
    private var reconnectAt: Double?
    private var watchdogAt: Double?
    private var nextPingAt: Double?
    private var lastInboundAt: Double = 0
    private var suppressUntil: Double = 0
    private var clock = TogetherClockSync()

    /// Injected in tests. Milliseconds since the epoch.
    var nowProvider: () -> Double = { TogetherClock.nowMs() }
    /// Injected in tests. A value in 0..<1 for reconnect jitter.
    var jitterProvider: () -> Double = { Double.random(in: 0..<1) }

    init(relayURL: String, clientId: String, name: String, avatar: String? = nil, color: String? = nil,
         factory: TogetherSocketFactory) {
        let pair = AsyncStream.makeStream(of: TogetherRoomEvent.self)
        self.events = pair.stream
        self.continuation = pair.continuation
        self.relayURL = relayURL
        self.clientId = clientId
        self.name = name
        self.originalName = name
        self.avatar = TogetherClient.capAvatar(avatar)
        self.color = color
        self.factory = factory
    }

    // MARK: Public commands

    func join(room code: String) {
        if isOpen, let current = room, current != code { sendNow(.leave) }
        cleanup()
        outQueue = []
        lastSentInvite = nil
        reconnectAttempt = 0
        intentional = false
        room = code
        claimedHost = false
        everJoined = false
        failStreak = 0
        terminal = false
        update { snap in
            snap.state = .connecting
            snap.room = code
            snap.lastError = nil
            snap.started = false
            snap.relayVersion = nil
        }
        openSocket()
    }

    func leave() {
        intentional = true
        if isOpen { sendNow(.leave) }
        cleanup()
        reconnectAttempt = 0
        room = nil
        outQueue = []
        lastSentInvite = nil
        claimedHost = false
        update { $0 = TogetherRoomSnapshot() }
    }

    func retry() {
        guard room != nil else { return }
        terminal = false
        failStreak = 0
        reconnectAttempt = 0
        everJoined = false
        update { snap in
            snap.state = .connecting
            snap.lastError = nil
        }
        cleanup()
        openSocket()
    }

    func setName(_ value: String) {
        name = value
        originalName = value
        renameAttempts = 0
        if snapshot.state == .joined {
            send(.profile(name: name, avatar: avatar, color: color))
        }
    }

    func setProfile(avatar newAvatar: String?, color newColor: String?) {
        avatar = TogetherClient.capAvatar(newAvatar)
        color = newColor
        if snapshot.state == .joined {
            send(.profile(name: name, avatar: avatar, color: color))
        }
    }

    func suppressOutgoing(forMs ms: Double) {
        suppressUntil = nowProvider() + ms
    }

    func publishState(_ state: TogetherSyncState) {
        guard room != nil else { return }
        if nowProvider() < suppressUntil { return }
        send(.state(state))
        update { $0.syncState = state }
    }

    func sendCommand(_ command: TogetherRoomCommand) {
        guard room != nil, isOpen else { return }
        sendNow(.command(command))
    }

    func sendChat(_ text: String) {
        let trimmed = text.togetherTrimmed
        guard room != nil, !trimmed.isEmpty else { return }
        send(.chat(trimmed))
    }

    func sendInvite(_ invite: TogetherPlayInvite) {
        guard room != nil, !invite.mediaId.isEmpty else { return }
        lastSentInvite = invite
        send(.invite(invite))
    }

    func clearInvite() {
        lastSentInvite = nil
    }

    func markReady(_ ready: Bool) {
        guard room != nil else { return }
        send(.ready(ready))
    }

    func claimHost(fresh: Bool) {
        guard room != nil else { return }
        claimedHost = true
        send(.claimHost(fresh: fresh))
    }

    func startRoom() {
        guard room != nil else { return }
        send(.start)
    }

    func notifyHostLeaving() {
        guard room != nil else { return }
        send(.hostLeaving)
    }

    func sendSummon(_ target: TogetherSummonTarget) {
        guard room != nil else { return }
        send(.summon(target))
    }

    /// Records the outcome of the `/health` probe after a terminal failure. `nil` means unreachable.
    func applyHealthProbe(status: Int?) {
        guard terminal else { return }
        update { $0.lastError = TogetherRelayDiagnosis.message(healthStatus: status) }
    }

    /// Call about once a second, as Desktop's timers do: reconnects, the connect watchdog, ping and liveness.
    func tick() {
        let now = nowProvider()
        if let due = reconnectAt, now >= due {
            reconnectAt = nil
            openSocket()
        }
        if let due = watchdogAt, now >= due {
            watchdogAt = nil
            if !(joinedThisAttempt || attemptResolved) {
                dropSocket()
                failAttempt()
            }
        }
        if let due = nextPingAt, now >= due {
            if lastInboundAt > 0 && now - lastInboundAt > TogetherTiming.livenessTimeoutMs {
                dropSocket()
                handleSocketLost()
            } else {
                sendPing()
                nextPingAt = now + TogetherTiming.pingIntervalMs
            }
        }
    }

    // MARK: Socket delegate

    func togetherSocketDidOpen(_ socket: TogetherSocket) {
        guard isCurrent(socket) else { return }
        isOpen = true
        reconnectAttempt = 0
        let now = nowProvider()
        lastInboundAt = now
        sendPing()
        sendNow(.hello(name: name, avatar: avatar, color: color))
        flushOutQueue()
        if claimedHost { sendNow(.claimHost(fresh: false)) }
        if let invite = lastSentInvite { sendNow(.invite(invite)) }
        nextPingAt = now + TogetherTiming.pingIntervalMs
    }

    func togetherSocket(_ socket: TogetherSocket, didReceive text: String) {
        guard isCurrent(socket) else { return }
        lastInboundAt = nowProvider()
        guard let message = TogetherServerMessage.decode(text) else { return }
        handle(message)
    }

    func togetherSocketDidClose(_ socket: TogetherSocket) {
        guard isCurrent(socket) else { return }
        handleSocketLost()
    }

    // MARK: Server messages

    private func handle(_ message: TogetherServerMessage) {
        switch message {
        case .joined(let joined):
            handleJoined(joined)
        case .participantJoined(let participant):
            handleParticipantJoined(participant)
        case .participantLeft(let leftID, let leftName):
            handleParticipantLeft(leftID, leftName)
        case .started(let value):
            update { $0.started = value }
            continuation.yield(.started(value))
        case .participantReady(let readyID, let ready):
            editParticipant(readyID) { $0.ready = ready }
        case .participantProfile(let profileID, let profileName, let profileAvatar, let profileColor):
            editParticipant(profileID) { participant in
                participant.name = profileName
                participant.avatar = profileAvatar
                participant.color = profileColor
            }
        case .host(let hostID):
            update { $0.hostClientId = hostID }
            reconcileHostClaim(hostID)
        case .hostLeaving(let sender, let senderName, let at):
            continuation.yield(.hostLeaving(from: sender, name: senderName, at: at))
        case .summon(let sender, let senderName, let target, let at):
            continuation.yield(.summon(from: sender, name: senderName, target: target, at: at))
        case .state(var state, let srvAt):
            if let srv = srvAt { state.updatedAt = clock.localize(srvAt: srv, nowMs: nowProvider()) }
            update { $0.syncState = state }
            continuation.yield(.incomingState(state))
        case .command(let sender, let command):
            continuation.yield(.incomingCommand(from: sender, command: command))
        case .chat(let sender, let senderName, let text, let at):
            continuation.yield(.chat(from: sender, name: senderName, text: text, at: at))
        case .invite(let sender, let senderName, let invite, let at):
            if sender == clientId { return }
            continuation.yield(.invite(from: sender, name: senderName, invite: invite, at: at))
        case .error(_, let text):
            update { snap in
                snap.state = .error
                snap.lastError = text
            }
        case .pong(let srvAt):
            clock.recordPong(srvAt: srvAt, nowMs: nowProvider())
        }
    }

    private func handleJoined(_ joined: TogetherJoined) {
        if handleNameCollision(joined.participants) { return }
        renameAttempts = 0
        everJoined = true
        joinedThisAttempt = true
        attemptResolved = true
        failStreak = 0
        watchdogAt = nil
        var state = joined.state
        if var localized = joined.state, let srv = joined.srvAt {
            localized.updatedAt = clock.localize(srvAt: srv, nowMs: nowProvider())
            state = localized
        }
        let code = room
        update { snap in
            snap.state = .joined
            snap.room = code
            snap.participants = joined.participants
            snap.syncState = state
            snap.hostClientId = joined.hostClientId
            snap.started = joined.started
            snap.relayVersion = joined.relayVersion
        }
        reconcileHostClaim(joined.hostClientId)
        guard let current = state else { return }
        continuation.yield(.incomingState(current))
        let author = current.updatedBy
        let authorPresent = joined.participants.contains { $0.id == author }
        if let mediaId = current.mediaId, author != clientId, authorPresent {
            let hostMember = joined.participants.first(where: { $0.id == author })
            let hostName = hostMember?.name ?? "Host"
            let invite = TogetherPlayInvite(mediaId: mediaId, mediaType: current.episode != nil ? "series" : "movie",
                                            mediaTitle: current.mediaTitle ?? "Watch Together",
                                            releaseInfo: nil, posterUrl: current.posterUrl, backgroundUrl: nil,
                                            logoUrl: nil, episode: current.episode,
                                            proto: current.source != nil ? TogetherProtocol.version : nil,
                                            guestPick: current.guestPick == true ? true : nil, source: nil)
            continuation.yield(.invite(from: author, name: hostName, invite: invite, at: current.updatedAt))
        }
    }

    private func handleParticipantJoined(_ incoming: TogetherParticipant) {
        var next = snapshot.participants.filter { $0.id != incoming.id }
        next.append(incoming)
        if incoming.id != clientId && incoming.name == name && clientId > incoming.id && handleNameCollision(next) {
            return
        }
        update { $0.participants = next }
        if incoming.id != clientId && isOpen && room != nil {
            sendNow(.profile(name: name, avatar: avatar, color: color))
        }
        if incoming.id != clientId, isOpen, let invite = lastSentInvite, snapshot.hostClientId == clientId {
            sendNow(.invite(invite))
        }
    }

    private func handleParticipantLeft(_ leftID: String, _ leftName: String?) {
        let left = snapshot.participants.first { $0.id == leftID }
        let shown = leftName ?? left?.name ?? "Someone"
        let remaining = snapshot.participants.filter { $0.id != leftID }
        continuation.yield(.participantLeft(clientId: leftID, name: shown))
        update { $0.participants = remaining }
    }

    private func editParticipant(_ id: String, _ edit: (inout TogetherParticipant) -> Void) {
        var list = snapshot.participants
        for index in list.indices where list[index].id == id {
            edit(&list[index])
        }
        update { $0.participants = list }
    }

    private func reconcileHostClaim(_ hostID: String?) {
        guard let hostID = hostID else { return }
        claimedHost = hostID == clientId
    }

    /// Another member already uses this name: retry as "Name (2)", "Name (3)" and so on, then reconnect.
    private func handleNameCollision(_ participants: [TogetherParticipant]) -> Bool {
        if renameAttempts >= TogetherTiming.renameAttemptsMax { return false }
        let taken = Set(participants.filter { $0.id != clientId }.map { $0.name })
        if !taken.contains(name) { return false }
        var number = 2
        var candidate = originalName + " (" + String(number) + ")"
        while taken.contains(candidate) {
            number += 1
            candidate = originalName + " (" + String(number) + ")"
        }
        name = candidate
        renameAttempts += 1
        if isOpen && room != nil { sendNow(.leave) }
        intentional = true
        cleanup()
        intentional = false
        if room != nil { reconnectAt = nowProvider() + TogetherTiming.renameReconnectMs }
        return true
    }

    // MARK: Socket lifecycle

    private func openSocket() {
        guard let code = room else { return }
        attemptResolved = false
        joinedThisAttempt = false
        guard let url = TogetherRelay.websocketURL(relay: relayURL, room: code) else {
            failAttempt()
            return
        }
        let created = factory.makeSocket(url: url, delegate: self)
        socket = created
        isOpen = false
        watchdogAt = nowProvider() + TogetherTiming.connectTimeoutMs
    }

    private func handleSocketLost() {
        socket = nil
        isOpen = false
        nextPingAt = nil
        clock.reset()
        watchdogAt = nil
        if intentional || terminal { return }
        if joinedThisAttempt {
            joinedThisAttempt = false
            attemptResolved = false
        }
        failAttempt()
    }

    private func failAttempt() {
        if attemptResolved { return }
        attemptResolved = true
        watchdogAt = nil
        failStreak += 1
        let limit = everJoined
            ? TogetherTiming.failStreakLimit * TogetherTiming.failStreakAfterJoinMultiplier
            : TogetherTiming.failStreakLimit
        if failStreak >= limit {
            goTerminal()
            return
        }
        update { $0.state = .connecting }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        if intentional || terminal { return }
        if reconnectAt != nil { return }
        let delay = TogetherReconnect.delayMs(attempt: reconnectAttempt, jitter: jitterProvider())
        reconnectAttempt += 1
        reconnectAt = nowProvider() + delay
    }

    private func goTerminal() {
        terminal = true
        nextPingAt = nil
        watchdogAt = nil
        reconnectAt = nil
        dropSocket()
        update { snap in
            snap.state = .error
            snap.lastError = TogetherRelayDiagnosis.message(healthStatus: nil)
        }
    }

    /// Detaches the current socket first, so its late close callback is ignored.
    private func dropSocket() {
        let old = socket
        socket = nil
        isOpen = false
        old?.close()
    }

    private func cleanup() {
        nextPingAt = nil
        watchdogAt = nil
        reconnectAt = nil
        dropSocket()
    }

    private func isCurrent(_ candidate: TogetherSocket) -> Bool {
        guard let current = socket else { return false }
        return current === candidate
    }

    // MARK: Sending

    private func sendPing() {
        guard isOpen, room != nil else { return }
        clock.markPing(at: nowProvider())
        sendNow(.ping)
    }

    private func send(_ message: TogetherClientMessage) {
        if isOpen {
            sendNow(message)
            return
        }
        if message.isVolatile { return }
        if message.isState { outQueue.removeAll { $0.isState } }
        outQueue.append(message)
    }

    private func sendNow(_ message: TogetherClientMessage) {
        guard let current = socket, let code = room else { return }
        guard let text = TogetherJSON.text(from: message.json(room: code, clientId: clientId)) else { return }
        current.send(text)
    }

    private func flushOutQueue() {
        guard isOpen else { return }
        let queue = outQueue
        outQueue = []
        for message in queue { sendNow(message) }
    }

    private func update(_ patch: (inout TogetherRoomSnapshot) -> Void) {
        patch(&snapshot)
        continuation.yield(.snapshot(snapshot))
    }

    private static func capAvatar(_ avatar: String?) -> String? {
        guard let value = avatar else { return nil }
        return value.utf16.count > TogetherProtocol.avatarMaxUnits ? nil : value
    }
}

// MARK: - URLSession transport

/// A real relay connection on `URLSessionWebSocketTask`. The handshake is confirmed by a ping that completes, and
/// frames are pumped by a receive loop that stops at the first error.
@MainActor final class TogetherURLSessionSocket: TogetherSocket {
    private let task: URLSessionWebSocketTask
    private weak var delegate: TogetherSocketDelegate?
    private var finished = false

    init(task: URLSessionWebSocketTask, delegate: TogetherSocketDelegate) {
        self.task = task
        self.delegate = delegate
    }

    func start() {
        task.resume()
        task.sendPing { [weak self] error in
            let opened = error == nil
            Task { @MainActor in
                self?.handleHandshake(opened: opened)
            }
        }
        receiveNext()
    }

    func send(_ text: String) {
        task.send(.string(text)) { _ in }
    }

    func close() {
        finished = true
        task.cancel(with: .normalClosure, reason: nil)
    }

    private func handleHandshake(opened: Bool) {
        if finished { return }
        if opened {
            delegate?.togetherSocketDidOpen(self)
        } else {
            finish()
        }
    }

    private func finish() {
        if finished { return }
        finished = true
        delegate?.togetherSocketDidClose(self)
    }

    private func receiveNext() {
        task.receive { [weak self] result in
            var text: String?
            var failed = false
            switch result {
            case .success(let message):
                if case .string(let value) = message { text = value }
            case .failure:
                failed = true
            }
            let received = text
            Task { @MainActor in
                guard let socket = self else { return }
                if socket.finished { return }
                if failed {
                    socket.finish()
                    return
                }
                if let value = received {
                    socket.delegate?.togetherSocket(socket, didReceive: value)
                }
                socket.receiveNext()
            }
        }
    }
}

@MainActor struct TogetherURLSessionSocketFactory: TogetherSocketFactory {
    func makeSocket(url: URL, delegate: TogetherSocketDelegate) -> TogetherSocket {
        let task = URLSession.shared.webSocketTask(with: url)
        let socket = TogetherURLSessionSocket(task: task, delegate: delegate)
        socket.start()
        return socket
    }
}
