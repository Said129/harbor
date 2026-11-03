import Foundation
import Observation

/// Consumes confirmed Spotify positions, never the UI's interpolated clock.
/// A reconnect starts a new observation window without resubmitting the song.
@MainActor @Observable final class SpotifyListeningRecorder {
    private struct Context {
        let id = UUID()
        var track: MusicTrack
        let uri: String
        let startedAt: UInt64
        var previous: Double?
        var paused = true
        var listened = 0.0
        var submitted = false
    }
    private(set) var error: String?
    @ObservationIgnored private let lastfm: LastFmMusicService
    @ObservationIgnored private let scope: PluginExecutionScope
    @ObservationIgnored private let currentScope: @MainActor () -> PluginExecutionScope
    @ObservationIgnored private var connection: UUID?
    @ObservationIgnored private var credentials: UUID
    @ObservationIgnored private var context: Context?
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var disposed = false
    var enabled: Bool { !disposed && scope == currentScope() && lastfm.connected }
    init(lastfm: LastFmMusicService, currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.lastfm = lastfm; scope = lastfm.scope; self.currentScope = currentScope
        credentials = lastfm.connectionRevision
    }
    func connect(_ id: UUID) { guard !disposed else { return }; connection = id; suspend() }
    func disconnect(_ id: UUID) { guard connection == id else { return }; connection = nil; suspend() }
    func suspend() {
        context?.previous = nil
        if !enabled { context = nil; error = nil }
    }
    func playRequested() { context = nil; error = nil }
    func seekRequested() { suspend() }
    func dispose() {
        disposed = true; connection = nil; context = nil
        tasks.values.forEach { $0.cancel() }; tasks.removeAll(); error = nil
    }
    func observe(_ track: MusicTrack, position: Double, paused: Bool, advertisement: Bool, connection: UUID, at date: Date = Date()) {
        guard enabled, connection == self.connection else { return }
        if credentials != lastfm.connectionRevision {
            credentials = lastfm.connectionRevision; context = nil; error = nil
        }
        guard !advertisement else { suspend(); return }
        guard track.connectorId == "spotify", let uri = SpotifyMusicLink.uri(track.sourceId ?? track.id),
              uri.hasPrefix("spotify:track:"), position.isFinite, position >= 0, track.durationSeconds > 0,
              !track.title.isEmpty, !track.artist.isEmpty else { context = nil; return }
        let duration = Double(track.durationSeconds)
        let repeated = context.map { value in
            value.uri == uri && !value.paused && !paused && position <= 2 && (value.previous ?? 0) >= duration - 2 && duration > 4
        } ?? false
        if context?.uri != uri || repeated {
            let seconds = date.timeIntervalSince1970
            guard seconds.isFinite, seconds >= 0, seconds < Double(UInt64.max) else { return }
            context = Context(track: track, uri: uri, startedAt: UInt64(seconds)); error = nil
        }
        guard var value = context else { return }
        value.track = track
        if !value.paused { value.listened += MusicListening.increment(previous: value.previous, current: position) }
        value.previous = position; value.paused = paused
        let eligible = !value.submitted && MusicListening.shouldScrobble(listened: value.listened, duration: duration)
        if eligible { value.submitted = true }
        context = value
        guard eligible else { return }
        let request = UUID(), expected = credentials, recording = value, lastfm = lastfm
        tasks[request] = Task { @MainActor [weak self] in
            defer { self?.tasks[request] = nil }
            guard let self, self.enabled, expected == lastfm.connectionRevision else { return }
            do { try await lastfm.scrobble(recording.track, startedAt: recording.startedAt) }
            catch is CancellationError { }
            catch {
                if self.enabled, expected == lastfm.connectionRevision, self.context?.id == recording.id {
                    self.error = DesktopInterfaceText.value("music.mobile.scrobbleError")
                }
            }
        }
    }
}
