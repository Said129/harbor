import SwiftUI

/// What Watch Together needs from the local player. `PlayerStateAdapter` backs it with the real player and tests use a fake.
@MainActor protocol TogetherPlayerAdapter: AnyObject {
    /// A video is loaded and has not ended or failed.
    var loaded: Bool { get }
    /// The first frame is on screen with a known duration (Desktop's `selfFrameReady`).
    var frameReady: Bool { get }
    var position: Double { get }
    var duration: Double { get }
    var playing: Bool { get }
    var rate: Double { get }
    var bufferedSeconds: Double { get }
    func setRate(_ rate: Double)
    func seek(to seconds: Double)
    func play()
    func pause()
    /// A one-line message over the video, or nil to remove the one this sync showed.
    func showNotice(_ text: String?)
}

@MainActor final class PlayerStateAdapter: TogetherPlayerAdapter {
    private let state: PlayerState
    private var shown: String?

    init(state: PlayerState) { self.state = state }

    var loaded: Bool { state.loaded && !state.ended && state.error == nil }
    var frameReady: Bool { state.loaded && state.duration > 0 && state.videoWidth > 0 && state.videoHeight > 0 }
    var position: Double { state.position }
    var duration: Double { state.duration }
    var playing: Bool { !state.paused }
    var rate: Double { state.speed }
    /// Seconds of video already read ahead of the position. Unknown counts as plenty, so catching up can finish.
    var bufferedSeconds: Double { state.cacheEnd.map { max(0, $0 - state.position) } ?? 30 }

    func setRate(_ rate: Double) { state.controller?.set("speed", String(rate)) }
    func seek(to seconds: Double) { state.controller?.run(["seek", String(seconds), "absolute+exact"]) }
    func play() { state.controller?.set("pause", "no") }
    func pause() { state.controller?.set("pause", "yes") }

    func showNotice(_ text: String?) {
        if let text {
            shown = text
            state.playbackIssue = text
        } else if let shown, state.playbackIssue == shown {
            state.playbackIssue = nil
            self.shown = nil
        }
    }
}

/// The player side of Watch Together (`views/player/hooks/use-room-sync.ts`). One driver lives as long as one playback. It runs
/// on a short tick: the host publishes its position about once a second, applies the guests' play, pause and seek commands, and
/// starts the room when it first presses play; a guest follows the host's state and sends its own play, pause and seek to the host
/// instead of fighting it. Before the room has started both sides hold the video paused, as Desktop's lobby does.
@MainActor final class TogetherPlayerSyncDriver {
    struct Identity: Equatable {
        var mediaId: String
        var title: String?
        var poster: String?
        var episode: TogetherEpisodeRef?
    }

    static let everyoneLoadedNotice = "Everyone is loaded in. Press play to start watching."
    static let waitingForHostNotice = "Waiting for the host to start"
    /// A pause or play inside this window after the lobby hold is the hold itself settling, not the host's choice.
    static let lobbyHoldSettleMs = 1_000.0
    /// A position change beyond what playing explains by more than this is the viewer seeking.
    static let seekJumpSec = 2.5
    static let lobbySeedToleranceSec = 1.5

    private struct Sample {
        var position: Double
        var at: Double
        var playing: Bool
    }

    private let together: TogetherSession
    private let player: TogetherPlayerAdapter
    private let identity: Identity
    private let now: () -> Double

    private var joinedRoom: String?
    private var readySent = false
    private var localStarted = false
    private var lobbyHeldAt: Double?
    private var lobbySeeded = false
    private var lobbySeedAt: Double = 0
    private var noticeShown = false
    private var initialAlignDone = false
    private var lastSeenStateAt: Double = 0
    private var lastCommandID = 0
    private var lastSeekSeq: [String: Int] = [:]
    private var pendingSeek: (position: Double, due: Double)?
    private var lastHeartbeat: Double = 0
    private var applyingUntil: Double = 0
    /// When this guest last sent a command. Host states older than that still describe the video before the command.
    private var commandSentAt: Double = 0
    private var observed: Sample?

    init(together: TogetherSession = .shared, player: TogetherPlayerAdapter, identity: Identity,
         now: @escaping () -> Double = { TogetherClock.nowMs() }) {
        self.together = together
        self.player = player
        self.identity = identity
        self.now = now
    }

    /// One pass. Returns whether a room is joined, so the caller can poll faster while one is.
    @discardableResult
    func tick() -> Bool {
        let snapshot = together.snapshot
        guard snapshot.state == .joined else {
            if joinedRoom != nil { leaveRoom() }
            return false
        }
        let room = snapshot.room ?? ""
        if joinedRoom != room { enter(room) }
        guard player.loaded else { return true }
        let nowMs = now()
        if !readySent, player.frameReady {
            readySent = true
            together.markReady(true)
        }
        guard snapshot.started || localStarted else {
            lobby(snapshot, nowMs: nowMs)
            return true
        }
        if noticeShown {
            noticeShown = false
            player.showNotice(nil)
        }
        let host = together.isHost
        if host { applyCommands(nowMs: nowMs) }
        follow(snapshot, host: host, nowMs: nowMs)
        detectLocalChange(host: host, nowMs: nowMs)
        if host { heartbeat(nowMs: nowMs) }
        return true
    }

    /// The player is closing: stop counting as loaded in the room.
    func stop() {
        guard joinedRoom != nil else { return }
        together.markReady(false)
        player.showNotice(nil)
        joinedRoom = nil
    }

    // MARK: Room entry and exit

    private func enter(_ room: String) {
        joinedRoom = room
        readySent = false
        localStarted = false
        lobbyHeldAt = nil
        lobbySeeded = false
        lobbySeedAt = 0
        initialAlignDone = false
        lastSeenStateAt = 0
        lastSeekSeq = [:]
        pendingSeek = nil
        lastHeartbeat = 0
        applyingUntil = 0
        commandSentAt = 0
        observed = nil
        lastCommandID = together.recentCommands.last?.id ?? 0
        together.resetFollower()
    }

    private func leaveRoom() {
        joinedRoom = nil
        player.showNotice(nil)
        noticeShown = false
        pendingSeek = nil
        observed = nil
    }

    // MARK: Lobby

    private func lobby(_ snapshot: TogetherRoomSnapshot, nowMs: Double) {
        observed = nil
        let hold = lobbyHeldAt
        if hold == nil { lobbyHeldAt = nowMs }
        if together.isHost {
            if !lobbySeeded, player.duration > 0 {
                lobbySeeded = true
                announce(playing: false)
            }
            let everyone = !snapshot.participants.isEmpty && snapshot.participants.allSatisfy { $0.ready }
            show(everyone ? Self.everyoneLoadedNotice : nil)
            guard let heldAt = hold else {
                if player.playing { player.pause() }
                return
            }
            if nowMs - heldAt <= Self.lobbyHoldSettleMs {
                if player.playing { player.pause() }
            } else if player.playing, player.frameReady {
                // The host pressed play: that starts the room for everyone.
                localStarted = true
                lastHeartbeat = 0
                together.startWatching()
                show(nil)
            }
            return
        }
        show(Self.waitingForHostNotice)
        if let seed = snapshot.syncState, seed.updatedAt != lobbySeedAt, seed.updatedBy == snapshot.hostClientId,
           !seed.playing, !TogetherRoomDerive.isDifferentMedia(seed, mediaId: identity.mediaId, episode: identity.episode),
           abs(player.position - seed.positionSeconds) > Self.lobbySeedToleranceSec {
            lobbySeedAt = seed.updatedAt
            player.seek(to: seed.positionSeconds)
        }
        if player.playing { player.pause() }
    }

    private func show(_ key: String?) {
        guard let key else {
            if noticeShown {
                noticeShown = false
                player.showNotice(nil)
            }
            return
        }
        noticeShown = true
        player.showNotice(DesktopInterfaceText.value(key))
    }

    // MARK: Host: commands from guests

    private func applyCommands(nowMs: Double) {
        for item in together.recentCommands where item.id > lastCommandID {
            lastCommandID = item.id
            switch item.command {
            case .play:
                flushPendingSeek()
                player.play()
                lastHeartbeat = 0
            case .pause:
                flushPendingSeek()
                player.pause()
                lastHeartbeat = 0
            case .seek(let position, let seq, _):
                if let seq {
                    if let last = lastSeekSeq[item.from], seq <= last { continue }
                    lastSeekSeq[item.from] = seq
                }
                pendingSeek = (position, nowMs + TogetherSync.seekApplyDebounceMs)
            }
        }
        if let pending = pendingSeek, nowMs >= pending.due {
            pendingSeek = nil
            applySeek(pending.position)
        }
    }

    private func flushPendingSeek() {
        guard let pending = pendingSeek else { return }
        pendingSeek = nil
        applySeek(pending.position)
    }

    private func applySeek(_ position: Double) {
        guard player.duration > 0 else { return }
        player.seek(to: max(0, min(position, player.duration - 1)))
        lastHeartbeat = 0
    }

    // MARK: Following the host

    private func follow(_ snapshot: TogetherRoomSnapshot, host: Bool, nowMs: Double) {
        guard let incoming = snapshot.syncState, incoming.updatedBy != together.clientID,
              incoming.updatedAt != lastSeenStateAt else { return }
        let mismatch = TogetherRoomDerive.isDifferentMedia(incoming, mediaId: identity.mediaId, episode: identity.episode)
        let local = TogetherLocalPlayback(positionSeconds: player.position, playing: player.playing, rate: player.rate,
                                          durationSec: player.duration, bufferedSec: player.bufferedSeconds,
                                          mediaMismatch: mismatch)
        lastSeenStateAt = incoming.updatedAt
        if incoming.updatedAt < commandSentAt { return }
        if !host && !initialAlignDone {
            guard incoming.mediaId != nil, !mismatch else { return }
            initialAlignDone = true
            if let decision = together.joinAlignment(incoming, local: local) { apply(decision, nowMs: nowMs) }
            return
        }
        apply(together.followHostState(incoming, local: local), nowMs: nowMs)
    }

    /// Order matters: rate, then seek, then play or pause.
    private func apply(_ decision: PlaybackFollower.Decision, nowMs: Double) {
        if decision.foreignMedia { return }
        var changed = false
        if let rate = decision.setRate {
            player.setRate(rate)
            changed = true
        }
        if let target = decision.seekTo {
            player.seek(to: target)
            changed = true
        }
        if decision.play {
            player.play()
            changed = true
        } else if decision.pause {
            player.pause()
            changed = true
        }
        guard changed else { return }
        applyingUntil = nowMs + TogetherSync.suppressMs
        together.suppressOutgoing()
        observed = nil
    }

    // MARK: The viewer's own play, pause and seek

    /// A change the follower did not make is the viewer's. The host publishes it at once; a guest sends it to the host as a
    /// command, and the host's next state brings the guest back in line.
    private func detectLocalChange(host: Bool, nowMs: Double) {
        let playing = player.playing
        let position = player.position
        let before = observed
        observed = Sample(position: position, at: nowMs, playing: playing)
        guard nowMs >= applyingUntil, let before else { return }
        if playing != before.playing {
            if host {
                lastHeartbeat = 0
            } else {
                commandSentAt = nowMs
                together.sendCommand(playing ? .play : .pause)
            }
            return
        }
        let advance = position - before.position
        let explained = before.playing ? max(0, nowMs - before.at) / 1000 * max(player.rate, 0.1) : 0
        guard advance > explained + Self.seekJumpSec || advance < -Self.seekJumpSec else { return }
        if host {
            lastHeartbeat = 0
        } else {
            commandSentAt = nowMs
            together.sendCommand(.seek(positionSeconds: position, seq: nil, at: nil))
        }
    }

    // MARK: Host: heartbeat

    private func heartbeat(nowMs: Double) {
        guard nowMs - lastHeartbeat >= TogetherSync.heartbeatMs else { return }
        guard player.duration > 0, player.position > 0 else { return }
        lastHeartbeat = nowMs
        announce(playing: player.playing)
    }

    private func announce(playing: Bool) {
        together.announcePlayback(TogetherPlaybackSnapshot(
            mediaId: identity.mediaId, mediaTitle: identity.title, episode: identity.episode, posterUrl: identity.poster,
            positionSeconds: player.position, playing: playing, speed: player.rate,
            source: TogetherSourceBuilder.descriptor(from: nil, durationSec: player.duration)))
    }
}

/// Keeps the player in step with a Watch Together room. A modifier of its own, like `LiveReconnectDriver`, so the player's long
/// modifier chain stays quick to type-check. Nothing happens unless a room is joined.
struct TogetherPlayerSync: ViewModifier {
    let state: PlayerState
    let session: PlaybackSession
    let media: Media?

    func body(content: Content) -> some View {
        content.task(id: session.id) { await run() }
    }

    @MainActor private func run() async {
        let driver = TogetherPlayerSyncDriver(player: PlayerStateAdapter(state: state), identity: identity)
        while !Task.isCancelled {
            let inRoom = driver.tick()
            try? await Task.sleep(for: .milliseconds(inRoom ? 250 : 1_000))
        }
        driver.stop()
    }

    private var identity: TogetherPlayerSyncDriver.Identity {
        let target = session.target
        var episode: TogetherEpisodeRef?
        if let season = target.season, let number = target.episode { episode = TogetherEpisodeRef(season: season, episode: number) }
        return .init(mediaId: target.id, title: media?.name, poster: media?.poster, episode: episode)
    }
}
