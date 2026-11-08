import CryptoKit
import Foundation

/// Desktop's community sync (`lib/subtitles/autosync/crowd-db.ts`) as pure rules: the sub-timeline hash, the lookup and
/// report requests and their checks. Nothing here touches the network; `CommunitySyncClient` does.
enum CommunitySyncRules {
    static let defaultServer = "https://sync.harbor.site"
    static let minCues = 8
    /// Desktop asks for 4 s, but its port is bounded at 3 s, so 3 s is the limit a user sees.
    static let lookupTimeout: TimeInterval = 3
    static let reportTimeout: TimeInterval = 8
    static let minReportConfidence = 0.85
    static let minDurationMs = 60_000
    static let maxOffsetMs = 60_000
    static let ratioRange: ClosedRange<Double> = 0.8...1.25
    static let positiveTTL: TimeInterval = 10 * 60
    static let negativeTTL: TimeInterval = 5 * 60

    /// Desktop's `Math.round`: halves go up.
    static func jsRound(_ value: Double) -> Double { (value + 0.5).rounded(.down) }

    /// Whole milliseconds, or nil when the seconds are not finite or too large to be a time.
    static func milliseconds(_ seconds: Double) -> Int? {
        let ms = jsRound(seconds * 1_000)
        guard ms.isFinite, abs(ms) < 1e15 else { return nil }
        return Int(ms)
    }

    /// Desktop's `subTimelineHash`: each cue is rounded to 10 ms (`Math.round(seconds * 100) * 10`), the cues are sorted,
    /// joined as "start-end" with ";" and hashed with SHA-256. Nil with fewer than eight finite cues.
    static func subTimelineHash(_ cues: [(Double, Double)]) -> String? {
        let usable = cues.filter { $0.0.isFinite && $0.1.isFinite }
        guard usable.count >= minCues else { return nil }
        var pairs: [(Int, Int)] = []
        for cue in usable {
            let start = jsRound(cue.0 * 100) * 10, end = jsRound(cue.1 * 100) * 10
            guard abs(start) < 1e15, abs(end) < 1e15 else { return nil }
            pairs.append((Int(start), Int(end)))
        }
        let text = pairs.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            .map { "\($0.0)-\($0.1)" }
            .joined(separator: ";")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", Int($0)) }.joined()
    }

    /// The server root without trailing slashes, or nil unless the text is an http or https address with a host.
    static func serverRoot(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        var root = trimmed
        while root.hasSuffix("/") { root.removeLast() }
        return root
    }

    /// The value to store for a typed server address. Blank means Harbor's own server. Nil when the address is invalid.
    static func storedServer(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return serverRoot(trimmed) == nil ? nil : trimmed
    }

    /// Desktop's `lookupCrowdSync` request: `GET <server>/api/v1/lookup?sub=<hash>&dur=<ms>`. `dur` is sent only when positive.
    /// `mh` is left out because iOS has no movie hash.
    static func lookupURL(server: String, cues: [(Double, Double)], durationSec: Double) -> URL? {
        guard let root = serverRoot(server), let sub = subTimelineHash(cues) else { return nil }
        var items = [URLQueryItem(name: "sub", value: sub)]
        if let ms = milliseconds(durationSec), ms > 0 { items.append(URLQueryItem(name: "dur", value: String(ms))) }
        var components = URLComponents(string: root + "/api/v1/lookup")
        components?.queryItems = items
        return components?.url
    }

    /// One lookup answer, as Desktop's `toCrowdResult` reads it for an affine (offset and ratio) answer.
    struct Lookup: Equatable, Sendable {
        let tier: String
        let offset: Double
        let ratio: Double
        let confidence: Double
    }

    /// Desktop's `toCrowdResult`. Only tiers A, B and C are kept. Piecewise answers (two or more usable anchors) give
    /// nil, because iOS applies only an affine offset and ratio.
    static func lookupResult(_ body: Data) -> Lookup? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        guard let tier = object["tier"] as? String, ["A", "B", "C"].contains(tier) else { return nil }
        if let anchors = object["anchors"] as? [Any] {
            var usable = 0
            for case let pair as [Any] in anchors where pair.count >= 2 && number(pair[0]) != nil && number(pair[1]) != nil {
                usable += 1
            }
            if usable >= 2 { return nil }
        }
        guard let offsetMs = number(object["offsetMs"]), let confidenceRaw = number(object["confidence"]) else { return nil }
        let ratio: Double
        if isMissing(object["ratio"]) { ratio = 1 } else if let value = number(object["ratio"]) { ratio = value } else { return nil }
        let confidence = min(1, max(0, confidenceRaw))
        guard confidence > 0 else { return nil }
        return Lookup(tier: tier, offset: offsetMs / 1_000, ratio: ratio, confidence: confidence)
    }

    /// The timing a lookup may apply by itself. Desktop applies a crowd result without its audio check only at tier A,
    /// where the match is an exact identity. B and C still need Desktop's audio gate, which a lookup alone cannot run,
    /// so they are not applied here. The offset and ratio must also sit inside the report limits.
    static func autoApplied(_ lookup: Lookup) -> SubtitleSyncResult? {
        guard lookup.tier == "A", abs(lookup.offset) * 1_000 <= Double(maxOffsetMs), ratioRange.contains(lookup.ratio),
              lookup.confidence > 0 else { return nil }
        return SubtitleSyncResult(offset: lookup.offset, ratio: lookup.ratio, confidence: lookup.confidence)
    }

    /// Desktop's `reportVerifiedSync` body, or nil when Desktop would not report: confidence at least 0.85, a video of at
    /// least 60 s, an offset within 60 s and a ratio between 0.8 and 1.25. Movie hash, IMDb id, chromaprint, subtitle file
    /// hash, client id and app version are left out because iOS does not have them at this point.
    static func reportBody(cues: [(Double, Double)], durationSec: Double, result: SubtitleSyncResult) -> [String: Any]? {
        guard result.confidence.isFinite, result.confidence >= minReportConfidence,
              let durationMs = milliseconds(durationSec), durationMs >= minDurationMs,
              let offsetMs = milliseconds(result.offset), abs(offsetMs) <= maxOffsetMs,
              result.ratio.isFinite, ratioRange.contains(result.ratio),
              let sub = subTimelineHash(cues) else { return nil }
        return [
            "subTimelineHash": sub,
            "durationMs": durationMs,
            "offsetMs": offsetMs,
            "ratio": result.ratio,
            "confidence": min(1, result.confidence),
        ]
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? Double, number.isFinite else { return nil }
        return number
    }

    private static func isMissing(_ value: Any?) -> Bool {
        guard let value else { return true }
        return value is NSNull
    }
}

/// The network call behind community sync: the status and body of one request.
protocol CommunitySyncTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (status: Int, body: Data)
}

struct CommunitySyncURLTransport: CommunitySyncTransport {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        let (body, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HarborError(code: "network") }
        return (http.statusCode, body)
    }
}

/// Desktop's lookup cache and report calls. A hit is kept for ten minutes and a miss for five. A failed request is not kept.
actor CommunitySyncClient {
    static let shared = CommunitySyncClient(transport: CommunitySyncURLTransport())

    private let transport: any CommunitySyncTransport
    private let clock: @Sendable () -> Date
    private var answers: [String: (expires: Date, value: CommunitySyncRules.Lookup?)] = [:]

    init(transport: any CommunitySyncTransport, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.clock = clock
    }

    /// Desktop's `lookupCrowdSync`. Nil when there is no answer, when the request fails (not kept) or when the server has none (kept).
    func lookup(cues: [(Double, Double)], durationSec: Double, server: String) async -> CommunitySyncRules.Lookup? {
        guard let url = CommunitySyncRules.lookupURL(server: server, cues: cues, durationSec: durationSec) else { return nil }
        let key = url.absoluteString
        let now = clock()
        if let cached = answers[key], cached.expires > now { return cached.value }
        var request = URLRequest(url: url, timeoutInterval: CommunitySyncRules.lookupTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let reply = try? await transport.send(request) else { return nil }
        var value: CommunitySyncRules.Lookup?
        if reply.status != 204, (200..<300).contains(reply.status) {
            value = CommunitySyncRules.lookupResult(reply.body)
        }
        let ttl = value == nil ? CommunitySyncRules.negativeTTL : CommunitySyncRules.positiveTTL
        answers[key] = (now.addingTimeInterval(ttl), value)
        return value
    }

    /// Desktop's `reportVerifiedSync`. True only when the server answers `accepted: true`.
    func report(cues: [(Double, Double)], durationSec: Double, result: SubtitleSyncResult, server: String) async -> Bool {
        guard let root = CommunitySyncRules.serverRoot(server),
              let body = CommunitySyncRules.reportBody(cues: cues, durationSec: durationSec, result: result),
              let url = URL(string: root + "/api/v1/report"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        var request = URLRequest(url: url, timeoutInterval: CommunitySyncRules.reportTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data
        guard let reply = try? await transport.send(request), (200..<300).contains(reply.status),
              let object = try? JSONSerialization.jsonObject(with: reply.body) as? [String: Any] else { return false }
        return (object["accepted"] as? Bool) == true
    }
}

/// The settings-aware entry points used by `SubtitleAutoSync`. Private mode or the setting turns every request off.
enum CommunitySync {
    static let crowdKey = "subtitleAutoSyncCrowd"
    static let serverKey = "communitySyncUrl"
    static let privateKey = "communitySyncOptOut"

    /// Desktop: `subtitleAutoSyncCrowd !== false`, and `communitySyncOptOut` is off.
    static func enabled(_ defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: crowdKey) as? Bool ?? true) && !defaults.bool(forKey: privateKey)
    }

    /// The stored server, or Harbor's own server when none is stored. An invalid stored address gives no requests.
    static func server(_ defaults: UserDefaults = .standard) -> String? {
        let stored = (defaults.string(forKey: serverKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? CommunitySyncRules.defaultServer : stored
    }

    /// The timing from the community database when it can be applied without analysing the audio, or nil.
    static func communityTiming(cues: [(Double, Double)], durationSec: Double, defaults: UserDefaults = .standard,
                                client: CommunitySyncClient = .shared) async -> SubtitleSyncResult? {
        guard enabled(defaults), let server = server(defaults),
              let lookup = await client.lookup(cues: cues, durationSec: durationSec, server: server) else { return nil }
        return CommunitySyncRules.autoApplied(lookup)
    }

    /// Reports a verified audio result. Returns at once; the sync never waits for the report or fails because of it.
    static func reportInBackground(cues: [(Double, Double)], durationSec: Double, result: SubtitleSyncResult,
                                   defaults: UserDefaults = .standard, client: CommunitySyncClient = .shared) {
        Task.detached(priority: .utility) {
            _ = await CommunitySync.reportAudioResult(cues: cues, durationSec: durationSec, result: result, defaults: defaults, client: client)
        }
    }

    static func reportAudioResult(cues: [(Double, Double)], durationSec: Double, result: SubtitleSyncResult,
                                  defaults: UserDefaults = .standard, client: CommunitySyncClient = .shared) async -> Bool {
        guard enabled(defaults), let server = server(defaults) else { return false }
        return await client.report(cues: cues, durationSec: durationSec, result: result, server: server)
    }
}
