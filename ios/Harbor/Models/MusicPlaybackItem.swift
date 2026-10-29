import Foundation

struct MusicPlaybackItem: Identifiable, Hashable, Sendable {
    let track: MusicTrack
    var localRecord: MusicRecord?
    var id: String { MusicQueueOrder.key(track) }
    init(track: MusicTrack, localRecord: MusicRecord? = nil) { self.track = track; self.localRecord = localRecord }
    init(_ record: MusicRecord) { track = record.local.track; localRecord = record }
}
struct MusicPlaybackResolution: Sendable {
    let stream: MusicAudioStream
    let valid: @MainActor @Sendable () -> Bool
}
@MainActor protocol MusicPlaybackResolving: AnyObject {
    var scope: PluginExecutionScope { get }
    func validate() throws
    func localRecord(_ track: MusicTrack) -> MusicRecord?
    func resolve(_ track: MusicTrack) async throws -> MusicPlaybackResolution
    func scrobble(_ track: MusicTrack, startedAt: UInt64) async throws
}

enum MusicListening {
    static func increment(previous: Double?, current: Double) -> Double {
        guard let previous else { return 0 }
        let delta = current - previous
        return current.isFinite && delta.isFinite && delta > 0 && delta <= 2 ? delta : 0
    }
    static func shouldScrobble(listened: Double, duration: Double) -> Bool {
        listened >= (duration.isFinite && duration > 0 ? min(duration * 0.5, 240) : 240)
    }
}
