import Foundation

/// Desktop's hero and detail trailer rules, reduced to what iPhone and iPad can honour. iOS plays a trailer only through
/// YouTube's embed, which chooses its own stream quality, so Desktop's `trailerQuality` and its 360p hero fetch have no
/// iOS equivalent and this file maps no quality.
/// Desktop reference: `src/components/cinema-hero.tsx` (first candidate, muted unless audio is on, paused off screen)
/// and `src/views/detail/detail-hero-trailer.tsx` (muted unless `detailTrailerAudio`, paused when the page is hidden).
enum HeroTrailerPolicy {
    /// The inputs that decide whether a trailer may play now. The view fills them from settings, the scene and the system.
    struct Conditions: Equatable, Sendable {
        var enabled: Bool
        var hasTrailer: Bool
        var sceneActive: Bool
        var slideActive: Bool
        var reduceMotion: Bool
        var lowPowerMode: Bool
        var expensiveNetwork: Bool
        var constrainedNetwork: Bool
    }

    /// Plays only when every gate passes. A metered or Low Data Mode connection keeps the artwork instead of a trailer.
    static func shouldPlay(_ conditions: Conditions) -> Bool {
        guard conditions.enabled, conditions.hasTrailer else { return false }
        guard conditions.sceneActive, conditions.slideActive else { return false }
        guard !conditions.reduceMotion, !conditions.lowPowerMode else { return false }
        return !conditions.expensiveNetwork && !conditions.constrainedNetwork
    }

    /// Desktop starts every trailer muted unless its audio setting is on.
    static func muted(audioEnabled: Bool) -> Bool {
        !audioEnabled
    }

    /// YouTube keys are 11 characters from the URL-safe alphabet. Anything else is refused before it reaches a URL.
    static func isValidYouTubeID(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
    }

    /// The first usable trailer in the order the details list gives. Invalid entries are skipped, not repaired.
    static func trailerID(in trailers: [MediaDetails.Trailer]) -> String? {
        trailers.first { isValidYouTubeID($0.id) }?.id
    }

    /// The privacy-enhanced embed, with inline playback and no controls. Returns nil for an invalid key.
    static func embedURL(videoID: String, muted: Bool) -> URL? {
        guard isValidYouTubeID(videoID) else { return nil }
        var components = URLComponents(string: "https://www.youtube-nocookie.com/embed/" + videoID)
        components?.queryItems = [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "mute", value: muted ? "1" : "0"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "controls", value: "0"),
            URLQueryItem(name: "loop", value: "1"),
            URLQueryItem(name: "playlist", value: videoID),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "modestbranding", value: "1")
        ]
        return components?.url
    }
}
