import Foundation

struct MusicQueueSnapshot {
    let owner: String
    let revision: UUID
    let current: MusicPlaybackItem?
    let previous: [MusicPlaybackItem]
    let upcoming: [MusicPlaybackItem]
}

struct MusicQueueSourceSelection: Identifiable {
    let id = UUID()
    let item: MusicPlaybackItem
    let queue: MusicQueueSnapshot
}
