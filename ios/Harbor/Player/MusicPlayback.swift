import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

enum MusicRepeat: String, CaseIterable, Identifiable, Sendable {
    case off, all, one
    var id: String { rawValue }
    var title: String {
        let key = switch self { case .off: "music.audio.replayOff"; case .all: "music.transport.repeatAll"; case .one: "music.transport.repeatOne" }
        return DesktopInterfaceText.value(key)
    }
}
struct MusicQueueOrigin: Codable, Equatable, Sendable { let kind: String; let id: String; let name: String }

@MainActor @Observable final class MusicPlayback {
    static let shared = MusicPlayback(checkpoints: MusicSessionFileStore.shared)
    private(set) var owner = "guest"
    private(set) var items: [MusicPlaybackItem] = [] {
        didSet { queueRevision = UUID(); cancelQueueContinuation() }
    }
    private(set) var currentItem: MusicPlaybackItem?
    private(set) var upcomingItems: [MusicPlaybackItem] = []
    private(set) var origin: MusicQueueOrigin?
    private(set) var queueContinuationMode = MusicQueueContinuationMode.context
    private(set) var queueContinuationLoading = false
    private(set) var queueContinuationNotice: String?
    // Retain the original local callers without inventing local records for a stream.
    var queue: [MusicRecord] { items.compactMap(\.localRecord) }
    var current: MusicRecord? { currentItem?.localRecord }
    var currentTrack: MusicTrack? { currentItem?.track }
    var lyricsClient: MusicLyricsClient? { (resolver as? MusicPlaybackSession)?.lyrics }
    var playbackSession: MusicPlaybackSession? { resolver as? MusicPlaybackSession }
    private(set) var audioPlan = MusicAudioPlan.defaults
    private(set) var audioEffects = MusicAudioEffects()
    private(set) var audioApplying = false
    var volumeMaximum: Double { audioPlan.volumeMaximum }
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
        didSet { if volume.isFinite && (0...500).contains(volume) { UserDefaults.standard.set(volume, forKey: "music.volume") } }
    }
    var error: String?
    var scrobbleError: String?
    var phase: SpooktoberWorldMusicState.Phase {
        if currentItem == nil { return .idle }
        if error != nil { return .error }
        if resolving || !loaded && !ended && !restored { return .resolving }
        return paused || ended ? .paused : .playing
    }
    var worldState: SpooktoberWorldMusicState { .init(trackId: currentTrack?.id, originKind: origin?.kind, originId: origin?.id, phase: phase) }
    @ObservationIgnored private let engine: any MusicAudioEngineOperating
    @ObservationIgnored private let systemIntegration: Bool
    @ObservationIgnored private let recordPlayed: @MainActor (MusicTrack, String) -> Void
    @ObservationIgnored private var resolver: (any MusicPlaybackResolving)?
    @ObservationIgnored private let order = MusicQueueOrder()
    @ObservationIgnored private var queueContinuationTask: Task<Void, Never>?
    @ObservationIgnored private var queueContinuationRun: UUID?
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
    @ObservationIgnored private var pendingResume: Double?
    @ObservationIgnored private var checkpointTarget: Double?
    @ObservationIgnored private let checkpoints: (any MusicSessionPersisting)?
    private(set) var queueRevision = UUID()
    @ObservationIgnored private var checkpointQueueRevision: UUID?
    @ObservationIgnored private var checkpointQueue: [MusicTrack] = []
    @ObservationIgnored private var lastCheckpoint = Date.distantPast
    @ObservationIgnored private var checkpointWrite: Task<Void, Never>?
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var restoreScope: PluginExecutionScope?
    private(set) var effectLease: UUID?
    @ObservationIgnored private var effectRevision = UUID()
    @ObservationIgnored private var meterUsers = Set<UUID>()
    @ObservationIgnored private var meterRevision: UInt64 = 0
    @ObservationIgnored private var lastSystemClock = Date.distantPast
    private(set) var restored = false
    init(engine: any MusicAudioEngineOperating = MusicAudioEngine(), systemIntegration: Bool = true,
         recordPlayed: (@MainActor (MusicTrack, String) -> Void)? = nil, checkpoints: (any MusicSessionPersisting)? = nil) {
        self.engine = engine; self.systemIntegration = systemIntegration
        self.checkpoints = checkpoints
        self.recordPlayed = recordPlayed ?? { track, owner in _ = MusicCollections.shared.recordPlayed(track.id, owner: owner) }
        queueContinuationMode = Self.savedContinuationMode(owner: owner)
        if systemIntegration {
            tokens.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.saveCheckpoint(force: true) }
            })
        }
    }
    private static func savedVolume() -> Double {
        guard let value = UserDefaults.standard.object(forKey: "music.volume") as? Double, value.isFinite, (0...500).contains(value) else { return 82 }; return value
    }
    private static func savedContinuationMode(owner: String) -> MusicQueueContinuationMode {
        MusicQueueContinuationMode(rawValue: UserDefaults.standard.string(forKey: MusicQueueContinuationRules.preferenceKey(owner: owner)) ?? "context") ?? .context
    }
    private func loadContinuationMode(owner: String) {
        queueContinuationMode = Self.savedContinuationMode(owner: owner)
        queueContinuationNotice = nil
    }
    private func cancelQueueContinuation() {
        queueContinuationRun = nil
        queueContinuationTask?.cancel(); queueContinuationTask = nil
        queueContinuationLoading = false
        queueContinuationNotice = nil
    }
    func attach(_ session: any MusicPlaybackResolving, restoring saved: MusicSessionSnapshot? = nil) {
        guard (try? session.validate()) != nil else { return }
        let previousOwner = owner
        if owner != session.scope.owner || resolver.map({ $0.scope != session.scope || ObjectIdentifier($0) != ObjectIdentifier(session) }) == true { stop() }
        owner = session.scope.owner; resolver = session
        if previousOwner != owner { loadContinuationMode(owner: owner) }
        restoreCheckpoint(using: session, saved: saved)
    }
    func play(_ record: MusicRecord, queue: [MusicRecord], owner: String, continuingQueue: Bool = false) {
        do {
            _ = try MusicFileService.file(record, owner: owner)
            let previousOwner = self.owner
            if self.owner != owner { stop(); resolver = nil }
            self.owner = owner
            if previousOwner != owner { loadContinuationMode(owner: owner) }
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
        items = queue.filter { seen.insert($0.id).inserted }
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        else { items.append(item) }
        if !continuing { try? order.reset(); priority = nil }
        self.origin = origin; start(item)
    }
    private func start(_ item: MusicPlaybackItem, resuming resumeAt: Double = 0, paused startPaused: Bool = false) {
        cancelQueueContinuation()
        submitScrobbleIfEligible()
        restoreTask?.cancel(); restoreTask = nil; restored = false
        request &+= 1; let token = request, loadedOwner = owner, session = resolver
        resolution?.onStopped?()
        resolutionTask?.cancel(); poller?.cancel(); poller = nil; resolution = nil
        currentItem = item; loaded = false; resolving = true; paused = true; desiredPause = startPaused
        pendingResume = resumeAt.isFinite && resumeAt > 0 ? resumeAt : nil
        checkpointTarget = checkpoints == nil ? nil : pendingResume
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
                if let recording = resolved.recording {
                    let replacement = MusicPlaybackItem(track: recording, localRecord: session?.localRecord(recording))
                    if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = replacement }
                    currentItem = replacement; duration = Double(recording.durationSeconds); refreshUpcoming()
                }
                let preferences = (session as? MusicPlaybackSession)?.audio
                let processingRevision = preferences?.revision
                let processingEffects = effectRevision
                let plan = try await preferences?.plan(effects: audioEffects) ?? .defaults
                guard request == token, resolved.valid() else { throw CancellationError() }
                try await engine.configure(plan, request: token)
                try Task.checkCancellation()
                guard request == token, resolved.valid() else { throw CancellationError() }
                audioPlan = plan
                if !desiredPause { try activateAudio() }
                resolution = resolved
                try await engine.open(resolved.stream, request: token, volume: volume, paused: desiredPause)
                try Task.checkCancellation()
                guard request == token, resolved.valid() else { throw CancellationError() }
                if preferences?.revision != processingRevision || effectRevision != processingEffects, let preferences {
                    let latest = try await preferences.plan(effects: audioEffects)
                    guard request == token, resolved.valid() else { throw CancellationError() }
                    try await engine.configure(latest, request: token)
                    guard request == token, resolved.valid() else { throw CancellationError() }
                    audioPlan = latest
                }
                try Task.checkCancellation()
                guard request == token, resolved.valid() else { throw CancellationError() }
                resolving = false; startPolling(token)
            } catch {
                await engine.stop(request: token)
                guard request == token else { return }
                resolution?.onStopped?(); resolution = nil
                resolving = false; loaded = false; paused = true
                if error is CancellationError { stop(); return }
                self.error = message(error); nowPlaying()
            }
        }
    }
    private func activateAudio() throws {
        SpotifyMusicService.active?.pauseForVideo()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        if audioPlan.settings.sampleRate > 0 { try AVAudioSession.sharedInstance().setPreferredSampleRate(Double(audioPlan.settings.sampleRate)) }
        try AVAudioSession.sharedInstance().setActive(true)
    }
    func togglePause() { setPaused(phase == .error ? false : phase == .resolving ? !desiredPause : !paused) }
    func setPaused(_ value: Bool) {
        guard currentItem != nil else { return }
        pausedForVideo = false; desiredPause = value
        if restored {
            if !value, let item = currentItem { start(item, resuming: position) }
            return
        }
        if !value, ended || error != nil, let item = currentItem { start(item); return }
        if !value { try? activateAudio() }
        send(.paused(value))
    }
    func pauseForVideo() {
        guard currentItem != nil, phase == .resolving ? !desiredPause : !paused else { return }
        desiredPause = true; pausedForVideo = true; send(.paused(true))
    }
    func seek(_ value: Double) {
        guard value.isFinite, value >= 0 else { return }
        if restored { position = duration > 0 ? min(value, duration) : value; saveCheckpoint(force: true); return }
        checkpointTarget = nil
        send(.seek(min(value, max(0, duration))))
    }
    func changeVolume(_ value: Double) {
        guard value.isFinite else { return }; volume = min(volumeMaximum, max(0, value)); send(.volume(volume))
    }
    func applyAudio(_ options: MusicAudioOptions, using session: MusicPlaybackSession) async throws {
        try session.validate()
        guard !audioApplying, let preferences = session.audio else { throw HarborError(code: "music-audio-unavailable") }
        audioApplying = true; defer { audioApplying = false }
        let token = request, effectsVersion = effectRevision
        let effects = owner == session.scope.owner ? audioEffects : .init()
        let plan = try await preferences.plan(options, effects: effects)
        guard plan.settings.supported else { throw HarborError(code: "music-audio-unavailable") }
        try session.validate()
        guard token == request, effectsVersion == effectRevision else { throw CancellationError() }
        if owner == session.scope.owner, resolver.map({ ObjectIdentifier($0) == ObjectIdentifier(session) }) == true, currentItem != nil, !resolving {
            let previous = audioPlan
            try await engine.configure(plan, request: token)
            try session.validate()
            guard token == request else { throw CancellationError() }
            do { try preferences.save(plan) }
            catch { try? await engine.configure(previous, request: token); throw error }
            audioPlan = plan; changeVolume(volume)
            nowPlaying()
        } else { try preferences.save(plan) }
    }
    func beginEffects(using session: MusicPlaybackSession, lease: UUID = UUID()) throws -> UUID {
        try session.validate()
        guard owner == session.scope.owner, resolver.map({ ObjectIdentifier($0) == ObjectIdentifier(session) }) == true,
              currentItem != nil, !audioApplying, !resolving else { throw CancellationError() }
        effectLease = lease; return lease
    }
    func applyEffects(_ effects: MusicAudioEffects, lease: UUID, using session: MusicPlaybackSession) async throws {
        try session.validate()
        guard effectLease == lease, owner == session.scope.owner,
              resolver.map({ ObjectIdentifier($0) == ObjectIdentifier(session) }) == true,
              currentItem != nil, !resolving, !audioApplying, let preferences = session.audio else { throw CancellationError() }
        audioApplying = true; defer { audioApplying = false }
        let token = request
        let plan = try await preferences.plan(effects: effects)
        try session.validate()
        guard token == request, effectLease == lease, MusicAudioRuntime.supports(plan) else { throw CancellationError() }
        if loaded {
            guard resolution?.valid() == true else { throw CancellationError() }
            try await engine.configure(plan, request: token)
        }
        // Once the serialized engine has acknowledged this plan, retain that
        // exact state even if its view's next edit has already been queued.
        guard token == request, effectLease == lease else { throw CancellationError() }
        audioEffects = plan.effects; effectRevision = UUID(); audioPlan = plan
        nowPlaying()
    }
    func endEffects(_ lease: UUID, using session: MusicPlaybackSession) async {
        while true {
            guard effectLease == lease, owner == session.scope.owner, (try? session.validate()) != nil else { return }
            if resolving {
                effectLease = nil; audioEffects = .init(); effectRevision = UUID()
                return
            }
            if !audioApplying { break }
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
        }
        guard effectLease == lease, !audioApplying, !resolving else { return }
        do { try await applyEffects(.init(), lease: lease, using: session) }
        catch { Diagnostics.shared.recordFailure(HarborError(code: "music-effects")) }
        if effectLease == lease { effectLease = nil }
    }
    func audioSignal() async -> MusicAudioSignal? {
        let token = request, value = await engine.signal(request: request)
        guard request == token, resolution?.valid() == true else { return nil }
        return value
    }
    /// Read-only count of live analysis consumers, for bounded diagnostics.
    var meterConsumerCount: Int { meterUsers.count }
    func acquireMeter() -> UUID {
        if meterUsers.isEmpty { meterRevision &+= 1 }
        let lease = UUID(); meterUsers.insert(lease)
        return lease
    }
    func releaseMeter(_ lease: UUID) async {
        guard meterUsers.remove(lease) != nil else { return }
        guard meterUsers.isEmpty else { return }
        meterRevision &+= 1
        do { try await engine.setMetering(false, request: request, revision: meterRevision) }
        catch is CancellationError { }
        catch { Diagnostics.shared.recordFailure(HarborError(code: "music-meter-unavailable")) }
    }
    func meterSnapshot(_ lease: UUID) async throws -> MusicMeterSnapshot? {
        guard meterUsers.contains(lease), loaded, !resolving, resolution?.valid() == true,
              let track = currentTrack else { return nil }
        let token = request, revision = meterRevision
        try await engine.setMetering(true, request: token, revision: revision)
        let value = await engine.meterSnapshot(request: token)
        try Task.checkCancellation()
        guard token == request, meterUsers.contains(lease), resolution?.valid() == true,
              currentTrack.map(MusicQueueOrder.key) == MusicQueueOrder.key(track) else { throw CancellationError() }
        return value.map { .init(trackID: track.id, connectorID: track.connectorId, measurement: $0) }
    }
    func switchSource(_ track: MusicTrack) throws {
        guard let session = playbackSession, let currentItem, let index = items.firstIndex(where: { $0.id == currentItem.id }) else { throw HarborError(code: "music-source-required") }
        let selected = try session.choose(track, for: currentItem.track)
        let item = MusicPlaybackItem(track: selected, localRecord: session.localRecord(selected))
        items[index] = item
        start(item, resuming: position, paused: paused)
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
    func setQueueContinuationMode(_ mode: MusicQueueContinuationMode) {
        guard mode != queueContinuationMode else { return }
        cancelQueueContinuation()
        queueContinuationMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: MusicQueueContinuationRules.preferenceKey(owner: owner))
    }
    func loadMoreMusic() {
        guard !queueContinuationLoading, let currentItem, let session = playbackSession,
              owner == session.scope.owner, resolver.map({ ObjectIdentifier($0) == ObjectIdentifier(session) }) == true,
              (try? session.validate()) != nil else { return }

        let run = UUID(), expectedRevision = queueRevision, expectedOwner = owner
        let expectedCurrent = currentItem.id, mode = queueContinuationMode, playbackOrigin = origin
        let current = currentItem.track, queue = items.map(\.track), history = session.continuationHistory()
        queueContinuationRun = run; queueContinuationLoading = true; queueContinuationNotice = nil
        queueContinuationTask = Task { @MainActor [weak self, weak session] in
            guard let self else { return }
            defer {
                if self.queueContinuationRun == run {
                    self.queueContinuationRun = nil; self.queueContinuationTask = nil; self.queueContinuationLoading = false
                }
            }
            guard let session else { return }
            do {
                try Task.checkCancellation()
                var result = try await Self.continuationRequest(session, mode: mode, origin: playbackOrigin,
                    current: current, queue: queue, history: history)
                try Task.checkCancellation(); try session.validate()
                guard self.queueContinuationRun == run, self.queueRevision == expectedRevision,
                      self.owner == expectedOwner, self.currentItem?.id == expectedCurrent,
                      self.resolver.map({ ObjectIdentifier($0) == ObjectIdentifier(session) }) == true else { return }

                let contextExhausted = result.exhausted
                if mode == .context { self.origin = result.origin }
                var tracks = MusicQueueContinuationRules.fresh(result.tracks,
                    excluded: MusicQueueContinuationRules.excluded(current: current, queue: queue,
                        history: history, discover: mode == .discover), allowVideo: current.mediaKind == "video")
                if tracks.isEmpty, mode == .context {
                    result = try await Self.continuationRequest(session, mode: .discover, origin: self.origin,
                        current: current, queue: queue, history: history)
                    try Task.checkCancellation(); try session.validate()
                    guard self.queueContinuationRun == run, self.queueRevision == expectedRevision,
                          self.owner == expectedOwner, self.currentItem?.id == expectedCurrent,
                          self.resolver.map({ ObjectIdentifier($0) == ObjectIdentifier(session) }) == true else { return }
                    tracks = MusicQueueContinuationRules.fresh(result.tracks,
                        excluded: MusicQueueContinuationRules.excluded(current: current, queue: queue,
                            history: history, discover: true), allowVideo: current.mediaKind == "video")
                }

                let remainingCapacity = max(0, 100_000 - self.items.count)
                let appendable = Array(tracks.prefix(remainingCapacity))
                self.queueContinuationRun = nil; self.queueContinuationTask = nil; self.queueContinuationLoading = false
                if !appendable.isEmpty {
                    self.items.append(contentsOf: appendable.map {
                        MusicPlaybackItem(track: $0, localRecord: session.localRecord($0))
                    })
                    self.refreshUpcoming()
                }
                self.queueContinuationNotice = appendable.isEmpty
                    ? DesktopInterfaceText.value(mode == .context && contextExhausted ? "music.now.contextEnd" : "music.now.noNewSongs")
                    : DesktopInterfaceText.value("music.now.moreAdded", variables: ["count": String(appendable.count)])
                self.saveCheckpoint(force: true)
            } catch is CancellationError { return }
            catch {
                guard self.queueContinuationRun == run, self.queueRevision == expectedRevision,
                      self.owner == expectedOwner, self.currentItem?.id == expectedCurrent,
                      self.resolver.map({ ObjectIdentifier($0) == ObjectIdentifier(session) }) == true,
                      (try? session.validate()) != nil else { return }
                self.queueContinuationNotice = DesktopInterfaceText.value("music.now.moreError")
            }
        }
    }
    private static func continuationRequest(_ session: MusicPlaybackSession, mode: MusicQueueContinuationMode,
        origin: MusicQueueOrigin?, current: MusicTrack, queue: [MusicTrack], history: [MusicTrack]) async throws -> MusicQueueContinuationResult {
        try await withThrowingTaskGroup(of: MusicQueueContinuationResult.self) { group in
            group.addTask { try await session.loadContinuation(mode: mode, origin: origin, current: current, queue: queue, history: history) }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw HarborError(code: "music-continuation-timeout")
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw CancellationError() }
            return value
        }
    }
    private func enqueue(_ item: MusicPlaybackItem, next: Bool) {
        guard let currentItem, currentItem.id != item.id else { return }
        items.removeAll { $0.id == item.id }
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
    var queueSnapshot: MusicQueueSnapshot {
        guard let currentItem, let index = items.firstIndex(where: { $0.id == currentItem.id }) else {
            return .init(owner: owner, revision: queueRevision, current: currentItem, previous: [], upcoming: [])
        }
        return .init(owner: owner, revision: queueRevision, current: currentItem,
                     previous: Array(items.prefix(index)), upcoming: Array(items.dropFirst(index + 1)))
    }
    func ownsQueue(_ snapshot: MusicQueueSnapshot) -> Bool {
        guard snapshot.owner == owner, snapshot.revision == queueRevision, snapshot.current?.id == currentItem?.id else { return false }
        if let resolver { return (try? resolver.validate()) != nil }
        return true
    }
    func moveUpcoming(from offsets: IndexSet, to destination: Int, in snapshot: MusicQueueSnapshot) {
        guard ownsQueue(snapshot), !offsets.isEmpty, destination >= 0, destination <= snapshot.upcoming.count,
              offsets.allSatisfy({ snapshot.upcoming.indices.contains($0) }) else { return }
        let moving = offsets.map { snapshot.upcoming[$0] }
        var tail = snapshot.upcoming.enumerated().filter { !offsets.contains($0.offset) }.map { $0.element }
        let insertion = destination - offsets.filter { $0 < destination }.count
        tail.insert(contentsOf: moving, at: insertion)
        items = snapshot.previous + [snapshot.current].compactMap { $0 } + tail
        refreshUpcoming()
    }
    func clearUpcoming(in snapshot: MusicQueueSnapshot) {
        guard ownsQueue(snapshot) else { return }
        priority = nil
        items = snapshot.previous + [snapshot.current].compactMap { $0 }
        refreshUpcoming()
    }
    func removeQueueItem(_ item: MusicPlaybackItem, in snapshot: MusicQueueSnapshot) {
        guard ownsQueue(snapshot) else { return }
        removeFromQueue(item)
    }
    func playQueueItem(_ item: MusicPlaybackItem, in snapshot: MusicQueueSnapshot) {
        guard ownsQueue(snapshot) else { return }
        if currentItem?.id == item.id { togglePause() } else { play(item) }
    }
    func prioritizeQueueItem(_ item: MusicPlaybackItem, in snapshot: MusicQueueSnapshot) {
        guard ownsQueue(snapshot) else { return }
        moveAfterCurrent(item)
    }
    func replaceQueuedSource(_ selected: MusicTrack, for item: MusicPlaybackItem, in snapshot: MusicQueueSnapshot) throws {
        guard ownsQueue(snapshot), let session = playbackSession, item.id != currentItem?.id,
              let index = items.firstIndex(where: { $0.id == item.id }) else { throw CancellationError() }
        let queue = try session.replacingSource(selected, in: items.map(\.track), at: index)
        guard queue.count == items.count, MusicQueueOrder.key(queue[index]) == item.id else { throw HarborError(code: "music-source-policy") }
        let replacement = MusicPlaybackItem(track: queue[index], localRecord: session.localRecord(queue[index]))
        if priority.map(MusicQueueOrder.key) == item.id { priority = replacement.track }
        items[index] = replacement
        refreshUpcoming()
    }
    private func refreshUpcoming() {
        defer { saveCheckpoint(force: true) }
        guard let currentItem, let index = items.firstIndex(where: { $0.id == currentItem.id }) else { upcomingItems = []; return }
        do {
            var tracks = try order.upcoming(items.map(\.track), index: index, shuffle: shuffle, repeatMode: repeatMode)
            if repeatMode != .one, let priority, priority != currentItem.track { tracks.removeAll { MusicQueueOrder.key($0) == MusicQueueOrder.key(priority) }; tracks.insert(priority, at: 0) }
            let byKey = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            upcomingItems = tracks.compactMap { byKey[MusicQueueOrder.key($0)] }
        } catch { upcomingItems = []; self.error = message(error) }
    }
    func stopForAccount(_ owner: String) { if self.owner != owner { stop(); resolver = nil; self.owner = owner; loadContinuationMode(owner: owner) } }
    func reloadPreferences() {
        shuffle = UserDefaults.standard.bool(forKey: "music.shuffle")
        repeatMode = MusicRepeat(rawValue: UserDefaults.standard.string(forKey: "music.repeat") ?? "off") ?? .off
        changeVolume(Self.savedVolume())
    }
    func stop() {
        cancelQueueContinuation()
        saveCheckpoint(force: true)
        restoreTask?.cancel(); restoreTask = nil; restored = false
        effectLease = nil; audioEffects = .init(); effectRevision = UUID()
        meterUsers.removeAll(); meterRevision &+= 1
        submitScrobbleIfEligible(); resolution?.onStopped?(); resolution = nil
        request &+= 1; let token = request
        resolutionTask?.cancel(); resolutionTask = nil; poller?.cancel(); poller = nil
        Task { await engine.stop(request: token) }
        items = []; currentItem = nil; upcomingItems = []; priority = nil; origin = nil; resolution = nil
        loaded = false; resolving = false; paused = true; pausedForVideo = false; position = 0; duration = 0; ended = false
        error = nil; scrobbleError = nil; previousPosition = nil; listened = 0; try? order.reset()
        pendingResume = nil
        checkpointTarget = nil
        checkpointQueue = []; checkpointQueueRevision = nil
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
                do { try await Task.sleep(for: .milliseconds(meterUsers.isEmpty ? 200 : 50)) } catch { return }
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
                if !loaded { resolution?.onLoaded?() }
                loaded = true; error = nil
                if let position = pendingResume { pendingResume = nil; send(.seek(position)) }
                if !recorded, let track = currentTrack { recorded = true; recordPlayed(track, owner) }
            case .time(let value):
                guard value.isFinite, value >= 0, loaded else { continue }
                if let target = checkpointTarget, abs(value - target) < 0.4 { checkpointTarget = nil }
                listened += MusicListening.increment(previous: previousPosition, current: value); previousPosition = value; position = value
            case .duration(let value): if value.isFinite && value >= 0 { duration = value }
            case .paused(let value): paused = value
            case .volume(let value): if value.isFinite && (0...volumeMaximum).contains(value) { volume = value }
            case .failed:
                resolution?.onStopped?(); resolution?.onStopped = nil
                error = message(HarborError(code: "music-player")); loaded = false; paused = true
            case .ended(let eof, let failed):
                submitScrobbleIfEligible(); resolution?.onStopped?(); resolution?.onStopped = nil
                natural = natural || eof
                if failed { error = message(HarborError(code: "music-player")); loaded = false; paused = true }
            }
        }
        submitScrobbleIfEligible()
        nowPlaying(force: events.contains { if case .time = $0 { return false }; return true })
        saveCheckpoint(force: events.contains { if case .paused = $0 { return true }; return false })
        if natural { next(automatic: true) }
    }
    private func restoreCheckpoint(using session: any MusicPlaybackResolving, saved: MusicSessionSnapshot?) {
        guard let checkpoints, restoreScope != session.scope else { return }
        restoreScope = session.scope
        guard currentItem == nil else { return }
        let token = request, previousWrite = checkpointWrite
        restoreTask = Task { @MainActor [weak self] in
            await previousWrite?.value
            do {
                let value: MusicSessionSnapshot?
                if let saved { value = saved } else { value = try await checkpoints.read(owner: session.scope.owner) }
                try Task.checkCancellation(); try session.validate()
                guard let self, self.request == token, self.owner == session.scope.owner,
                      self.resolver.map({ ObjectIdentifier($0) == ObjectIdentifier(session) }) == true,
                      self.currentItem == nil, let value else { return }
                var seen = Set<String>()
                self.items = value.queue.filter { seen.insert(MusicQueueOrder.key($0)).inserted }
                    .map { .init(track: $0, localRecord: session.localRecord($0)) }
                let current = MusicPlaybackItem(track: value.current, localRecord: session.localRecord(value.current))
                if let index = self.items.firstIndex(where: { $0.id == current.id }) { self.items[index] = current }
                else { self.items.insert(current, at: 0) }
                self.currentItem = current; self.origin = value.origin
                self.duration = Double(current.track.durationSeconds)
                self.position = MusicSessionSnapshot.usablePosition(value.position, duration: self.duration)
                self.restored = true; self.loaded = false; self.resolving = false; self.paused = true; self.desiredPause = true
                self.refreshUpcoming()
            } catch is CancellationError { }
            catch { Diagnostics.shared.recordFailure(HarborError(code: "music-session")) }
        }
    }
    private func saveCheckpoint(force: Bool = false) {
        guard let checkpoints, let currentTrack, force || Date().timeIntervalSince(lastCheckpoint) >= 2 else { return }
        lastCheckpoint = Date()
        if checkpointQueueRevision != queueRevision {
            checkpointQueue = items.map(\.track); checkpointQueueRevision = queueRevision
        }
        let value = MusicSessionSnapshot(revision: queueRevision, queue: checkpointQueue, current: currentTrack,
                                         origin: origin, position: checkpointTarget ?? pendingResume ?? position, savedAt: lastCheckpoint)
        let previous = checkpointWrite, owner = owner
        checkpointWrite = Task {
            await previous?.value
            do { try await checkpoints.write(value, owner: owner) }
            catch { Diagnostics.shared.recordFailure(HarborError(code: "music-session")) }
        }
    }
    func flushCheckpoint() async { saveCheckpoint(force: true); await checkpointWrite?.value }
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
    private func nowPlaying(force: Bool = true) {
        guard systemIntegration, let track = currentTrack else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSystemClock) >= 0.2 else { return }
        lastSystemClock = now
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album ?? "", MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: paused ? 0.0 : audioPlan.settings.speed]
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
