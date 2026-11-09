import Foundation

enum MusicQueueContinuationMode: String, CaseIterable, Identifiable, Sendable {
    case context, discover
    var id: String { rawValue }
}

struct MusicQueueContinuationResult: Sendable {
    let tracks: [MusicTrack]
    let origin: MusicQueueOrigin?
    let exhausted: Bool
}

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

    static func fresh(_ candidates: [MusicTrack], excluded: [MusicTrack], allowVideo: Bool) -> [MusicTrack] {
        fresh(candidates, excluded: excluded, allowVideo: allowVideo,
              isVideo: { $0.mediaKind == "video" }, key: MusicQueueOrder.key, recording: identity)
    }

    /// Desktop's recording identity follows the credited title and lead artist,
    /// so a second provider copy of a queued song is still treated as a duplicate.
    static func identity(_ track: MusicTrack) -> String {
        let creditedTitle = track.collectionOrigin?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let creditedArtist = track.collectionOrigin?.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = normalized(creditedTitle.isEmpty ? track.title : creditedTitle)
        let artist = creditedArtist.isEmpty ? track.artist : creditedArtist
        let lead = artistLead(artist)
        guard !title.isEmpty, !lead.isEmpty else { return (track.connectorId ?? "") + ":" + track.id }
        return title + "::" + lead
    }

    static func preferenceKey(owner: String) -> String {
        "harbor.music.queue-continuation.v1." + EBookShelf.hash(owner)
    }

    private static func artistLead(_ value: String) -> String {
        let pattern = #"\s*(?:,|\s&\s|\s+\(?(?:feat\.?|ft\.?|featuring)\s+)\s*"#
        let name = value.range(of: pattern, options: [.regularExpression, .caseInsensitive]).map { String(value[..<$0.lowerBound]) } ?? value
        return normalized(name)
    }

    private static func normalized(_ value: String) -> String {
        let compatible = value.precomposedStringWithCompatibilityMapping
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"['`´ʻʼ‘’]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&", with: " and ")
        let words = compatible.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
        return words.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
