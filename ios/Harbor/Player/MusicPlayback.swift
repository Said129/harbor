import AVFoundation
import Foundation
import Libmpv
import MediaPlayer
import Observation

enum MusicRepeat: String, CaseIterable, Identifiable {
    case off, all, one
    var id: String { rawValue }
    var title: String { switch self { case .off: "Sin repetir"; case .all: "Repetir cola"; case .one: "Repetir canción" } }
}

@MainActor @Observable
final class MusicPlayback {
    static let shared = MusicPlayback()
    private(set) var owner = "guest"
    private(set) var queue: [MusicRecord] = []
    private(set) var current: MusicRecord?
    private(set) var position = 0.0
    private(set) var duration = 0.0
    private(set) var paused = true
    private(set) var loaded = false
    private(set) var pausedForVideo = false
    var shuffle = UserDefaults.standard.bool(forKey: "music.shuffle") { didSet { UserDefaults.standard.set(shuffle, forKey: "music.shuffle") } }
    var repeatMode = MusicRepeat(rawValue: UserDefaults.standard.string(forKey: "music.repeat") ?? "off") ?? .off { didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "music.repeat") } }
    var volume = MusicPlayback.savedVolume() { didSet { if volume.isFinite && (0...100).contains(volume) { UserDefaults.standard.set(volume, forKey: "music.volume") } } }
    var error: String?
    private var handle: OpaquePointer?
    private var poller: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []
    private var played: Set<String> = []
    private var remoteReady = false
    private var ended = false
    private var pendingLoad = false
    private static func savedVolume() -> Double {
        guard let value = UserDefaults.standard.object(forKey: "music.volume") as? Double, value.isFinite, (0...100).contains(value) else { return 82 }
        return value
    }

    func play(_ record: MusicRecord, queue: [MusicRecord], owner: String, continuingQueue: Bool = false) {
        do {
            let url = try MusicFileService.file(record, owner: owner)
            if self.owner != owner { stop() }
            self.owner = owner
            self.queue = Array(queue.prefix(500))
            if !self.queue.contains(where: { $0.id == record.id }) { self.queue = Array(self.queue.prefix(499)); self.queue.append(record) }
            try setup()
            guard let handle else { throw HarborError(code: "music-player") }
            current = record; position = 0; duration = Double(record.local.track.durationSeconds)
            loaded = false; error = nil; pausedForVideo = false; ended = false; pendingLoad = true
            if !continuingQueue { played = [] }
            played.insert(record.id)
            set("volume", String(volume)); set("pause", "no")
            try MusicMPV.command(handle, ["loadfile", url.path, "replace"])
            nowPlaying()
        } catch { self.error = safeMessage(error) }
    }
    func togglePause() { setPaused(!paused) }
    func setPaused(_ value: Bool) {
        pausedForVideo = false
        if !value, ended, let current { play(current, queue: queue, owner: owner, continuingQueue: true); return }
        if !value { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default); try? AVAudioSession.sharedInstance().setActive(true) }
        set("pause", value ? "yes" : "no")
    }
    func pauseForVideo() {
        guard current != nil, !paused else { return }
        set("pause", "yes"); pausedForVideo = true
    }
    func seek(_ value: Double) {
        guard value.isFinite, value >= 0, let handle else { return }
        do { try MusicMPV.command(handle, ["seek", String(min(value, max(duration, 0))), "absolute+exact"]) }
        catch { self.error = safeMessage(error) }
    }
    func changeVolume(_ value: Double) {
        guard value.isFinite else { return }
        volume = min(100, max(0, value)); set("volume", String(volume))
    }
    func next(automatic: Bool = false) {
        guard let current, let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        if automatic && repeatMode == .one { play(current, queue: queue, owner: owner, continuingQueue: true); return }
        var candidate: MusicRecord?
        if shuffle {
            var available = queue.filter { !played.contains($0.id) }
            if available.isEmpty && repeatMode == .all { played = [current.id]; available = queue.filter { $0.id != current.id } }
            candidate = available.randomElement()
            if candidate == nil && repeatMode == .all { candidate = current }
        } else if index + 1 < queue.count { candidate = queue[index + 1] }
        else if repeatMode == .all { candidate = queue.first }
        if let candidate { play(candidate, queue: queue, owner: owner, continuingQueue: true) }
        else if automatic { setPaused(true); ended = true; loaded = false; position = duration; nowPlaying() }
    }
    func previous() {
        guard let current, let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        if position > 3 { seek(0) }
        else if index > 0 { play(queue[index - 1], queue: queue, owner: owner, continuingQueue: true) }
        else { seek(0) }
    }
    func remove(_ record: MusicRecord) {
        if current?.id == record.id { stop() }
        else { queue.removeAll { $0.id == record.id } }
    }
    func enqueue(_ record: MusicRecord, owner: String, next: Bool = false) {
        guard self.owner == owner, let current else { play(record, queue: [record], owner: owner); return }
        guard current.id != record.id else { return }
        queue.removeAll { $0.id == record.id }
        guard queue.count < 500 else { error = "La cola admite hasta 500 canciones."; return }
        if next, let index = queue.firstIndex(where: { $0.id == current.id }) { queue.insert(record, at: index + 1) }
        else { queue.append(record) }
        played.remove(record.id)
    }
    func moveAfterCurrent(_ record: MusicRecord) {
        guard let current, current.id != record.id, queue.contains(where: { $0.id == record.id }) else { return }
        do {
            let remaining = queue.filter { $0.id != record.id }
            guard let index = remaining.firstIndex(where: { $0.id == current.id }) else { return }
            let ids = try MusicOrdering.move(queue.map(\.id), track: record.id, to: index + 1)
            let records = Dictionary(uniqueKeysWithValues: queue.map { ($0.id, $0) })
            queue = ids.compactMap { records[$0] }; played.remove(record.id)
        } catch { self.error = safeMessage(error) }
    }
    func removeFromQueue(_ record: MusicRecord) {
        guard let index = queue.firstIndex(where: { $0.id == record.id }) else { return }
        let remaining = queue.filter { $0.id != record.id }
        if current?.id == record.id {
            if !remaining.isEmpty { play(remaining[min(index, remaining.count - 1)], queue: remaining, owner: owner, continuingQueue: true) }
            else { stop() }
        } else { queue = remaining; played.remove(record.id) }
    }
    func stopForAccount(_ owner: String) { if self.owner != owner { stop(); self.owner = owner } }
    func stop() {
        poller?.cancel(); poller = nil
        if let handle { mpv_terminate_destroy(handle) }
        handle = nil; queue = []; current = nil; played = []
        loaded = false; paused = true; pausedForVideo = false; position = 0; duration = 0; ended = false; pendingLoad = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPRemoteCommandCenter.shared().playCommand.isEnabled = false
        MPRemoteCommandCenter.shared().pauseCommand.isEnabled = false
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.isEnabled = false
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = false
    }
    private func setup() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        if handle == nil {
            guard let created = mpv_create() else { throw HarborError(code: "music-player") }
            do {
                for (name, value) in [("config", "no"), ("terminal", "no"), ("msg-level", "all=no"), ("vo", "null"), ("vid", "no"), ("audio-display", "no"), ("access-references", "no"), ("keep-open", "no")] {
                    guard mpv_set_option_string(created, name, value) >= 0 else { throw HarborError(code: "music-player") }
                }
                guard mpv_initialize(created) >= 0 else { throw HarborError(code: "music-player") }
                for property in ["time-pos", "duration"] { guard mpv_observe_property(created, 0, property, MPV_FORMAT_DOUBLE) >= 0 else { throw HarborError(code: "music-player") } }
                guard mpv_observe_property(created, 0, "pause", MPV_FORMAT_FLAG) >= 0 else { throw HarborError(code: "music-player") }
                handle = created
            } catch { mpv_terminate_destroy(created); throw error }
            poller = Task { [weak self] in
                while !Task.isCancelled {
                    self?.events()
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                }
            }
        }
        remoteControls()
    }
    private func set(_ property: String, _ value: String) {
        guard let handle else { return }
        let status = value.withCString { pointer in
            var string: UnsafePointer<CChar>? = pointer
            return withUnsafeMutablePointer(to: &string) { mpv_set_property_async(handle, 0, property, MPV_FORMAT_STRING, $0) }
        }
        if status < 0 { error = "No se pudo cambiar el estado de Música." }
    }
    private func events() {
        guard let handle else { return }
        var endedNormally = false
        for _ in 0..<64 {
            guard let event = mpv_wait_event(handle, 0)?.pointee, event.event_id != MPV_EVENT_NONE else { break }
            if event.event_id == MPV_EVENT_FILE_LOADED { loaded = true }
            if event.event_id == MPV_EVENT_START_FILE { loaded = false; position = 0; pendingLoad = false }
            if event.event_id == MPV_EVENT_PROPERTY_CHANGE, let data = event.data {
                let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                guard let raw = property.name, let value = property.data else { continue }
                let name = String(cString: raw)
                if property.format == MPV_FORMAT_DOUBLE {
                    let number = value.assumingMemoryBound(to: Double.self).pointee
                    guard number.isFinite, number >= 0 else { continue }
                    if name == "time-pos" && loaded { position = number }
                    if name == "duration" { duration = number }
                } else if name == "pause" && property.format == MPV_FORMAT_FLAG { paused = value.assumingMemoryBound(to: Int32.self).pointee != 0 }
            }
            if event.event_id == MPV_EVENT_END_FILE, let data = event.data {
                let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                if end.error < 0 { error = "No se pudo reproducir este archivo de música."; loaded = false }
                endedNormally = !pendingLoad && end.reason == MPV_END_FILE_REASON_EOF
            }
            if (event.event_id == MPV_EVENT_COMMAND_REPLY || event.event_id == MPV_EVENT_SET_PROPERTY_REPLY) && event.error < 0 { error = "La operación de Música ha fallado." }
        }
        nowPlaying()
        if endedNormally { next(automatic: true) }
    }
    private func nowPlaying() {
        guard let track = current?.local.track else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album ?? "", MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: paused ? 0.0 : 1.0
        ]
    }
    private func remoteControls() {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand, center.nextTrackCommand, center.previousTrackCommand, center.changePlaybackPositionCommand] { command.isEnabled = true }
        guard !remoteReady else { return }
        remoteReady = true
        center.playCommand.addTarget { _ in Task { @MainActor in Self.shared.setPaused(false) }; return .success }
        center.pauseCommand.addTarget { _ in Task { @MainActor in Self.shared.setPaused(true) }; return .success }
        center.togglePlayPauseCommand.addTarget { _ in Task { @MainActor in Self.shared.togglePause() }; return .success }
        center.nextTrackCommand.addTarget { _ in Task { @MainActor in Self.shared.next() }; return .success }
        center.previousTrackCommand.addTarget { _ in Task { @MainActor in Self.shared.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor in Self.shared.seek(position) }; return .success
        }
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { notification in
            let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            if began { Task { @MainActor in Self.shared.setPaused(true) } }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { notification in
            let unplugged = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            if unplugged { Task { @MainActor in Self.shared.setPaused(true) } }
        })
    }
}
