import Foundation

/// Desktop's queue continuation candidate rules (lib/music/queue-continuation.ts).
/// Generic over the track type, so the playback queue (Player/) is not needed to test them.
enum MusicQueueContinuationRules {
    /// Desktop's excluded list: the current track and the queue, plus the history only in discover mode.
    static func excluded<T>(current: T, queue: [T], history: [T], discover: Bool) -> [T] {
        [current] + queue + (discover ? history : [])
    }

    /// Desktop's freshContinuationTracks: a video candidate is dropped unless the seed is a video, and a candidate
    /// is dropped when its queue key or its recording identity was excluded or already accepted earlier in the list.
    static func fresh<T>(_ candidates: [T], excluded: [T], allowVideo: Bool, isVideo: (T) -> Bool,
                         key: (T) -> String, recording: (T) -> String) -> [T] {
        var ids = Set(excluded.map(key))
        var recordings = Set(excluded.map(recording))
        return candidates.filter { track in
            let id = key(track)
            let identity = recording(track)
            if (isVideo(track) && !allowVideo) || ids.contains(id) || recordings.contains(identity) { return false }
            ids.insert(id)
            recordings.insert(identity)
            return true
        }
    }
}
