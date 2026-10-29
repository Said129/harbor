import CryptoKit
import Foundation
import JavaScriptCore

/// Runs the pinned source's pure recording/version/queue decisions. Provider
/// transport, credentials and player state remain outside this context.
@MainActor final class MusicSourcePolicy {
    private var context: JSContext?
    private func prepare() throws -> JSContext {
        if let context { return context }
        guard let url = Bundle.main.url(forResource: "MusicSourcePolicyAssets", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 512 * 1024,
              let asset = try? JSONDecoder().decode(JSONValue.self, from: data),
              asset["schema"].integer == 1, asset["reference"].string == "0834340cec5531650bfe78cd628628702e636987",
              asset["inputs"].objectValue.count == 4, let source = asset["program"]["source"].string,
              let expected = asset["program"]["sha256"].string,
              SHA256.hash(data: Data(source.utf8)).map({ String(format: "%02x", $0) }).joined() == expected,
              expected == "043e8a1f1c42708e772262647d09678b8fb8016ba768dfb12276f28e9ee17e3f", let context = JSContext() else { throw HarborError(code: "music-source-policy") }
        context.evaluateScript(source)
        guard context.exception == nil, context.objectForKeyedSubscript("harborMusicSourcePolicy")?.isUndefined == false else { throw HarborError(code: "music-source-policy") }
        self.context = context; return context
    }
    func evaluate(_ request: MusicSourcePolicyRequest) throws -> JSONValue {
        let data = try JSONEncoder().encode(request)
        guard data.count <= 512 * 1024 else { throw HarborError(code: "music-source-policy") }
        let context = try prepare(); context.exception = nil
        let result = context.objectForKeyedSubscript("harborMusicSourcePolicy")?.call(withArguments: [String(decoding: data, as: UTF8.self)])
        guard context.exception == nil, let raw = result?.toString(), let bytes = raw.data(using: .utf8), bytes.count <= 1024 * 1024 else { throw HarborError(code: "music-source-policy") }
        return try JSONDecoder().decode(JSONValue.self, from: bytes)
    }
    private func decode<T: Decodable>(_ request: MusicSourcePolicyRequest, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(evaluate(request)))
    }
    func adopt(_ selected: MusicTrack, requested: MusicTrack) throws -> MusicTrack {
        try decode(.init(operation: "adopt", track: requested, selected: selected), as: MusicTrack.self)
    }
    func replace(_ queue: [MusicTrack], at index: Int, with selected: MusicTrack) throws -> [MusicTrack] {
        try decode(.init(operation: "replace", selected: selected, queue: queue, index: index), as: [MusicTrack].self)
    }
    func selectable(_ candidates: [MusicSourceCandidate], current: MusicTrack) throws -> [MusicSourceCandidate] {
        try decode(.init(operation: "selectable", track: current, candidates: candidates), as: [MusicSourceCandidate].self)
    }
    func choose(_ track: MusicTrack, queue: [MusicTrack]? = nil, candidates: [MusicSourceCandidate], preferred: String?) throws -> MusicSourceChoice? {
        try decode(.init(operation: "choose", track: track, queue: queue, candidates: candidates, preferred: preferred), as: MusicSourceChoice?.self)
    }
}
