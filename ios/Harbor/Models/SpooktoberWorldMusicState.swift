import Foundation

/// A projection of player identity and phase, never its high-frequency playback clock.
struct SpooktoberWorldMusicState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case idle, resolving, playing, paused, error }
    let trackId: String?
    let originKind: String?
    let originId: String?
    let phase: Phase
    static let idle = Self(trackId: nil, originKind: nil, originId: nil, phase: .idle)
}
