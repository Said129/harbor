import CryptoKit
import Foundation
import JavaScriptCore

struct MusicEQCorrection: Decodable, Sendable {
    let filters: [MusicPEQFilter]
    let preampDb: Double
    func loading(into current: MusicAudioOptions) -> MusicAudioOptions {
        var next = current
        next.peqFilters = filters; next.preampDb = preampDb
        next.eqMode = "parametric"; next.eqEnabled = true
        next.autoHeadroom = false; next.eqStrength = 1
        return next
    }
}
struct MusicEQResponse: Decodable, Sendable {
    let draft: [Double]
    let applied: [Double]
    let headroom: Double
}

/// The original Desktop APO parser, exporter and RBJ response calculation.
/// This pure context has no network, filesystem or account bridge.
@MainActor final class MusicParametricEQ {
    private var context: JSContext?
    private func prepare() throws -> JSContext {
        if let context { return context }
        guard let url = Bundle.main.url(forResource: "MusicParametricEQAssets", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 128 * 1024,
              let asset = try? JSONDecoder().decode(JSONValue.self, from: data),
              asset["schema"].integer == 1,
              asset["reference"].string == "0834340cec5531650bfe78cd628628702e636987",
              let source = asset["program"]["source"].string,
              let expected = asset["program"]["sha256"].string,
              expected == "54f833128fa79a0b6d30936cf51065756493e4d3f276df0a5f7e76d6952a82c7",
              SHA256.hash(data: Data(source.utf8)).map({ String(format: "%02x", $0) }).joined() == expected,
              let context = JSContext() else { throw HarborError(code: "music-eq-correction") }
        context.evaluateScript(source)
        guard context.exception == nil, context.objectForKeyedSubscript("harborMusicParametricEQ")?.isUndefined == false else { throw HarborError(code: "music-eq-correction") }
        self.context = context; return context
    }
    private func call<T: Decodable>(_ request: [String: JSONValue], as type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(request)
        guard data.count <= 256 * 1024 else { throw HarborError(code: "music-eq-correction") }
        let context = try prepare(); context.exception = nil
        let value = context.objectForKeyedSubscript("harborMusicParametricEQ")?.call(withArguments: [String(decoding: data, as: UTF8.self)])
        guard context.exception == nil, let raw = value?.toString(), let bytes = raw.data(using: .utf8),
              bytes.count <= 128 * 1024 else { throw HarborError(code: "music-eq-correction") }
        return try JSONDecoder().decode(type, from: bytes)
    }
    func importText(_ text: String) throws -> MusicEQCorrection {
        guard text.utf16.count <= 32768 else { throw HarborError(code: "music-eq-correction") }
        return try call(["operation": .string("import"), "text": .string(text)], as: MusicEQCorrection.self)
    }
    func exportText(_ settings: MusicAudioOptions) throws -> String {
        try call(["operation": .string("export"), "settings": try .encoded(settings)], as: String.self)
    }
    func response(_ settings: MusicAudioOptions, applied: MusicAudioOptions) throws -> MusicEQResponse {
        try call(["operation": .string("response"), "settings": try .encoded(settings), "applied": try .encoded(applied)], as: MusicEQResponse.self)
    }
}
