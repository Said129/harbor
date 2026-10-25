import Foundation

enum CustomSourceDocumentFile {
    static func read(_ file: URL) throws -> String {
        let scoped = file.startAccessingSecurityScopedResource(); defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let data = try handle.read(upToCount: 96 * 1_024 + 1) ?? Data()
        guard data.count <= 96 * 1_024, let contents = String(data: data, encoding: .utf8) else { throw HarborError(code: "custom-source-import") }
        return contents
    }
}

/// Interpret Desktop's folder rows without rebuilding their JSON: edits must
/// retain future fields and the public addon/catalog identity used by Desktop.
struct DesktopSourceRow: Identifiable, Equatable, Sendable {
    let raw: JSONValue
    let folders: [DesktopSourceFolder]
    var id: String { raw["id"].string! }
    var title: String { raw["title"].string! }
    var rowID: String { "source-" + id }
    init?(_ raw: JSONValue) {
        guard case .object = raw, raw["id"].string != nil, raw["title"].string != nil,
              case .array(let rows) = raw["folders"], !rows.isEmpty else { return nil }
        let folders = rows.compactMap(DesktopSourceFolder.init)
        guard folders.count == rows.count else { return nil }
        self.raw = raw; self.folders = folders
    }
    static func parse(_ text: String) -> [Self] {
        guard let data = text.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        if case .array(let rows) = value { return rows.compactMap(Self.init) }
        return Self(value).map { [$0] } ?? []
    }
    static func merging(_ additions: [Self], into existing: [JSONValue]) -> [JSONValue] {
        var next = existing
        for row in additions {
            if let index = next.firstIndex(where: { $0["id"].string == row.id }) { next[index] = row.raw }
            else { next.append(row.raw) }
        }
        return next
    }
    func editingImages(folderID: String, cover: String, focus: String) -> Self {
        var fields = raw.objectValue
        fields["folders"] = .array(folders.map { folder in
            guard folder.id == folderID else { return folder.raw }
            var next = folder.raw.objectValue
            next["coverImageUrl"] = cover.isEmpty ? .null : .string(cover)
            next["focusGifUrl"] = focus.isEmpty ? .null : .string(focus)
            return .object(next)
        })
        return Self(.object(fields))!
    }
}

struct DesktopSourceFolder: Identifiable, Equatable, Sendable {
    enum Requirement: Equatable, Identifiable, Sendable {
        case tmdbKey
        case addon(String)
        var id: String { switch self { case .tmdbKey: "tmdb"; case .addon(let id): "addon:" + id } }
    }
    enum Destination: Equatable, Sendable {
        case discover(title: String, kind: String, parameters: [String: String])
        case collection(title: String, id: String)
        case traktList(title: String, id: String)
        case catalog(title: String, addon: String, type: String, id: String)
        var title: String {
            switch self {
            case .discover(let title, _, _), .collection(let title, _), .traktList(let title, _), .catalog(let title, _, _, _): title
            }
        }
    }
    let raw: JSONValue
    var id: String { raw["id"].string! }
    var title: String { raw["title"].string! }
    var poster: Bool { raw["tileShape"].string == "POSTER" }
    var hideTitle: Bool { raw["hideTitle"] == .bool(true) }
    var cover: String? { raw["coverImageUrl"].string }
    var focus: String? { raw["focusGifUrl"].string }
    init?(_ raw: JSONValue) {
        guard case .object = raw, raw["id"].string != nil, raw["title"].string != nil,
              ["LANDSCAPE", "POSTER"].contains(raw["tileShape"].string ?? "") else { return nil }
        let catalogs = raw["catalogSources"].array, native = raw["sources"].array
        guard !catalogs.isEmpty || !native.isEmpty,
              catalogs.allSatisfy({ source in
                  if case .object = source { return ["addonId", "type", "catalogId"].allSatisfy { source[$0].string != nil } }
                  return false
              }), native.allSatisfy({ source in
                  if case .object = source { return source["provider"].string != nil && source["mediaType"].string != nil }
                  return false
              }) else { return nil }
        self.raw = raw
    }
    var requiresTMDBKey: Bool {
        guard let source = raw["sources"].array.first else { return false }
        return source["provider"].string == "tmdb" || source["provider"].string == "trakt" && Self.identifier(source["traktListId"]) != nil
    }
    func missingRequirement(hasTMDBKey: Bool, addons: [Addon]) -> Requirement? {
        if requiresTMDBKey && !hasTMDBKey { return .tmdbKey }
        if let destination, case .catalog(_, let id, _, _) = destination {
            if addons.contains(where: { $0.enabled && $0.manifest["id"].string == id }) { return nil }
            // A declared disabled Cinemeta is intentional. The built-in catalog
            // is available only when the account has no Cinemeta declaration.
            if id == "com.linvo.cinemeta", !addons.contains(where: { $0.manifest["id"].string == id }) { return nil }
            return .addon(id)
        }
        return nil
    }
    var destination: Destination? {
        if let source = raw["sources"].array.first {
            let label = source["title"].string.flatMap { $0.isEmpty ? nil : $0 } ?? title
            if source["provider"].string == "tmdb" {
                if ["DISCOVER", "COMPANY"].contains(source["tmdbSourceType"].string ?? "") {
                    var parameters: [String: String] = [:]
                    if let sort = source["sortBy"].string, !sort.isEmpty { parameters["sort_by"] = sort }
                    for (key, value) in source["filters"].objectValue {
                        let name: String
                        switch key {
                        case "year": name = source["mediaType"].string == "TV" ? "first_air_date_year" : "primary_release_year"
                        case "voteCountGte": name = "vote_count.gte"
                        case "voteAverageGte": name = "vote_average.gte"
                        default: name = key.unicodeScalars.map { (65...90).contains($0.value) ? "_" + String($0).lowercased() : String($0) }.joined()
                        }
                        parameters[name] = Self.parameter(value)
                    }
                    if source["tmdbSourceType"].string == "COMPANY", let id = Self.identifier(source["tmdbId"]) { parameters["with_companies"] = id }
                    return .discover(title: label, kind: source["mediaType"].string!.lowercased(), parameters: parameters)
                }
                if source["tmdbSourceType"].string == "COLLECTION", let id = Self.identifier(source["tmdbId"]) { return .collection(title: label, id: id) }
            } else if source["provider"].string == "trakt", let id = Self.identifier(source["traktListId"]) { return .traktList(title: label, id: id) }
        }
        if let source = raw["catalogSources"].array.first {
            return .catalog(title: title, addon: source["addonId"].string!, type: source["type"].string!, id: source["catalogId"].string!)
        }
        return nil
    }
    private static func identifier(_ value: JSONValue) -> String? {
        switch value {
        case .string(let id): return id.isEmpty ? nil : id
        case .integer(let id): return id == 0 ? nil : String(id)
        case .unsigned(let id): return id == 0 ? nil : String(id)
        case .number(let id): return id == 0 || !id.isFinite ? nil : parameter(value)
        default: return nil
        }
    }
    private static func parameter(_ value: JSONValue) -> String {
        switch value {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .unsigned(let value): return String(value)
        case .number(let value): return String(decoding: (try? JSONEncoder().encode(value)) ?? Data(), as: UTF8.self)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        case .object: return "[object Object]"
        case .array(let values): return values.map { $0 == .null ? "" : parameter($0) }.joined(separator: ",")
        }
    }
}
