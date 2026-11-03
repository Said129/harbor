import Foundation

struct MusicQueueSnapshot {
    let owner: String
    let revision: UUID
    let current: MusicPlaybackItem?
    let previous: [MusicPlaybackItem]
    let upcoming: [MusicPlaybackItem]
}
