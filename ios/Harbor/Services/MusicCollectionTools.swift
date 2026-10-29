import CryptoKit
import Foundation
import JavaScriptCore

struct MusicCollectionFilters: Codable, Equatable, Sendable {
    var query = ""
    var genre: Int?
    var source = "all"
    var content = MusicContentFilter.all
    var sort = MusicSort.original
    var descending = false
    var view = "list"
    var active: Bool { !query.isEmpty || genre != nil || source != "all" || content != .all }
    var canReorder: Bool { !active && sort == .original }
    static func limitedQuery(_ value: String) -> String {
        var result = "", units = 0
        for character in value {
            let text = String(character), count = text.utf16.count
            guard units + count <= 200 else { break }; result += text; units += count
        }
        return result
    }
    mutating func reset() { query = ""; genre = nil; source = "all"; content = .all }
    var sortTitle: String {
        let key = switch sort {
        case .original: "music.sort.default"
        case .added: "music.playlistTools.added"
        case .title: "music.playlistTools.title"
        case .artist: "music.playlistTools.artist"
        case .album: "music.playlistTools.album"
        case .duration: "music.sort.duration"
        }
        return DesktopInterfaceText.value(key)
    }
}
struct MusicCollectionInput: Equatable, Sendable {
    let tracks: [MusicTrack]
    var filters = MusicCollectionFilters()
    var addedAt: [String: String]?
    var recentFirst = false
    var genreTracks: [Int: Set<String>] = [:]
}

/// Filtering thousands of saved recordings stays off the UI actor. All source
/// comparisons, date parsing and identity normalization run the pinned modules.
actor MusicCollectionTools {
    private var context: JSContext?
    private struct Request: Encodable {
        let operation: String
        var tracks: [MusicTrack]?
        var candidates: [MusicTrack]?
        var track: MusicTrack?
        var source: String?
        var filters: MusicCollectionFilters?
        var metadata: Metadata?
        var genreTracks: [String: [String]]?
    }
    private struct Metadata: Encodable { var addedAt: [String: String]?; var recentFirst: Bool }
    private func prepare() throws -> JSContext {
        if let context { return context }
        guard let url = Bundle.main.url(forResource: "MusicCollectionToolsAssets", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 256 * 1024,
              let asset = try? JSONDecoder().decode(JSONValue.self, from: data),
              asset["schema"].integer == 1, asset["reference"].string == "0834340cec5531650bfe78cd628628702e636987",
              asset["inputs"].objectValue.count == 5, let source = asset["program"]["source"].string,
              let digest = asset["program"]["sha256"].string, digest == "85a0e907ad1a5c61c7720dd421738f6027efa96012d2d77a681d25224b94e994",
              SHA256.hash(data: Data(source.utf8)).map({ String(format: "%02x", $0) }).joined() == digest,
              let context = JSContext() else { throw HarborError(code: "music-collection-tools") }
        context.evaluateScript(source)
        guard context.exception == nil, context.objectForKeyedSubscript("harborMusicCollectionTools")?.isUndefined == false else { throw HarborError(code: "music-collection-tools") }
        self.context = context; return context
    }
    private func run<T: Decodable & Sendable>(_ input: Request, as type: T.Type) throws -> T {
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(input)
        guard data.count <= 16 * 1024 * 1024 else { throw HarborError(code: "music-collection-tools") }
        let context = try prepare(); context.exception = nil
        let value = context.objectForKeyedSubscript("harborMusicCollectionTools")?.call(withArguments: [String(decoding: data, as: UTF8.self)])
        guard context.exception == nil, let raw = value?.toString(), let bytes = raw.data(using: .utf8), bytes.count <= 16 * 1024 * 1024 else { throw HarborError(code: "music-collection-tools") }
        try Task.checkCancellation()
        return try JSONDecoder().decode(type, from: bytes)
    }
    func filter(_ input: MusicCollectionInput) throws -> [MusicTrack] {
        try run(.init(operation: "filter", tracks: input.tracks, filters: input.filters,
                      metadata: .init(addedAt: input.addedAt, recentFirst: input.recentFirst),
                      genreTracks: Dictionary(uniqueKeysWithValues: input.genreTracks.map { (String($0.key), $0.value.sorted()) })), as: [MusicTrack].self)
    }
    func sources(_ tracks: [MusicTrack]) throws -> [String] { try run(.init(operation: "sources", tracks: tracks), as: [String].self) }
    func label(_ source: String) throws -> String { try run(.init(operation: "label", source: source), as: String.self) }
    func identity(_ track: MusicTrack) throws -> String { try run(.init(operation: "identity", track: track), as: String.self) }
    func addable(_ candidates: [MusicTrack], to held: [MusicTrack]) throws -> [MusicTrack] {
        try run(.init(operation: "addable", tracks: held, candidates: candidates), as: [MusicTrack].self)
    }
}
