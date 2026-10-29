import Foundation

struct MusicSourceCandidate: Codable, Hashable, Sendable, Identifiable {
    enum Health: String, Codable, Sendable { case unknown, healthy, degraded, offline }
    let connectorId: String
    let connectorName: String
    let health: Health
    let track: MusicTrack
    var id: String { connectorId + "|" + track.id }
}
struct MusicSourceChoice: Codable, Equatable, Sendable {
    let track: MusicTrack
    let queue: [MusicTrack]
}
struct MusicSourcePolicyRequest: Codable, Sendable {
    let operation: String
    var track: MusicTrack?
    var selected: MusicTrack?
    var queue: [MusicTrack]?
    var candidates: [MusicSourceCandidate]?
    var index: Int?
    var preferred: String?
    var connectorId: String?
    var explicit: Bool?
    var failed: Bool?
}
