import Foundation
import Observation

// The room state the UI reads, the outgoing commands, and the playback follower (`views/player/hooks/use-room-sync.ts`).
// The player stays in charge of the actual player; it calls `announcePlayback` on its heartbeat and state changes and
// applies the `PlaybackFollower.Decision` it gets from `followHostState`.

struct TogetherChatMessage: Equatable, Identifiable, Sendable {
    let id: Int
    let from: String
    let name: String
    let text: String
    let at: Double
}

struct TogetherIncomingInvite: Equatable, Sendable {
    let from: String
    let name: String
    let invite: TogetherPlayInvite
    let at: Double
}

struct TogetherIncomingSummon: Equatable, Sendable {
    let from: String
    let name: String
    let target: TogetherSummonTarget
    let at: Double
}

struct TogetherIncomingCommand: Equatable, Sendable {
    let id: Int
    let from: String
    let command: TogetherRoomCommand
}

struct TogetherHostLeaving: Equatable, Sendable {
    let from: String
    let name: String
    let at: Double
}

/// What the local player reports to the room.
struct TogetherPlaybackSnapshot: Equatable, Sendable {
    var mediaId: String
    var mediaTitle: String?
    var episode: TogetherEpisodeRef?
    var posterUrl: String?
    var positionSeconds: Double
    var playing: Bool
    var speed: Double?
    var source: TogetherSourceDescriptor?
}

/// The local player at the moment a host state arrives. `mediaMismatch` is true when the host plays another title.
struct TogetherLocalPlayback: Equatable, Sendable {
    var positionSeconds: Double
    var playing: Bool
    var rate: Double
    var durationSec: Double
    var bufferedSec: Double
    var mediaMismatch: Bool
}

/// `use-room-sync.ts` as a pure function. It keeps the last applied state time and the catch-up flag between calls.
struct PlaybackFollower: Equatable, Sendable {
    struct Decision: Equatable, Sendable {
        var setRate: Double?
        var seekTo: Double?
        var play = false
        var pause = false
        var foreignMedia = false
    }

    private(set) var lastAppliedAt: Double = 0
    private(set) var catchingUp = false

    mutating func reset() {
        lastAppliedAt = 0
        catchingUp = false
    }

    /// The incoming-state branch of `useRoomSync`: follow the host's position, rate and play state.
    mutating func follow(_ state: TogetherSyncState, selfID: String, local: TogetherLocalPlayback, nowMs: Double) -> Decision {
        var out = Decision()
        if state.updatedBy == selfID { return out }
        if local.mediaMismatch {
            out.foreignMedia = true
            return out
        }
        if state.mediaId == nil { return out }
        if state.updatedAt < lastAppliedAt { return out }
        lastAppliedAt = state.updatedAt

        let rate = TogetherSync.rate(state)
        if abs(rate - local.rate) > 0.01 { out.setRate = rate }

        let target = TogetherSync.target(state, durationSec: local.durationSec, nowMs: nowMs)
        let drift = abs(local.positionSeconds - target)
        let playStateChanged = state.playing != local.playing
        let driftTooBig = drift > TogetherSync.driftToleranceSec

        if catchingUp {
            if drift < TogetherSync.seekJumpSec {
                let nearEnd = local.durationSec > 0 && local.positionSeconds + local.bufferedSec >= local.durationSec - 0.5
                if !local.playing || (local.bufferedSec < 2.0 && !nearEnd) {
                    applyPlayState(state, local: local, into: &out)
                    return out
                }
            }
            catchingUp = false
        }

        if !playStateChanged && !driftTooBig { return out }
        out.seekTo = target
        if driftTooBig { catchingUp = true }
        applyPlayState(state, local: local, into: &out)
        return out
    }

    /// The first alignment after joining: rate, position and play state from the host, unconditionally.
    static func joinAlignment(_ state: TogetherSyncState, local: TogetherLocalPlayback, nowMs: Double) -> Decision? {
        if state.mediaId == nil || local.mediaMismatch { return nil }
        return Decision(setRate: TogetherSync.rate(state),
                        seekTo: TogetherSync.target(state, durationSec: local.durationSec, nowMs: nowMs),
                        play: state.playing, pause: !state.playing, foreignMedia: false)
    }

    private func applyPlayState(_ state: TogetherSyncState, local: TogetherLocalPlayback, into out: inout Decision) {
        if state.playing && !local.playing { out.play = true }
        if !state.playing && local.playing { out.pause = true }
    }
}

@MainActor @Observable final class TogetherSession {
    static let shared = TogetherSession()

    private(set) var snapshot = TogetherRoomSnapshot()
    private(set) var chat: [TogetherChatMessage] = []
    private(set) var incomingInvite: TogetherIncomingInvite?
    private(set) var incomingSummon: TogetherIncomingSummon?
    private(set) var incomingHostLeaving: TogetherHostLeaving?
    /// The latest command from another member. Use its `id` to react once per command.
    private(set) var lastCommand: TogetherIncomingCommand?
    /// The latest commands, oldest first, so a player that polls loses none when two arrive between polls.
    private(set) var recentCommands: [TogetherIncomingCommand] = []
    private(set) var lastInvite: TogetherLastInvite?

    private let preferences: TogetherPreferences
    private let factory: TogetherSocketFactory
    @ObservationIgnored private var client: TogetherClient?
    @ObservationIgnored private var relayInUse: String?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var commandSender: TogetherCommandSender
    @ObservationIgnored private var follower = PlaybackFollower()
    @ObservationIgnored private var sequence = 0

    init(preferences: TogetherPreferences = .shared, factory: TogetherSocketFactory = TogetherURLSessionSocketFactory()) {
        self.preferences = preferences
        self.factory = factory
        self.commandSender = TogetherCommandSender(seed: Int(TogetherClock.nowMs()))
    }

    // MARK: Derived

    var clientID: String { preferences.clientID }
    var relayURL: String { preferences.relayURL }
    var isHost: Bool { snapshot.hostClientId != nil && snapshot.hostClientId == preferences.clientID }
    var hostSource: TogetherHostSource? { TogetherRoomDerive.hostSource(snapshot) }
    var roomGuestPick: Bool {
        TogetherRoomDerive.guestPick(snapshot, clientId: preferences.clientID, lastInvite: lastInvite)
    }

    // MARK: Room commands

    /// Joins a room on the saved relay. False when no relay is saved or the code is empty.
    @discardableResult
    func join(code: String) -> Bool {
        let normalized = TogetherRoomCode.normalize(code)
        guard !normalized.isEmpty, activateRelay(), let active = client else { return false }
        chat = []
        commandSender.dispose()
        startTicking()
        active.join(room: normalized)
        return true
    }

    /// Creates a room with a fresh code and joins it. Returns the code, or nil when no relay is saved.
    @discardableResult
    func createRoom() -> String? {
        let code = TogetherRoomCode.generate()
        return join(code: code) ? code : nil
    }

    func leaveRoom() {
        client?.leave()
        chat = []
        incomingInvite = nil
        incomingSummon = nil
        incomingHostLeaving = nil
        commandSender.dispose()
        follower.reset()
        stopTicking()
    }

    func retry() {
        client?.retry()
    }

    func sendChat(_ text: String) {
        client?.sendChat(text)
    }

    func sendInvite(_ invite: TogetherPlayInvite) {
        var outgoing = invite
        outgoing.proto = TogetherProtocol.version
        outgoing.guestPick = preferences.guestsPick ? true : nil
        client?.sendInvite(outgoing)
    }

    func clearInvite() {
        client?.clearInvite()
    }

    func summon(_ target: TogetherSummonTarget) {
        client?.sendSummon(target)
    }

    func startWatching() {
        client?.startRoom()
    }

    func markReady(_ ready: Bool) {
        client?.markReady(ready)
    }

    func claimHost(fresh: Bool) {
        client?.claimHost(fresh: fresh)
    }

    func notifyHostLeaving() {
        client?.notifyHostLeaving()
    }

    func setDisplayName(_ value: String) {
        preferences.setDisplayName(value)
        client?.setName(preferences.displayName)
    }

    func dismissInvite() { incomingInvite = nil }
    func dismissSummon() { incomingSummon = nil }
    func dismissHostLeaving() { incomingHostLeaving = nil }

    // MARK: Playback

    /// Host heartbeat and change publisher. Desktop calls this about once a second and on each play, pause or seek.
    func announcePlayback(_ playback: TogetherPlaybackSnapshot) {
        let state = TogetherSyncState(mediaId: playback.mediaId, mediaTitle: playback.mediaTitle,
                                      episode: playback.episode, posterUrl: playback.posterUrl,
                                      positionSeconds: playback.positionSeconds, playing: playback.playing,
                                      speed: playback.speed, source: playback.source,
                                      guestPick: preferences.guestsPick ? true : nil,
                                      updatedAt: TogetherClock.nowMs(), updatedBy: preferences.clientID,
                                      hostClientId: nil)
        client?.publishState(state)
    }

    /// A local play, pause or seek to share. Seeks are coalesced; other commands flush a pending seek first.
    func sendCommand(_ command: TogetherRoomCommand) {
        let outgoing = commandSender.send(command, nowMs: TogetherClock.nowMs())
        for item in outgoing { client?.sendCommand(item) }
    }

    /// Guest side: the player's state against the host's latest state. Apply the returned decision in this order:
    /// rate, seek, then play or pause.
    func followHostState(_ state: TogetherSyncState, local: TogetherLocalPlayback) -> PlaybackFollower.Decision {
        follower.follow(state, selfID: preferences.clientID, local: local, nowMs: TogetherClock.nowMs())
    }

    /// Guest side, once after joining or changing media.
    func joinAlignment(_ state: TogetherSyncState, local: TogetherLocalPlayback) -> PlaybackFollower.Decision? {
        PlaybackFollower.joinAlignment(state, local: local, nowMs: TogetherClock.nowMs())
    }

    /// Call after the player applies a decision, so its own echo is not sent back (`SYNC_SUPPRESS_MS`).
    func suppressOutgoing() {
        client?.suppressOutgoing(forMs: TogetherSync.suppressMs)
    }

    func resetFollower() {
        follower.reset()
    }

    /// Probes `/health` after a terminal failure and stores the Desktop message for it.
    func probeRelayHealth() async {
        guard let active = client else { return }
        guard let url = URL(string: TogetherRelay.healthBase(preferences.relayURL) + "/health") else { return }
        var status: Int?
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            status = (response as? HTTPURLResponse)?.statusCode
        } catch {
            status = nil
        }
        active.applyHealthProbe(status: status)
    }

    // MARK: Events

    func apply(_ event: TogetherRoomEvent) {
        switch event {
        case .snapshot(let next):
            snapshot = next
            if next.state == .disconnected {
                incomingInvite = nil
                incomingSummon = nil
                incomingHostLeaving = nil
            }
        case .incomingState:
            break
        case .incomingCommand(let sender, let command):
            sequence += 1
            let incoming = TogetherIncomingCommand(id: sequence, from: sender, command: command)
            lastCommand = incoming
            recentCommands.append(incoming)
            if recentCommands.count > 16 { recentCommands.removeFirst(recentCommands.count - 16) }
        case .chat(let sender, let name, let text, let at):
            sequence += 1
            chat.append(TogetherChatMessage(id: sequence, from: sender, name: name, text: text, at: at))
            let overflow = chat.count - TogetherProtocol.chatHistoryLimit
            if overflow > 0 { chat.removeFirst(overflow) }
        case .invite(let sender, let name, let invite, let at):
            lastInvite = TogetherLastInvite(key: TogetherRoomDerive.inviteKey(invite), at: TogetherClock.nowMs(),
                                            proto: invite.proto ?? 0, guestPick: invite.guestPick == true)
            incomingSummon = nil
            incomingInvite = TogetherIncomingInvite(from: sender, name: name, invite: invite, at: at)
        case .hostLeaving(let sender, let name, let at):
            incomingHostLeaving = TogetherHostLeaving(from: sender, name: name, at: at)
        case .summon(let sender, let name, let target, let at):
            incomingInvite = nil
            incomingSummon = TogetherIncomingSummon(from: sender, name: name, target: target, at: at)
        case .participantLeft, .started:
            break
        }
    }

    // MARK: Internals

    /// Creates or replaces the client when the saved relay changed. False when no relay is saved.
    private func activateRelay() -> Bool {
        let relay = preferences.relayURL
        if relay.isEmpty {
            tearDownClient()
            return false
        }
        if client != nil && relayInUse == relay { return true }
        tearDownClient()
        let next = TogetherClient(relayURL: relay, clientId: preferences.clientID, name: preferences.displayName,
                                  factory: factory)
        client = next
        relayInUse = relay
        eventTask = Task { [weak self] in
            for await event in next.events {
                guard let session = self else { return }
                session.apply(event)
            }
        }
        return true
    }

    private func tearDownClient() {
        stopTicking()
        eventTask?.cancel()
        eventTask = nil
        client?.leave()
        client = nil
        relayInUse = nil
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let session = self else { return }
                session.tickOnce()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tickOnce() {
        client?.tick()
        let outgoing = commandSender.tick(nowMs: TogetherClock.nowMs())
        for item in outgoing { client?.sendCommand(item) }
    }
}
