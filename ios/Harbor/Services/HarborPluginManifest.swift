import Foundation

enum HarborStreamPluginFormat: String, Codable, Sendable { case harbor, providerScript = "provider-script", androidExtension = "android-extension" }

struct HarborStreamPluginEntry: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var version: String
    var entry: String
    var sha256: String?
    var icon: String?
    var description: String?
    var author: String?
    var lang: [String]
    var types: [String]
    var idPrefixes: [String]
    var hosts: [String]
    var settings: Bool
    var nsfw: Bool
    var enabled: Bool
    var platforms: [String]?
    var minHarbor: String?
    var timeoutMs: Double?
    var format: HarborStreamPluginFormat
    var note: String?
}

struct HarborParsedStreamRepository: Codable, Equatable, Sendable {
    var name: String
    var homepage: String?
    var format: HarborStreamPluginFormat
    var entries: [HarborStreamPluginEntry]
    var lists: [String]?
}

struct HarborPluginRepositoryError: Error, Equatable, Sendable {
    let code: String
    init(_ code: String) { self.code = code }
}

/// Matches streams/plugins/manifest.ts at the pinned 0.9.132 reference.
/// Parsing does not authorize network access or make Android bytecode executable.
enum HarborPluginManifest {
    static func splitLinks(_ text: String) -> [String] {
        unique(text.components(separatedBy: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))).filter { !$0.isEmpty })
    }

    static func normalizeURL(_ raw: String) throws -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw HarborPluginRepositoryError("only-https") }
        if text.range(of: "^cloudstreamrepo://", options: [.regularExpression, .caseInsensitive]) != nil { throw HarborPluginRepositoryError("android-extensions") }
        if text.range(of: "^[a-z][a-z0-9+.-]*://", options: [.regularExpression, .caseInsensitive]) == nil { text = "https://" + text }
        guard let url = URL(string: text, encodingInvalidCharacters: false), var parts = URLComponents(url: url.standardized, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty else { throw HarborPluginRepositoryError("only-https") }
        parts.scheme = "https"; parts.host = host.lowercased(); parts.fragment = nil
        if parts.port == 443 { parts.port = nil }
        if host.lowercased() == "github.com" {
            let segments = parts.percentEncodedPath.split(separator: "/").map(String.init)
            if segments.count >= 2 {
                let repository = segments[1].hasSuffix(".git") ? String(segments[1].dropLast(4)) : segments[1]
                var rawParts = URLComponents(string: "https://raw.githubusercontent.com")!
                let branchPath: [String]
                if segments.count >= 4 && ["tree", "blob"].contains(segments[2]) { branchPath = Array(segments.dropFirst(3)) }
                else { branchPath = ["HEAD"] + Array(segments.dropFirst(2)) }
                rawParts.percentEncodedPath = "/" + ([segments[0], repository] + branchPath).joined(separator: "/")
                rawParts.percentEncodedQuery = parts.percentEncodedQuery; parts = rawParts
            }
        }
        if !parts.path.lowercased().hasSuffix(".json") {
            parts.percentEncodedPath = parts.percentEncodedPath.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) + "/manifest.json"
        }
        guard let result = parts.url?.absoluteString else { throw HarborPluginRepositoryError("only-https") }
        return result
    }

    static func candidates(_ url: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: "^(https://raw\\.githubusercontent\\.com/[^/]+/[^/]+/)HEAD/(.*)$"),
              let match = expression.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let prefix = Range(match.range(at: 1), in: url), let suffix = Range(match.range(at: 2), in: url) else { return [url] }
        return [String(url[prefix]) + "main/" + String(url[suffix]), String(url[prefix]) + "master/" + String(url[suffix]), url]
    }

    static func displayName(_ url: String) -> String {
        guard let parts = URLComponents(string: url), let host = parts.host?.lowercased() else { return url }
        let segments = parts.path.split(separator: "/").map(String.init)
        if (host.hasSuffix("githubusercontent.com") || host == "github.com" || host.hasSuffix("gitlab.com")), segments.count >= 2 {
            return segments[0] + "/" + segments[1].replacingOccurrences(of: "\\.git$", with: "", options: .regularExpression)
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func pluginID(repository: String, entry: String) -> String {
        var hash: UInt32 = 0x811c9dc5
        // JavaScript charCodeAt hashes UTF-16 code units, not Swift graphemes or UTF-8.
        for unit in repository.utf16 { hash = (hash ^ UInt32(unit)) &* 0x01000193 }
        return "plugin:" + String(hash, radix: 36) + "." + entry
    }

    static func parse(_ value: JSONValue, url: String) throws -> HarborParsedStreamRepository {
        let json = value.objectValue
        let name = string(json["name"])
        let title = name.isEmpty || name == "Repository" ? displayName(url) : name
        let homepage = optionalString(json["homepage"])
        let rows = value.array
        if case .array(let scrapers) = json["scrapers"] {
            return .init(name: title, homepage: homepage, format: .providerScript, entries: scrapers.compactMap { entry($0, url: url, provider: true) })
        }
        if case .array = value, rows.contains(where: { $0.objectValue["filename"] != nil }) {
            return .init(name: title, homepage: homepage, format: .providerScript, entries: rows.compactMap { entry($0, url: url, provider: true) })
        }
        let plugins = json["plugins"]?.array ?? []
        let nativeRows = value.array.isEmpty ? plugins : rows
        let hasLists: Bool = { if case .array = json["pluginLists"] { return true }; return false }()
        if hasLists || nativeRows.contains(where: { row in
            let object = row.objectValue
            return string(object["url"]).range(of: "\\.cs3(\\?|#|$)", options: [.regularExpression, .caseInsensitive]) != nil || (object["internalName"]?.string != nil && number(object["apiVersion"]) != nil)
        }) {
            let lists = unique((json["pluginLists"]?.array ?? []).compactMap { item -> String? in
                let path = item.string ?? string(item["url"])
                return path.isEmpty ? nil : resolve(path, url)
            })
            var seen = Set<String>()
            let entries = lists.isEmpty ? nativeRows.compactMap { nativeEntry($0, url: url) }.filter { seen.insert($0.id).inserted } : []
            return .init(name: title, homepage: homepage, format: .androidExtension, entries: entries, lists: lists)
        }
        if case .array = json["plugins"] {
            let type = string(json["type"])
            if !type.isEmpty && type != "stream" { throw HarborPluginRepositoryError(type == "ebook" ? "ebook-repo" : "manga-repo") }
            return .init(name: title, homepage: homepage, format: .harbor, entries: plugins.compactMap { entry($0, url: url, provider: false) })
        }
        if json["id"]?.string != nil, json["version"]?.string != nil, case .array = json["resources"], case .array = json["types"] { throw HarborPluginRepositoryError("stremio-addon") }
        let foreignRows = rows + (json["sources"]?.array ?? []) + (json["mangayomiSources"]?.array ?? [])
        if ["manga", "ebook"].contains(string(json["type"])) || foreignRows.contains(where: { row in
            let object = row.objectValue
            return object["sourceCodeUrl"] != nil || object["pkgPath"] != nil || (object["apk"] != nil && object["pkg"] != nil) || object["contentRating"] != nil
        }) { throw HarborPluginRepositoryError("manga-repo") }
        throw HarborPluginRepositoryError("not-a-repo")
    }

    private static func entry(_ value: JSONValue, url: String, provider: Bool) -> HarborStreamPluginEntry? {
        let object = value.objectValue
        let file = string(object[provider ? "filename" : "entry"])
        let explicitID = string(object["id"])
        let id = explicitID.isEmpty && provider ? string(object["filename"]).replacingOccurrences(of: "\\.[a-z0-9]+$", with: "", options: [.regularExpression, .caseInsensitive]) : explicitID
        let explicitName = string(object["name"])
        let name = provider && explicitName.isEmpty ? id : explicitName
        guard !id.isEmpty, !name.isEmpty, !file.isEmpty, let entry = resolve(file, url) else { return nil }
        let types = unique(strings(object[provider ? "supportedTypes" : "types"]).compactMap { type -> String? in
            switch type.lowercased() {
            case "movie", "movies", "film": return "movie"
            case "tv", "series", "show", "shows", "other": return "series"
            default: return nil
            }
        })
        let hash = string(object["sha256"])
        let prefixes = strings(object["idPrefixes"])
        let platforms = strings(object[provider ? "supportedPlatforms" : "platforms"])
        var note = strings(object["formats"])
        if note.isEmpty { note = strings(object["supportedFormats"]) }
        var notes = note.isEmpty ? [] : [note.joined(separator: ", ")]
        if object["limited"] == .bool(true) { notes.append("limited") }
        if let text = optionalString(object["notes"]) { notes.append(text) }
        let timeout = number(object["timeoutMs"])
        return .init(id: id, name: name, version: optionalString(object["version"]) ?? "0", entry: entry,
            sha256: !provider && hash.range(of: "^[0-9a-f]{64}$", options: [.regularExpression, .caseInsensitive]) != nil ? hash.lowercased() : nil,
            icon: provider ? optionalString(object["logo"]) ?? optionalString(object["icon"]) : optionalString(object["icon"]),
            description: optionalString(object["description"]), author: optionalString(object["author"]), lang: strings(object[provider ? "contentLanguage" : "lang"]),
            types: types.isEmpty ? ["movie", "series"] : types, idPrefixes: provider || prefixes.isEmpty ? ["tt", "tmdb:"] : prefixes,
            hosts: provider ? [] : strings(object["hosts"]).map { $0.lowercased() }, settings: object[provider ? "hasSettings" : "settings"] == .bool(true),
            nsfw: object["nsfw"] == .bool(true) || (provider && object["adult"] == .bool(true)), enabled: object["enabled"] != .bool(false),
            platforms: platforms.isEmpty ? nil : platforms, minHarbor: provider ? nil : optionalString(object["minHarbor"]),
            timeoutMs: !provider && (timeout ?? 0) > 0 ? min(timeout!, 60_000) : nil, format: provider ? .providerScript : .harbor,
            note: provider && !notes.isEmpty ? notes.joined(separator: " · ") : nil)
    }

    private static func nativeEntry(_ value: JSONValue, url: String) -> HarborStreamPluginEntry? {
        let object = value.objectValue
        let file = string(object["url"])
        guard !file.isEmpty, let target = resolve(file, url) else { return nil }
        let fallback = target.replacingOccurrences(of: "^.*/", with: "", options: .regularExpression).replacingOccurrences(of: "\\.[a-z0-9]+$", with: "", options: [.regularExpression, .caseInsensitive])
        let id = optionalString(object["internalName"]) ?? fallback
        guard !id.isEmpty else { return nil }
        let tvTypes = strings(object["tvTypes"])
        let types = unique(tvTypes.compactMap { text -> String? in
            let key = text.lowercased().replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
            if ["movie", "animemovie", "documentary", "torrent"].contains(key) { return "movie" }
            if ["tvseries", "anime", "ova", "cartoon", "asiandrama"].contains(key) { return "series" }
            return nil
        })
        let status = number(object["status"]) ?? 1
        var notes: [String] = status == 0 ? ["down"] : status == 2 ? ["slow"] : status == 3 ? ["beta"] : []
        if let version = number(object["apiVersion"]), version != 1 { notes.append("api " + numberText(version)) }
        let authors = strings(object["authors"])
        return .init(id: id, name: optionalString(object["name"]) ?? id,
            version: number(object["version"]).map(numberText) ?? optionalString(object["version"]) ?? "0", entry: target,
            icon: optionalString(object["iconUrl"]), description: optionalString(object["description"]), author: authors.isEmpty ? nil : authors.joined(separator: ", "),
            lang: strings(object["language"]), types: types.isEmpty ? ["movie", "series"] : types, idPrefixes: ["tt", "tmdb:"], hosts: [], settings: false,
            nsfw: tvTypes.contains { $0.lowercased() == "nsfw" }, enabled: status != 0, format: .androidExtension, note: notes.isEmpty ? nil : notes.joined(separator: " · "))
    }

    private static func string(_ value: JSONValue?) -> String { value?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    private static func optionalString(_ value: JSONValue?) -> String? { let result = string(value); return result.isEmpty ? nil : result }
    private static func strings(_ value: JSONValue?) -> [String] {
        if case .array(let rows) = value { return rows.compactMap(\.string).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        return optionalString(value).map { [$0] } ?? []
    }
    private static func number(_ value: JSONValue?) -> Double? {
        switch value {
        case .integer(let value): return Double(value)
        case .unsigned(let value): return Double(value)
        case .number(let value): return value.isFinite ? value : nil
        default: return nil
        }
    }
    private static func numberText(_ value: Double) -> String { value.rounded() == value && abs(value) < 1e21 ? String(format: "%.0f", value) : String(value) }
    private static func resolve(_ path: String, _ base: String) -> String? { URL(string: path, relativeTo: URL(string: base))?.absoluteURL.standardized.absoluteString }
    private static func unique(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { seen.insert($0).inserted } }
}
