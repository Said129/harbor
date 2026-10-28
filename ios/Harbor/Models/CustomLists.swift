import Foundation

struct CustomListItem: Identifiable, Sendable {
    let raw: JSONValue
    var id: String { raw["id"].string ?? "" }
    var name: String { raw["name"].string ?? "" }
    var type: String { raw["type"].string ?? "movie" }
    var poster: String? { raw["poster"].string }
    var media: Media { Media.parse(raw, kind: type) ?? .init(id: id, type: type, name: name) }
    static func origin(_ raw: JSONValue) -> JSONValue? {
        guard let id = raw["id"].string, !id.isEmpty else { return nil }
        var fields: [String: JSONValue] = ["id": .string(id), "name": .string(raw["name"].string.flatMap { $0.isEmpty ? nil : $0 } ?? id)]
        if let logo = raw["logo"].string { fields["logo"] = .string(logo) }
        if let base = raw["base"].string, !base.isEmpty { fields["base"] = .string(base) }
        return .object(fields)
    }
    static func videos(_ raw: JSONValue) -> JSONValue? {
        guard case .array(let videos) = raw, !videos.isEmpty, videos.count <= 40 else { return nil }
        let values = videos.compactMap { video -> JSONValue? in
            guard case .object(var fields) = video else { return nil }
            fields["streams"] = nil; return .object(fields)
        }
        guard !values.isEmpty else { return nil }
        let result = JSONValue.array(values), encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(result), let text = String(data: data, encoding: .utf8), text.utf16.count <= 64_000 else { return nil }
        return result
    }
    static func parse(_ raw: JSONValue) -> Self? {
        guard let id = raw["id"].string else { return nil }
        let type = raw["type"].string.flatMap { ["series", "manga"].contains($0) ? $0 : nil } ?? "movie"
        var fields: [String: JSONValue] = ["id": .string(id), "name": .string(raw["name"].string ?? ""),
            "type": .string(type),
            "addedAt": raw["addedAt"].numericValue != nil ? raw["addedAt"] : .integer(0)]
        for key in ["altTitle", "poster"] { if let value = raw[key].string { fields[key] = .string(value) } }
        fields["addonOrigin"] = origin(raw["addonOrigin"]); fields["videos"] = videos(raw["videos"])
        return .init(raw: .object(fields))
    }
    static func input(_ raw: JSONValue, at: Int64) -> Self? {
        guard let id = raw["id"].string else { return nil }
        let type: String
        switch raw["type"].string {
        case "series", "tv", "anime": type = "series"
        case "movie": type = "movie"
        case "manga": type = "manga"
        default:
            type = ["kitsu:", "mal:", "anilist:", "anidb:"].contains(where: id.lowercased().hasPrefix) || id.contains(":tv:") || id.contains(":series:") ? "series" : "movie"
        }
        var fields = raw.objectValue; fields["type"] = .string(type); fields["addedAt"] = .integer(at)
        return parse(.object(fields))
    }
    static func input(_ media: Media) -> JSONValue {
        var fields: [String: JSONValue] = ["id": .string(media.id), "type": .string(media.type), "name": .string(media.name)]
        fields["poster"] = media.poster.map(JSONValue.string)
        if let videos = media.videos, let data = try? JSONEncoder().encode(videos), let value = try? JSONDecoder().decode(JSONValue.self, from: data) { fields["videos"] = Self.videos(value) }
        return .object(fields)
    }
}

struct CustomList: Identifiable, Sendable {
    let raw: JSONValue
    let items: [CustomListItem]
    init(raw: JSONValue, items: [CustomListItem]? = nil) {
        self.raw = raw; self.items = items ?? raw["items"].array.compactMap(CustomListItem.parse)
    }
    var id: String { raw["id"].string ?? "" }
    var name: String { raw["name"].string ?? "" }
    var description: String { raw["description"].string ?? "" }
    var cover: String? { raw["coverImage"].string ?? items.compactMap(\.poster).first }
    static func parse(_ raw: JSONValue) -> Self? {
        guard let id = raw["id"].string, let name = raw["name"].string else { return nil }
        let items = raw["items"].array.compactMap(CustomListItem.parse)
        var fields: [String: JSONValue] = ["id": .string(id), "name": .string(name),
            "createdAt": raw["createdAt"].numericValue != nil ? raw["createdAt"] : .integer(0),
            "updatedAt": raw["updatedAt"].numericValue != nil ? raw["updatedAt"] : .integer(0),
            "items": .array(items.map(\.raw))]
        for key in ["description", "coverImage", "bgImage"] { if let value = raw[key].string { fields[key] = .string(value) } }
        if raw["order"].numericValue != nil { fields["order"] = raw["order"] }
        if let mode = raw["bgMode"].string, ["auto", "custom"].contains(mode) { fields["bgMode"] = .string(mode) }
        return .init(raw: .object(fields), items: items)
    }
}

struct CustomListsDocument: Sendable {
    static let maximumLists = 24, maximumItems = 100
    enum Action: Sendable {
        case create(String, String, id: String), rename(String, String), describe(String, String), delete(String)
        case add(String, JSONValue), remove(String, String), updateItem(String, String, JSONValue), toggle(String, JSONValue)
        case reorderLists([String]), reorderItems(String, [String])
    }
    struct Result: Sendable { var changed = false; var createdID: String?; var contains: Bool? }
    private(set) var values: [CustomList]
    init(_ raw: JSONValue = .array([])) { values = raw.array.compactMap(CustomList.parse) }
    var raw: JSONValue { .array(values.map(\.raw)) }
    var sorted: [CustomList] {
        values.enumerated().sorted {
            let first = $0.element.raw["order"].numericValue ?? 9_007_199_254_740_991
            let second = $1.element.raw["order"].numericValue ?? 9_007_199_254_740_991
            if first != second { return first < second }
            let lhs = $0.element.raw["updatedAt"].numericValue ?? 0, rhs = $1.element.raw["updatedAt"].numericValue ?? 0
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.map(\.element)
    }
    private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\u{FEFF}"))) }
    private mutating func edit(_ id: String, _ body: (inout [String: JSONValue]) -> Bool) -> Bool {
        guard let index = values.firstIndex(where: { $0.id == id }) else { return false }
        var fields = values[index].raw.objectValue; guard body(&fields) else { return false }
        values[index] = .init(raw: .object(fields)); return true
    }
    @discardableResult mutating func apply(_ action: Action, at: Int64) -> Result {
        var result = Result()
        switch action {
        case .create(let name, let description, let id):
            let name = trimmed(name), description = trimmed(description)
            guard !name.isEmpty, values.count < Self.maximumLists else { return result }
            var fields: [String: JSONValue] = ["id": .string(id), "name": .string(name), "createdAt": .integer(at), "updatedAt": .integer(at), "items": .array([])]
            if !description.isEmpty { fields["description"] = .string(description) }
            values.append(.init(raw: .object(fields))); result.createdID = id; result.changed = true
        case .rename(let id, let name):
            let name = trimmed(name); guard !name.isEmpty else { return result }
            result.changed = edit(id) { $0["name"] = .string(name); $0["updatedAt"] = .integer(at); return true }
        case .describe(let id, let description):
            let description = trimmed(description)
            result.changed = edit(id) { $0["description"] = description.isEmpty ? nil : .string(description); $0["updatedAt"] = .integer(at); return true }
        case .delete(let id):
            let count = values.count; values.removeAll { $0.id == id }; result.changed = count != values.count
        case .reorderLists(let ids):
            let positions = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { _, last in last })
            for index in values.indices {
                if let position = positions[values[index].id] {
                    var fields = values[index].raw.objectValue; fields["order"] = .integer(Int64(position))
                    values[index] = .init(raw: .object(fields), items: values[index].items)
                }
            }
            result.changed = true
        case .reorderItems(let list, let ids):
            result.changed = edit(list) { fields in
                let items = fields["items"]?.array ?? [], indexed = Dictionary(items.compactMap { item in item["id"].string.map { ($0, item) } }, uniquingKeysWith: { _, last in last })
                var remaining = indexed, next: [JSONValue] = []
                for id in ids { if let value = remaining.removeValue(forKey: id) { next.append(value) } }
                next += items.filter { $0["id"].string.map { remaining[$0] != nil } ?? false }
                fields["items"] = .array(next); return true
            }
        case .add(let list, let input), .toggle(let list, let input):
            let toggling: Bool; if case .toggle = action { toggling = true } else { toggling = false }
            guard let item = CustomListItem.input(input, at: at) else { return result }
            var contains = false
            result.changed = edit(list) { fields in
                var items = fields["items"]?.array ?? []
                if items.contains(where: { $0["id"].string == item.id }) {
                    guard toggling else { contains = true; return false }; items.removeAll { $0["id"].string == item.id }
                } else { guard items.count < Self.maximumItems else { return false }; items.append(item.raw); contains = true }
                fields["items"] = .array(items); fields["updatedAt"] = .integer(at); return true
            }
            result.contains = contains
        case .remove(let list, let id):
            result.changed = edit(list) { fields in
                let items = fields["items"]?.array ?? [], next = items.filter { $0["id"].string != id }
                guard next.count != items.count else { return false }; fields["items"] = .array(next); fields["updatedAt"] = .integer(at); return true
            }
        case .updateItem(let list, let id, let patch):
            result.changed = edit(list) { fields in
                var items = fields["items"]?.array ?? []; guard let index = items.firstIndex(where: { $0["id"].string == id }) else { return false }
                var updated = items[index].objectValue
                for key in ["id", "name", "altTitle", "poster"] { if patch[key] != .null { updated[key] = patch[key] } }
                let newID = updated["id"]?.string ?? id
                items = items.enumerated().filter { $0.offset == index || $0.element["id"].string != newID }.map(\.element)
                guard let position = items.firstIndex(where: { $0["id"].string == id }) else { return false }
                items[position] = .object(updated); fields["items"] = .array(items); fields["updatedAt"] = .integer(at); return true
            }
        }
        return result
    }
}
