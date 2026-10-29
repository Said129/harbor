import CryptoKit
import Foundation
import JavaScriptCore

struct MusicQueueOrderRequest: Codable, Sendable {
    let operation: String
    var queue: [MusicTrack]?
    var track: MusicTrack?
    var index: Int?
    var shuffle: Bool?
    var repeatMode: String?
    var automatic: Bool?
    var priority: MusicTrack?
    var count: Int?
    var randoms: [Double]?
}

/// The complete pinned Desktop queue implementation owns shuffle/history, so a
/// preview and the next button consume the same listening order.
@MainActor final class MusicQueueOrder {
    private var context: JSContext?
    private func prepare() throws -> JSContext {
        if let context { return context }
        guard let url = Bundle.main.url(forResource: "MusicQueueOrderAssets", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 128 * 1024,
              let asset = try? JSONDecoder().decode(JSONValue.self, from: data),
              asset["schema"].integer == 1, asset["reference"].string == "0834340cec5531650bfe78cd628628702e636987",
              asset["inputs"].objectValue.count == 1, let source = asset["program"]["source"].string,
              let expected = asset["program"]["sha256"].string,
              SHA256.hash(data: Data(source.utf8)).map({ String(format: "%02x", $0) }).joined() == expected,
              expected == "304e9e0a23fe198a59959cb9cb1b09cfc9228d026f72aa5c219341fb09ab391f", let context = JSContext() else { throw HarborError(code: "music-queue-order") }
        context.evaluateScript(source)
        guard context.exception == nil, context.objectForKeyedSubscript("harborMusicQueueOrder")?.isUndefined == false else { throw HarborError(code: "music-queue-order") }
        self.context = context; return context
    }
    func evaluate(_ request: MusicQueueOrderRequest) throws -> JSONValue {
        let data = try JSONEncoder().encode(request)
        guard data.count <= 1024 * 1024 else { throw HarborError(code: "music-queue-order") }
        let context = try prepare(); context.exception = nil
        let result = context.objectForKeyedSubscript("harborMusicQueueOrder")?.call(withArguments: [String(decoding: data, as: UTF8.self)])
        guard context.exception == nil, let raw = result?.toString(), let bytes = raw.data(using: .utf8), bytes.count <= 1024 * 1024 else { throw HarborError(code: "music-queue-order") }
        return try JSONDecoder().decode(JSONValue.self, from: bytes)
    }
    private func decode<T: Decodable>(_ request: MusicQueueOrderRequest, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(evaluate(request)))
    }
    func reset() throws { _ = try evaluate(.init(operation: "reset")) }
    func next(_ queue: [MusicTrack], index: Int, shuffle: Bool, repeatMode: MusicRepeat, automatic: Bool, priority: MusicTrack?) throws -> MusicTrack? {
        try decode(.init(operation: "next", queue: queue, index: index, shuffle: shuffle, repeatMode: repeatMode.rawValue, automatic: automatic, priority: priority), as: MusicTrack?.self)
    }
    func previous(_ queue: [MusicTrack], index: Int, shuffle: Bool) throws -> MusicTrack? {
        try decode(.init(operation: "previous", queue: queue, index: index, shuffle: shuffle), as: MusicTrack?.self)
    }
    func upcoming(_ queue: [MusicTrack], index: Int, shuffle: Bool, repeatMode: MusicRepeat, count: Int = 500) throws -> [MusicTrack] {
        try decode(.init(operation: "upcoming", queue: queue, index: index, shuffle: shuffle, repeatMode: repeatMode.rawValue, count: count), as: [MusicTrack].self)
    }
    nonisolated static func key(_ track: MusicTrack) -> String {
        (track.collectionOrigin?.connectorId ?? track.connectorId ?? "") + ":" + (track.collectionOrigin?.id ?? track.id)
    }
}
