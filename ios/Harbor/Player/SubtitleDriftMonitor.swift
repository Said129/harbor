import CryptoKit
import Foundation
import JavaScriptCore

struct SubtitleDriftCue: Codable, Sendable {
    let startSec: Double
    let endSec: Double
}

struct SubtitleDriftInterval: Codable, Sendable {
    let startSec: Double
    let endSec: Double

    init(startSec: Double, endSec: Double) {
        self.startSec = startSec
        self.endSec = endSec
    }

    init(_ interval: (Double, Double)) {
        self.init(startSec: interval.0, endSec: interval.1)
    }
}

struct SubtitleDriftSnapshot: Codable, Sendable {
    let trackKey: String
    let positionSec: Double
    let durationSec: Double
    let subDelaySec: Double
    let playing: Bool
    let buffering: Bool
    let rate: Double
    var cues: [SubtitleDriftCue]?
    var nowMs: Double?

    init(
        trackKey: String,
        positionSec: Double,
        durationSec: Double,
        subDelaySec: Double,
        playing: Bool,
        buffering: Bool,
        rate: Double,
        cues: [SubtitleDriftCue]? = nil,
        nowMs: Double? = nil
    ) {
        self.trackKey = trackKey
        self.positionSec = positionSec
        self.durationSec = durationSec
        self.subDelaySec = subDelaySec
        self.playing = playing
        self.buffering = buffering
        self.rate = rate
        self.cues = cues
        self.nowMs = nowMs
    }
}

enum SubtitleDriftResetReason: String, Codable, Sendable {
    case identity
    case seek
}

struct SubtitleDriftSampleRequest: Codable, Sendable {
    let id: String
    let startSec: Double
    let lenSec: Double
}

struct SubtitleDriftCorrectionOffer: Codable, Sendable {
    let residualSec: Double
    let stepSec: Double
    let pCorrect: Double
}

struct SubtitleDriftMonitorState: Codable, Sendable {
    let status: String
    let sampleRequest: SubtitleDriftSampleRequest?
    let correction: SubtitleDriftCorrectionOffer?
    let appliedDelaySec: Double?
    let correctionTotalSec: Double
    let accepted: Bool?
}

/// JavaScriptCore binding for Desktop's pure online subtitle drift estimator.
/// Speech decoding and applying the returned delay remain native responsibilities.
@MainActor final class SubtitleDriftMonitor {
    private let context: JSContext

    init() throws {
        context = try Self.makeContext()
    }

    func reset(
        _ snapshot: SubtitleDriftSnapshot,
        reason: SubtitleDriftResetReason = .identity
    ) throws -> SubtitleDriftMonitorState {
        try call("reset", snapshot: snapshot, fields: ["reason": reason.rawValue])
    }

    func observe(_ snapshot: SubtitleDriftSnapshot) throws -> SubtitleDriftMonitorState {
        try call("observe", snapshot: snapshot)
    }

    /// Resolves a native speech request. Call `drain` in the next JavaScriptCore
    /// turn before reading the monitor state so Promise jobs have completed.
    func completeSpeech(
        requestID: String,
        intervals: [SubtitleDriftInterval],
        currentSnapshot: SubtitleDriftSnapshot? = nil
    ) throws -> Bool {
        let data = try JSONEncoder().encode(intervals)
        guard data.count <= 2 * 1_024 * 1_024,
              let values = try JSONSerialization.jsonObject(with: data) as? [[String: Double]]
        else { throw HarborError(code: "subtitle-drift-monitor") }
        let response = try callRaw(
            "completeSpeech",
            snapshot: currentSnapshot,
            fields: ["requestID": requestID, "intervals": values]
        )
        return response["accepted"] == .bool(true)
    }

    func rejectSpeech(
        requestID: String,
        currentSnapshot: SubtitleDriftSnapshot? = nil
    ) throws -> Bool {
        let response = try callRaw("rejectSpeech", snapshot: currentSnapshot, fields: ["requestID": requestID])
        return response["accepted"] == .bool(true)
    }

    func drain(_ snapshot: SubtitleDriftSnapshot? = nil) throws -> SubtitleDriftMonitorState {
        try call("drain", snapshot: snapshot)
    }

    /// Accepts the current offer against the latest player snapshot. The write
    /// is captured and returned; JavaScript never mutates the native player.
    func applyPending(_ snapshot: SubtitleDriftSnapshot) throws -> SubtitleDriftMonitorState {
        try call("applyPending", snapshot: snapshot)
    }

    private func call(
        _ operation: String,
        snapshot: SubtitleDriftSnapshot?,
        fields: [String: Any] = [:]
    ) throws -> SubtitleDriftMonitorState {
        try callRaw(operation, snapshot: snapshot, fields: fields).decoded(SubtitleDriftMonitorState.self)
    }

    private func callRaw(
        _ operation: String,
        snapshot: SubtitleDriftSnapshot?,
        fields: [String: Any]
    ) throws -> JSONValue {
        var request: [String: Any] = ["operation": operation]
        if let snapshot {
            let data = try JSONEncoder().encode(snapshot)
            guard data.count <= 8 * 1_024 * 1_024,
                  let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw HarborError(code: "subtitle-drift-monitor") }
            request["snapshot"] = value
        }
        for (key, value) in fields { request[key] = value }
        let requestData = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        guard requestData.count <= 8 * 1_024 * 1_024 else { throw HarborError(code: "subtitle-drift-monitor") }
        context.exception = nil
        let rawRequest = String(decoding: requestData, as: UTF8.self)
        guard let result = context.objectForKeyedSubscript("harborSubtitleDriftMonitor")?.call(withArguments: [rawRequest]),
              context.exception == nil,
              let raw = result.toString(), let data = raw.data(using: .utf8), data.count <= 1_024 * 1_024
        else { throw HarborError(code: "subtitle-drift-monitor") }
        do { return try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw HarborError(code: "subtitle-drift-monitor") }
    }

    private static func makeContext() throws -> JSContext {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: "SubtitleDriftMonitorAssets", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 512 * 1_024,
              let asset = try? JSONDecoder().decode(JSONValue.self, from: data),
              asset["schema"].integer == 1,
              asset["reference"].string == "0834340cec5531650bfe78cd628628702e636987",
              asset["inputs"].objectValue.count == 4,
              asset["pure_monitor_no_tauri_or_io"] == .bool(true),
              let source = asset["program"]["source"].string,
              let expected = asset["program"]["sha256"].string,
              SHA256.hash(data: Data(source.utf8)).map({ String(format: "%02x", $0) }).joined() == expected,
              expected == "b2f6e1e6fcd6dc5cb14e28e7deaf937e84e902356fb65cf94f496ede54b6f1b0",
              source.utf8.count <= 512 * 1_024,
              let context = JSContext()
        else { throw HarborError(code: "subtitle-drift-monitor") }
        context.evaluateScript(source)
        guard context.exception == nil,
              context.objectForKeyedSubscript("harborSubtitleDriftMonitor")?.isUndefined == false
        else { throw HarborError(code: "subtitle-drift-monitor") }
        return context
    }
}
