import Foundation

struct JellyfinMusicAccount: Codable, Sendable {
    let origin: String
    let userId: String
    let userName: String
    let token: String
    let deviceId: String
    let serverName: String
    let libraryId: String?
}
struct JellyfinMusicSession: Codable, Sendable {
    let itemId: String
    let playSessionId: String
    let mediaSourceId: String?
}
struct JellyfinMusicCommand: Encodable, Sendable {
    let action: String
    var query: String?
    var limit: Int?
    var id: String?
    var kind: MusicCatalogKind?
    var track: MusicTrack?
    var session: JellyfinMusicSession?
    var direct: Bool?
}
struct JellyfinMusicRequest: Encodable, Sendable {
    let action: String
    var address: String?
    var username: String?
    var password: String?
    var deviceId: String?
    var config: JellyfinMusicAccount?
    var command: JellyfinMusicCommand?
}
struct JellyfinMusicResolution: Decodable, Sendable {
    struct Stream: Decodable, Sendable {
        let url: URL
        let httpHeaders: [String: String]?
        let mimeType: String
        let bitrate: UInt64
    }
    let stream: Stream
    let session: JellyfinMusicSession
    let direct: Bool
}
