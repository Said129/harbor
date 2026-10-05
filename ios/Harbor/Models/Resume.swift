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

struct PlaybackSession: Identifiable, Sendable {
    let id = UUID()
    let source: PlaybackSource
    let target: ResumeTarget
    let startMs: Double
    let storageWarning: String?
    let progressEnabled: Bool
    var owner = "guest"
    var resumeStore: ResumeStore? = nil
}

struct ResumeSnapshot: Sendable {
    let positionMs: Double
    let durationMs: Double
    let timestampMs: UInt64
    let exiting: Bool
}
