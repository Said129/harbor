import CryptoKit
import Foundation
import JavaScriptCore

struct SubtitlePivotCue: Codable, Sendable {
    let start: Double
    let end: Double
    let text: String

    init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

struct SubtitlePivotWorkflowInput: Codable, Sendable {
    let audioLanguage: String
    let subtitleLanguage: String
    let targetCues: [SubtitlePivotCue]
    let targetHealthy: Bool
    let targetFormatSafe: Bool
    let calibrationReady: Bool
    let maxCandidates: Int?
    let bestEffort: Bool?

    init(
        audioLanguage: String,
        subtitleLanguage: String,
        targetCues: [SubtitlePivotCue],
        targetHealthy: Bool,
        targetFormatSafe: Bool,
        calibrationReady: Bool,
        maxCandidates: Int? = nil,
        bestEffort: Bool? = nil
    ) {
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
        self.targetCues = targetCues
        self.targetHealthy = targetHealthy
        self.targetFormatSafe = targetFormatSafe
        self.calibrationReady = calibrationReady
        self.maxCandidates = maxCandidates
        self.bestEffort = bestEffort
    }
}

struct SubtitlePivotNativeRequest: Codable, Sendable {
    let id: String
    let operation: String
    let payload: JSONValue
}

struct SubtitlePivotWorkflowState: Codable, Sendable {
    let status: String
    let request: SubtitlePivotNativeRequest?
    let result: JSONValue?
    let error: String?
    let accepted: Bool?
}

/// Runs Desktop's pure cross-language pivot workflow in JavaScriptCore. Provider
/// search, subtitle preparation, and audio measurement are request/response ports.
actor SubtitlePivotWorkflow {
    private let context: JSContext

    init() throws {
        context = try Self.makeContext()
    }

    func start(
        _ input: SubtitlePivotWorkflowInput,
        validateTargetAgainstAudio: Bool = true
    ) throws -> SubtitlePivotWorkflowState {
        try call("start", fields: [
            "input": try foundationObject(input),
            "validateTargetAgainstAudio": validateTargetAgainstAudio,
        ])
    }

    /// Resolves one native port result. Read state using `drain()` in the next
    /// JavaScriptCore call so queued Promise jobs can issue the next port.
    func complete(requestID: String, result: JSONValue) throws -> Bool {
        let data = try JSONEncoder().encode(result)
        guard data.count <= 8 * 1_024 * 1_024,
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { throw HarborError(code: "subtitle-pivot-workflow") }
        let response = try call("complete", fields: ["requestID": requestID, "result": value])
        return response.accepted ?? false
    }

    func reject(requestID: String) throws -> Bool {
        try call("reject", fields: ["requestID": requestID]).accepted ?? false
    }

    func drain() throws -> SubtitlePivotWorkflowState {
        try call("drain")
    }

    func cancel() throws -> SubtitlePivotWorkflowState {
        try call("cancel")
    }

    func arabicCueHealth(rawText: String, cues: [SubtitlePivotCue]) throws -> Bool {
        let response = try callRaw("arabicCueHealth", fields: [
            "rawText": rawText,
            "cues": try foundationObject(cues),
        ])
        return try response["healthy"].decoded(Bool.self)
    }

    func releaseConfidences(hints: JSONValue, subtitleTexts: [String]) throws -> [String] {
        let response = try callRaw("releaseConfidences", fields: [
            "hints": try foundationObject(hints), "subtitleTexts": subtitleTexts,
        ])
        return try response["values"].decoded([String].self)
    }

    private func call(
        _ operation: String,
        fields: [String: Any] = [:]
    ) throws -> SubtitlePivotWorkflowState {
        try callRaw(operation, fields: fields).decoded(SubtitlePivotWorkflowState.self)
    }

    private func callRaw(
        _ operation: String,
        fields: [String: Any] = [:]
    ) throws -> JSONValue {
        var request: [String: Any] = ["operation": operation]
        for (key, value) in fields { request[key] = value }
        let requestData = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        guard requestData.count <= 8 * 1_024 * 1_024 else { throw HarborError(code: "subtitle-pivot-workflow") }
        context.exception = nil
        let rawRequest = String(decoding: requestData, as: UTF8.self)
        guard let result = context.objectForKeyedSubscript("harborSubtitlePivotWorkflow")?.call(withArguments: [rawRequest]),
              context.exception == nil,
              let raw = result.toString(), let data = raw.data(using: .utf8), data.count <= 16 * 1_024 * 1_024
        else { throw HarborError(code: "subtitle-pivot-workflow") }
        do { return try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw HarborError(code: "subtitle-pivot-workflow") }
    }

    private func foundationObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 8 * 1_024 * 1_024,
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { throw HarborError(code: "subtitle-pivot-workflow") }
        return object
    }

    private static func makeContext() throws -> JSContext {
        guard let url = Bundle.main.url(forResource: "SubtitlePivotWorkflowAssets", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 1_024 * 1_024,
              let asset = try? JSONDecoder().decode(JSONValue.self, from: data),
              asset["schema"].integer == 1,
              asset["reference"].string == "0834340cec5531650bfe78cd628628702e636987",
              asset["inputs"].objectValue.count == 7,
              asset["pure_workflow_with_native_ports"] == .bool(true),
              asset["held_out_audio_is_native_only"] == .bool(true),
              let source = asset["program"]["source"].string,
              let expected = asset["program"]["sha256"].string,
              SHA256.hash(data: Data(source.utf8)).map({ String(format: "%02x", $0) }).joined() == expected,
              expected == "7996065a3033a92ad9d305384dd165b97b79e0d84b6ebb9932c5b8db5dd2db74",
              source.utf8.count <= 1_024 * 1_024,
              let context = JSContext()
        else { throw HarborError(code: "subtitle-pivot-workflow") }
        context.evaluateScript(source)
        guard context.exception == nil,
              context.objectForKeyedSubscript("harborSubtitlePivotWorkflow")?.isUndefined == false
        else { throw HarborError(code: "subtitle-pivot-workflow") }
        return context
    }
}
