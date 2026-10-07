import Foundation

/// Public discovery only. Installation still fetches and validates the live manifest.
actor AddonDirectory {
    static let shared = AddonDirectory()
    static let sources = [
        "https://v3-cinemeta.strem.io/addon_catalog/all/community.json",
        "https://v3-cinemeta.strem.io/addon_catalog/all/official.json",
        "https://api.strem.io/addonsofficialcollection.json"
    ]
    struct Result: Sendable { let addons: [Addon]; let failedSources: Int }
    private var cached: [String: [Addon]] = [:]
    private var refreshed: Date?

    func load(refresh: Bool = false) async throws -> Result {
        if !refresh, let refreshed, Date().timeIntervalSince(refreshed) < 900 { return Result(addons: merged(), failedSources: 0) }
        let responses = try await withThrowingTaskGroup(of: (String, [Addon]?).self) { group in
            for source in Self.sources {
                group.addTask {
                    do {
                        let json = try await HTTPClient().json(source)
                        return (source, try await Self.parse(json))
                    } catch is CancellationError { throw CancellationError() }
                    catch { return (source, nil) }
                }
            }
            var results: [(String, [Addon]?)] = []
            for try await response in group { results.append(response) }
            return results
        }
        try Task.checkCancellation()
        for (source, addons) in responses { if let addons { cached[source] = addons } }
        let failures = responses.filter { $0.1 == nil }.count
        if failures == 0 { refreshed = Date() }
        return Result(addons: merged(), failedSources: failures)
    }
    private func merged() -> [Addon] {
        var seen = Set<String>()
        return Self.sources.flatMap { cached[$0] ?? [] }.filter { seen.insert($0.manifest["id"].string ?? "").inserted }
    }
    static func parse(_ json: JSONValue) async throws -> [Addon] {
        let rows: [JSONValue]
        if case .array(let values) = json { rows = values }
        else if case .array(let values) = json["addons"] { rows = values }
        else { throw HarborError(code: "addon-directory-response") }
        var result: [Addon] = [], seen = Set<String>()
        for row in rows.prefix(1_000) {
            try Task.checkCancellation()
            guard let url = row["transportUrl"].string, let id = row["manifest"]["id"].string, !id.isEmpty,
                  let parts = URLComponents(string: url), parts.user == nil, parts.password == nil,
                  parts.scheme?.lowercased() == "https", parts.host != nil else { continue }
            do {
                let addon: Addon = try await CoreBridge().call("installAddon", ["url": .string(url), "manifest": row["manifest"]])
                if seen.insert(id).inserted { result.append(addon) }
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        guard rows.isEmpty || !result.isEmpty else { throw HarborError(code: "addon-directory-response") }
        return result
    }
}

enum AddonCategory: String, CaseIterable, Identifiable {
    case all, streams, metadata, subtitles, anime, sports, television, tools, adult
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Todos"
        case .streams: "Streaming"
        case .metadata: "Catálogos"
        case .subtitles: "Subtítulos"
        case .anime: "Anime"
        case .sports: "Deportes"
        case .television: "TV en directo"
        case .tools: "Herramientas"
        case .adult: "Adultos"
        }
    }
}
extension Addon {
    var resources: [String] { manifest["resources"].array.compactMap { $0.string ?? $0["name"].string } }
    var types: [String] { manifest["types"].array.compactMap(\.string) }
    var adult: Bool { manifest["behaviorHints"]["adult"] == .bool(true) || AddonAdultRules.matches([manifest["id"].string ?? "", name]) }
    var category: AddonCategory {
        if adult { return .adult }
        let text = [name, manifest["description"].string ?? "", manifest["id"].string ?? ""].joined(separator: " ").lowercased()
        let prefixes = manifest["idPrefixes"].array.compactMap(\.string)
        if prefixes.contains(where: { $0.hasPrefix("kitsu") || $0.hasPrefix("mal") || $0.hasPrefix("anidb") }) || text.range(of: #"\banime\b|\bkitsu\b|\bmal\b|\bjikan\b|\bmyanimelist\b|\banidb\b|\banilist\b|\bmanga\b"#, options: .regularExpression) != nil {
            if !Set(resources).isDisjoint(with: ["stream", "meta", "catalog"]) { return .anime }
        }
        if types.contains("tv") || types.contains("channel") || text.range(of: #"\biptv\b|\blive\s*tv\b|\bchannel\b|\bm3u\b|\bplutotv\b|\bpluto\.tv\b|\busatv\b|\bota\b|\bbroadcast\b"#, options: .regularExpression) != nil { return .television }
        if text.range(of: #"\bsports?\b|\bnfl\b|\bnba\b|\bnhl\b|\bmlb\b|\bsoccer\b|\bfootball\b|\bf1\b|\bformula\s*1\b|\bcricket\b|\bbasketball\b|\bufc\b|\bmma\b|\bwwe\b|\bdazn\b|\besports?\b|\bsporttv\b|\bdaddylive\b"#, options: .regularExpression) != nil { return .sports }
        if resources.contains("subtitles") { return .subtitles }
        if resources.contains("stream") { return .streams }
        if resources.contains("catalog") || resources.contains("meta") { return .metadata }
        return .tools
    }
}
private struct AddonAdultRules: Decodable {
    let substrings: [String]
    let words: [String]
    let replacements: [String: String]
    private static let rules: Self? = {
        guard let url = Bundle.main.url(forResource: "AddonAdultRules", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()
    static func matches(_ fields: [String]) -> Bool {
        // Fail closed for public discovery if the bundled Desktop filter is missing.
        guard let rules else { return true }
        let normalized = fields.map { field in
            field.decomposedStringWithCompatibilityMapping.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased().map { rules.replacements[String($0)] ?? String($0) }.joined()
        }
        let compact = normalized.map { $0.filter { $0.isASCII && $0.isLetter } }.joined(separator: " ")
        if rules.substrings.contains(where: compact.contains) { return true }
        let tokens = Set(normalized.flatMap { $0.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.map(String.init) })
        return !tokens.isDisjoint(with: rules.words)
    }
}
