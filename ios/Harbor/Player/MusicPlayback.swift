import AVFoundation
import Foundation
import MediaPlayer
import Observation

enum MusicRepeat: String, CaseIterable, Identifiable, Sendable {
    case off, all, one
    var id: String { rawValue }
    var title: String {
        let key = switch self { case .off: "music.audio.replayOff"; case .all: "music.transport.repeatAll"; case .one: "music.transport.repeatOne" }
        return DesktopInterfaceText.value(key)
    }
}
struct MusicQueueOrigin: Equatable, Sendable { let kind: String; let id: String; let name: String }

@MainActor @Observable final class MusicPlayback {
    static let shared = MusicPlayback()
    private(set) var owner = "guest"
    private(set) var items: [MusicPlaybackItem] = []
    private(set) var currentItem: MusicPlaybackItem?
    private(set) var upcomingItems: [MusicPlaybackItem] = []
    private(set) var origin: MusicQueueOrigin?
    // Retain the original local callers without inventing local records for a stream.
    var queue: [MusicRecord] { items.compactMap(\.localRecord) }
    var current: MusicRecord? { currentItem?.localRecord }
    var currentTrack: MusicTrack? { currentItem?.track }
    private(set) var position = 0.0
    private(set) var duration = 0.0
    private(set) var paused = true
    private(set) var loaded = false
    private(set) var pausedForVideo = false
    private(set) var resolving = false
    var shuffle = UserDefaults.standard.bool(forKey: "music.shuffle") {
        didSet { UserDefaults.standard.set(shuffle, forKey: "music.shuffle"); if oldValue != shuffle { try? order.reset(); refreshUpcoming() } }
    }
    var repeatMode = MusicRepeat(rawValue: UserDefaults.standard.string(forKey: "music.repeat") ?? "off") ?? .off {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "music.repeat"); refreshUpcoming() }
    }
    var volume = MusicPlayback.savedVolume() {
        didSet { if volume.isFinite && (0...100).contains(volume) { UserDefaults.standard.set(volume, forKey: "music.volume") } }
    }
    var error: String?
    var scrobbleError: String?
    var phase: SpooktoberWorldMusicState.Phase {
        if currentItem == nil { return .idle }
        if error != nil { return .error }
        if resolving || !loaded && !ended { return .resolving }
        return paused || ended ? .paused : .playing
    }
    var worldState: SpooktoberWorldMusicState { .init(trackId: currentTrack?.id, originKind: origin?.kind, originId: origin?.id, phase: phase) }
    @ObservationIgnored private let engine: any MusicAudioEngineOperating
    @ObservationIgnored private let systemIntegration: Bool
    @ObservationIgnored private let recordPlayed: @MainActor (MusicTrack, String) -> Void
    @ObservationIgnored private var resolver: (any MusicPlaybackResolving)?
    @ObservationIgnored private let order = MusicQueueOrder()
    @ObservationIgnored private var resolution: MusicPlaybackResolution?
    @ObservationIgnored private var resolutionTask: Task<Void, Never>?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var request: UInt64 = 0
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var remoteReady = false
    @ObservationIgnored private var ended = false
    @ObservationIgnored private var desiredPause = false
    @ObservationIgnored private var priority: MusicTrack?
    @ObservationIgnored private var previousPosition: Double?
    @ObservationIgnored private var listened = 0.0
    @ObservationIgnored private var startedAt: UInt64 = 0
    @ObservationIgnored private var scrobbleStarted = false
    @ObservationIgnored private var recorded = false
    init(engine: any MusicAudioEngineOperating = MusicAudioEngine(), systemIntegration: Bool = true,
         recordPlayed: (@MainActor (MusicTrack, String) -> Void)? = nil) {
        self.engine = engine; self.systemIntegration = systemIntegration
        self.recordPlayed = recordPlayed ?? { track, owner in _ = MusicCollections.shared.recordPlayed(track.id, owner: owner) }
    }
    private static func savedVolume() -> Double {
        guard let value = UserDefaults.standard.object(forKey: "music.volume") as? Double, value.isFinite, (0...100).contains(value) else { return 82 }; return value
    }
    func attach(_ session: any MusicPlaybackResolving) {
        guard (try? session.validate()) != nil else { return }
        if owner != session.scope.owner || resolver.map({ $0.scope != session.scope || ObjectIdentifier($0) != ObjectIdentifier(session) }) == true { stop() }
        owner = session.scope.owner; resolver = session
    }
    func play(_ record: MusicRecord, queue: [MusicRecord], owner: String, continuingQueue: Bool = false) {
        do {
            _ = try MusicFileService.file(record, owner: owner)
            if self.owner != owner { stop(); resolver = nil }
            self.owner = owner
            admit(MusicPlaybackItem(record), queue: queue.map(MusicPlaybackItem.init), continuing: continuingQueue, origin: continuingQueue ? origin : nil)
        } catch { self.error = safeMessage(error) }
    }
    func play(_ track: MusicTrack, queue: [MusicTrack], using session: any MusicPlaybackResolving, origin: MusicQueueOrigin? = nil) {
        do {
            try session.validate(); attach(session)
            let values = queue.map { MusicPlaybackItem(track: $0, localRecord: session.localRecord($0)) }
            admit(.init(track: track, localRecord: session.localRecord(track)), queue: values, continuing: false, origin: origin)
        } catch { self.error = message(error) }
    }
    func play(_ item: MusicPlaybackItem) { admit(item, queue: items, continuing: true, origin: origin) }
    private func admit(_ item: MusicPlaybackItem, queue: [MusicPlaybackItem], continuing: Bool, origin: MusicQueueOrigin?) {
        var seen = Set<String>()
        items = Array(queue.filter { seen.insert($0.id).inserted }.prefix(500))
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        else { items = Array(items.prefix(499)); items.append(item) }
        if !continuing { try? order.reset(); priority = nil }
        self.origin = origin; start(item)
    }
    private func start(_ item: MusicPlaybackItem) {
        submitScrobbleIfEligible()
        request &+= 1; let token = request, loadedOwner = owner, session = resolver
        resolutionTask?.cancel(); poller?.cancel(); poller = nil; resolution = nil
        currentItem = item; loaded = false; resolving = true; paused = true; desiredPause = false
        pausedForVideo = false; ended = false; error = nil; scrobbleError = nil
        position = 0; duration = Double(item.track.durationSeconds)
        previousPosition = nil; listened = 0; scrobbleStarted = false; recorded = false
        startedAt = UInt64(max(0, Date().timeIntervalSince1970))
        refreshUpcoming(); if systemIntegration { remoteControls() }; nowPlaying()
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.request == token { self.resolutionTask = nil } }
            await engine.stop(request: token)
            do {
                try Task.checkCancellation()
                let resolved: MusicPlaybackResolution
                if let session { try session.validate(); resolved = try await session.resolve(item.track) }
                else if let record = item.localRecord {
                    resolved = .init(stream: .init(url: try MusicFileService.file(record, owner: loadedOwner), httpHeaders: [:], mimeType: "audio/*", bitrate: 0), valid: { [weak self] in self?.owner == loadedOwner })
                } else { throw HarborError(code: "music-source-required") }
                try Task.checkCancellation()
                guard request == token, resolved.valid() else { throw CancellationError() }
                if !desiredPause { try activateAudio() }
                resolution = resolved
                try await engine.open(resolved.stream, request: token, volume: volume, paused: desiredPause)
                try Task.checkCancellation()
                guard request == token, resolved.valid() else { throw CancellationError() }
                resolving = false; startPolling(token)
            } catch {
                await engine.stop(request: token)
                guard request == token else { return }
                resolving = false; loaded = false; paused = true
                if error is CancellationError { stop(); return }
                self.error = message(error); nowPlaying()
            }
        }
    }
    private func activateAudio() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
    }
    func togglePause() { setPaused(phase == .error ? false : phase == .resolving ? !desiredPause : !paused) }
    func setPaused(_ value: Bool) {
        guard currentItem != nil else { return }
        pausedForVideo = false; desiredPause = value
        if !value, ended || error != nil, let item = currentItem { start(item); return }
        if !value { try? activateAudio() }
        send(.paused(value))
    }
    func pauseForVideo() {
        guard currentItem != nil, phase == .resolving ? !desiredPause : !paused else { return }
        desiredPause = true; pausedForVideo = true; send(.paused(true))
    }
    func seek(_ value: Double) {
        guard value.isFinite, value >= 0 else { return }; send(.seek(min(value, max(0, duration))))
    }
    func changeVolume(_ value: Double) {
        guard value.isFinite else { return }; volume = min(100, max(0, value)); send(.volume(volume))
    }
    private func send(_ command: MusicAudioCommand) {
        let token = request
        Task { [weak self] in
            guard let self else { return }
            do { try await engine.command(command, request: token) }
            catch { if request == token { self.error = message(error) } }
        }
    }
    func next(automatic: Bool = false) {
        guard let currentItem, let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        do {
            let selected = try order.next(items.map(\.track), index: index, shuffle: shuffle, repeatMode: repeatMode, automatic: automatic, priority: priority)
            if !(automatic && repeatMode == .one) { priority = nil }
            if let selected, let item = items.first(where: { $0.id == MusicQueueOrder.key(selected) }) { start(item) }
            else if automatic { resolving = false; loaded = false; paused = true; ended = true; position = duration; nowPlaying() }
        } catch { self.error = message(error) }
    }
    func previous() {
        guard let currentItem, let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        if position > 3 { seek(0); return }
        do {
            if let previous = try order.previous(items.map(\.track), index: index, shuffle: shuffle), let item = items.first(where: { $0.id == MusicQueueOrder.key(previous) }) { start(item) }
            else { seek(0) }
        } catch { self.error = message(error) }
    }
    func enqueue(_ record: MusicRecord, owner: String, next: Bool = false) {
        guard self.owner == owner, currentItem != nil else { play(record, queue: [record], owner: owner); return }
        enqueue(.init(record), next: next)
    }
    func enqueue(_ track: MusicTrack, using session: any MusicPlaybackResolving, next: Bool = false) {
        attach(session)
        guard owner == session.scope.owner, currentItem != nil else { play(track, queue: [track], using: session); return }
        guard (try? session.validate()) != nil else { return }; resolver = session
        enqueue(.init(track: track, localRecord: session.localRecord(track)), next: next)
    }
    private func enqueue(_ item: MusicPlaybackItem, next: Bool) {
        guard let currentItem, currentItem.id != item.id else { return }
        items.removeAll { $0.id == item.id }
        guard items.count < 500 else { error = DesktopInterfaceText.value("music.mobile.queueLimit"); return }
        if next, let index = items.firstIndex(where: { $0.id == currentItem.id }) { items.insert(item, at: index + 1); priority = item.track }
        else { items.append(item) }; refreshUpcoming()
    }
    func moveAfterCurrent(_ record: MusicRecord) { if let item = items.first(where: { $0.localRecord?.id == record.id }) { moveAfterCurrent(item) } }
    func moveAfterCurrent(_ item: MusicPlaybackItem) { guard items.contains(where: { $0.id == item.id }) else { return }; enqueue(item, next: true) }
    func remove(_ record: MusicRecord) { if current?.id == record.id { stop() } else { items.removeAll { $0.localRecord?.id == record.id }; refreshUpcoming() } }
    func removeFromQueue(_ record: MusicRecord) { if let item = items.first(where: { $0.localRecord?.id == record.id }) { removeFromQueue(item) } }
    func removeFromQueue(_ item: MusicPlaybackItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let remaining = items.filter { $0.id != item.id }; items = remaining
        if priority.map(MusicQueueOrder.key) == item.id { priority = nil }
        if currentItem?.id == item.id {
            if remaining.isEmpty { stop() } else { start(remaining[min(index, remaining.count - 1)]) }
        } else { refreshUpcoming() }
    }
    private func refreshUpcoming() {
        guard let currentItem, let index = items.firstIndex(where: { $0.id == currentItem.id }) else { upcomingItems = []; return }
        do {
            var tracks = try order.upcoming(items.map(\.track), index: index, shuffle: shuffle, repeatMode: repeatMode)
            if repeatMode != .one, let priority, priority != currentItem.track { tracks.removeAll { MusicQueueOrder.key($0) == MusicQueueOrder.key(priority) }; tracks.insert(priority, at: 0) }
            let byKey = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            upcomingItems = tracks.compactMap { byKey[MusicQueueOrder.key($0)] }
        } catch { upcomingItems = []; self.error = message(error) }
    }
    func stopForAccount(_ owner: String) { if self.owner != owner { stop(); resolver = nil; self.owner = owner } }
    func reloadPreferences() {
        shuffle = UserDefaults.standard.bool(forKey: "music.shuffle")
        repeatMode = MusicRepeat(rawValue: UserDefaults.standard.string(forKey: "music.repeat") ?? "off") ?? .off
        changeVolume(Self.savedVolume())
    }
    func stop() {
        submitScrobbleIfEligible(); request &+= 1; let token = request
        resolutionTask?.cancel(); resolutionTask = nil; poller?.cancel(); poller = nil
        Task { await engine.stop(request: token) }
        items = []; currentItem = nil; upcomingItems = []; priority = nil; origin = nil; resolution = nil
        loaded = false; resolving = false; paused = true; pausedForVideo = false; position = 0; duration = 0; ended = false
        error = nil; scrobbleError = nil; previousPosition = nil; listened = 0; try? order.reset()
        if systemIntegration { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; setRemoteEnabled(false) }
    }
    private func startPolling(_ token: UInt64) {
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, request == token else { return }
                guard resolution?.valid() == true else { stop(); return }
                let events = await engine.read(request: token)
                guard request == token else { return }
                consume(events, token: token)
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }
    private func consume(_ events: [MusicAudioEvent], token: UInt64) {
        guard !events.isEmpty else { return }
        var natural = false
        for event in events {
            guard request == token else { return }
            switch event {
            case .started: loaded = false; position = 0; previousPosition = nil
            case .loaded:
                loaded = true; error = nil
                if !recorded, let track = currentTrack { recorded = true; recordPlayed(track, owner) }
            case .time(let value):
                guard value.isFinite, value >= 0, loaded else { continue }
                listened += MusicListening.increment(previous: previousPosition, current: value); previousPosition = value; position = value
            case .duration(let value): if value.isFinite && value >= 0 { duration = value }
            case .paused(let value): paused = value
            case .volume(let value): if value.isFinite && (0...100).contains(value) { volume = value }
            case .failed: error = message(HarborError(code: "music-player")); loaded = false; paused = true
            case .ended(let eof, let failed):
                submitScrobbleIfEligible(); natural = natural || eof
                if failed { error = message(HarborError(code: "music-player")); loaded = false; paused = true }
            }
        }
        nowPlaying()
        if natural { next(automatic: true) }
    }
    private func submitScrobbleIfEligible() {
        guard !scrobbleStarted, let track = currentTrack, let resolver, let resolution, resolution.valid(),
              MusicListening.shouldScrobble(listened: listened, duration: duration) else { return }
        scrobbleStarted = true; let start = startedAt, token = request
        Task { [weak self] in
            guard resolution.valid() else { return }
            do { try await resolver.scrobble(track, startedAt: start) }
            catch { if self?.request == token { self?.scrobbleError = DesktopInterfaceText.value("music.mobile.scrobbleError") } }
        }
    }
    private func message(_ failure: Error) -> String {
        if let error = failure as? HarborError, error.code == "music-source-required" { return DesktopInterfaceText.value("music.source.none") }
        return DesktopInterfaceText.value("music.error.playback")
    }
    private func nowPlaying() {
        guard systemIntegration, let track = currentTrack else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album ?? "", MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: paused ? 0.0 : 1.0]
    }
    private func setRemoteEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand, center.nextTrackCommand, center.previousTrackCommand, center.changePlaybackPositionCommand] { command.isEnabled = enabled }
    }
    private func remoteControls() {
        setRemoteEnabled(true); guard !remoteReady else { return }; remoteReady = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.setPaused(false) }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.setPaused(true) }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePause() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor in self?.seek(position) }; return .success
        }
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] notification in
            let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            if began { Task { @MainActor in self?.setPaused(true) } }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] notification in
            let unplugged = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            if unplugged { Task { @MainActor in self?.setPaused(true) } }
        })
    }
}
