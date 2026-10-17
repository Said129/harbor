import Foundation

struct SubtitleRequest: Sendable {
    let media: Media
    let videoID: String
    let season: Int?
    let episode: Int?
    let addons: [Addon]
    let stream: JSONValue

    var extras: String {
        let hints = stream["behaviorHints"]
        var values: [String: String] = [:]
        if let hash = hints["videoHash"].string, !hash.isEmpty { values["videoHash"] = hash }
        if let size = hints["videoSize"].integer, size > 0 { values["videoSize"] = String(size) }
        if let name = hints["filename"].string ?? hints["fileName"].string, !name.isEmpty { values["filename"] = name }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return values.sorted { $0.key < $1.key }.map { $0.key + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }.joined(separator: "&")
    }

    func plans() async throws -> [RequestPlan] {
        var plans: [RequestPlan] = []
        let kind = media.type == "anime" ? "series" : media.type
        for id in StreamRequestPolicy.ids(media, videoID: videoID, season: season, episode: episode) {
            let requested: [RequestPlan] = try await CoreBridge().call("resources", ["addons": try .encoded(addons), "resource": .string("subtitles"), "kind": .string(kind), "id": .string(id)])
            plans += requested
        }
        let extra = extras
        return StreamRequestPolicy.plans(plans).map { plan in
            guard !extra.isEmpty, var url = URLComponents(string: plan.url), url.percentEncodedPath.hasSuffix(".json") else { return plan }
            url.percentEncodedPath = String(url.percentEncodedPath.dropLast(5)) + "/" + extra + ".json"
            return RequestPlan(key: plan.key, url: url.string ?? plan.url, title: plan.title, kind: plan.kind, addon: plan.addon, addonPriority: plan.addonPriority, timeoutMs: plan.timeoutMs, catalog: nil)
        }
    }
}

extension PlaybackSource.Subtitle {
    func matchesFilename(_ value: String) -> Bool {
        if value == url { return true }
        guard let target = URL(string: url), target.isFileURL else { return false }
        let candidate = value.hasPrefix("file:") ? URL(string: value) : URL(fileURLWithPath: value)
        return candidate?.standardizedFileURL == target.standardizedFileURL
    }
}

struct SubtitleAddonService: Sendable {
    struct Result: Sendable {
        var subtitles: [PlaybackSource.Subtitle] = []
        var failures = 0
        var providers = 0
    }

    func search(_ request: SubtitleRequest, onBatch: (@MainActor @Sendable ([PlaybackSource.Subtitle]) -> Void)? = nil,
                load: @escaping @Sendable (RequestPlan) async throws -> JSONValue = { try await HTTPClient().json($0.url, timeout: Double($0.timeoutMs) / 1000) }) async throws -> Result {
        let plans = try await request.plans()
        return try await withThrowingTaskGroup(of: (RequestPlan, JSONValue?).self) { group in
            var iterator = plans.makeIterator()
            func enqueue(_ plan: RequestPlan) {
                group.addTask {
                    do { return (plan, try await load(plan)) }
                    catch is CancellationError { throw CancellationError() }
                    catch { return (plan, nil) }
                }
            }
            for _ in 0..<6 { if let plan = iterator.next() { enqueue(plan) } }
            var result = Result(providers: Set(plans.map { $0.addon.id }).count)
            var seen = Set<String>()
            for try await (plan, response) in group {
                if let response, case .array = response["subtitles"] {
                    let batch = Self.parse(response, provider: plan.title).filter { seen.insert($0.url).inserted }
                    result.subtitles += batch
                    if !batch.isEmpty { await onBatch?(batch) }
                } else { result.failures += 1 }
                if let next = iterator.next() { enqueue(next) }
            }
            try Task.checkCancellation()
            return result
        }
    }

    static func parse(_ response: JSONValue, provider: String) -> [PlaybackSource.Subtitle] {
        response["subtitles"].array.prefix(1000).compactMap { value in
            guard var text = value["url"].string, var url = URLComponents(string: text) else { return nil }
            // Some addons return a Desktop streaming-server conversion URL.
            // mpv decodes the original subtitle directly on iPhone.
            if ["127.0.0.1", "localhost", "::1"].contains(url.host ?? ""), url.path == "/subtitles.vtt",
               let original = url.queryItems?.first(where: { $0.name == "from" })?.value {
                text = original
                guard let originalURL = URLComponents(string: original) else { return nil }
                url = originalURL
            }
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
                  url.user == nil, url.password == nil, text.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
            let label = value["label"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = [provider, label].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return PlaybackSource.Subtitle(url: text, lang: value["lang"].string, id: value["id"].string, title: String(title.prefix(240)))
        }
    }
}
