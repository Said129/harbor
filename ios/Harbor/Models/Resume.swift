import Foundation

struct ResumeTarget: Codable, Sendable {
    let id: String
    var season: Int?
    var episode: Int?
    var videoId: String?
}

struct ResumeEntry: Codable, Equatable, Sendable {
    let ms: Double
    let t: UInt64
    var pct: Double? = nil
    var source: String? = nil
}

struct CloudResume: Sendable {
    let entry: ResumeEntry
    let durationMs: Double
}

struct ResumeDocument: Codable, Sendable {
    var version = 1
    var entries: [String: ResumeEntry] = [:]
}

struct ResumeStart: Decodable, Sendable {
    let ms: Double
    let prompt: Bool
}

struct PlaybackProgressStores: Sendable {
    let personalOwner: String
    let sharedOwner: String
    let personal: ResumeStore
    let shared: ResumeStore
}

struct PlaybackSession: Identifiable, Sendable {
    let id = UUID()
    let source: PlaybackSource
    let target: ResumeTarget
    let startMs: Double
    let storageWarning: String?
    let progressEnabled: Bool
    var owner = "guest"
    var personalOwner: String? = nil
    var progressStores: PlaybackProgressStores? = nil
    var resumeStore: ResumeStore? = nil
    var preservePosition = false
    var advanceStartedAtMs: Double? = nil
    var promptForResume = false
    var subtitleRequest: SubtitleRequest? = nil
    var media: Media? = nil
}

struct ResumeSnapshot: Sendable {
    let positionMs: Double
    let durationMs: Double
    let timestampMs: UInt64
    let exiting: Bool
}

struct SourceContinuation: Sendable {
    let target: ResumeTarget
    let owner: String
    let snapshot: ResumeSnapshot
    var advanceStartedAtMs: Double? = nil
    func position(for target: ResumeTarget, owner: String) -> Double? {
        guard owner == self.owner, target.id == self.target.id, target.season == self.target.season,
              target.episode == self.target.episode, target.videoId == self.target.videoId,
              snapshot.positionMs.isFinite, snapshot.positionMs >= 0 else { return nil }
        return snapshot.positionMs
    }
}
