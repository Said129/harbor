import Foundation

struct NativeNavigationLayout: Codable, Equatable, Sendable {
    var order: [String] = []
    var hidden: Set<String> = []
    var renamed: [String: String] = [:]
    var valid: Bool {
        order.count <= 1_000 && hidden.count <= 1_000 && renamed.count <= 1_000
            && (order + Array(hidden) + Array(renamed.keys)).allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 }
            && renamed.values.allSatisfy { $0.utf8.count <= 4_096 }
    }
}

/// Desktop's navCustomization section. Unsupported navigation IDs and future
/// fields stay in the shadow value; editing iOS must not reset Desktop Games.
struct DesktopNavigationLayout: Equatable, Sendable {
    let raw: JSONValue
    let order: [String]
    let hidden: [String]
    let renamed: [String: String]
    static let referenceOrder = ["home", "discover", "catalogs", "plugins", "movies", "shows", "music", "games", "kids", "anime", "manga", "ebook", "live", "sports", "vod", "calendar", "library", "collections", "downloads", "addons", "settings"]

    init(_ raw: JSONValue) throws {
        guard case .object(let fields) = raw, try JSONEncoder().encode(raw).count <= 96 * 1_024 else { throw HarborError(code: "navigation-sync-value") }
        func identifiers(_ key: String) throws -> [String] {
            guard let value = fields[key] else { return [] }
            guard case .array(let items) = value, items.count <= 1_000 else { throw HarborError(code: "navigation-sync-value") }
            return try items.map {
                guard let id = $0.string, !id.isEmpty, id.utf8.count <= 256 else { throw HarborError(code: "navigation-sync-value") }
                return id
            }
        }
        order = try identifiers("order"); hidden = try identifiers("hidden")
        var names: [String: String] = [:]
        if let value = fields["renamed"] {
            guard case .object(let rows) = value, rows.count <= 1_000 else { throw HarborError(code: "navigation-sync-value") }
            for (id, value) in rows {
                guard !id.isEmpty, id.utf8.count <= 256, let name = value.string, name.utf8.count <= 4_096 else { throw HarborError(code: "navigation-sync-value") }
                names[id] = name
            }
        }
        renamed = names; self.raw = raw
    }

    func native(knownIDs: Set<String>, preserving local: NativeNavigationLayout, defaultOrder: [String]) -> NativeNavigationLayout {
        let incoming = Self.unique(order.filter { knownIDs.contains($0) } + defaultOrder.filter { knownIDs.contains($0) })
        let existing = Self.unique(local.order + defaultOrder)
        let order = Self.replacingKnownSlots(existing, with: incoming, knownIDs: knownIDs)
        let hidden = local.hidden.subtracting(knownIDs).union(self.hidden.filter { knownIDs.contains($0) })
        let names = local.renamed.filter { !knownIDs.contains($0.key) }.merging(renamed.filter { knownIDs.contains($0.key) }) { _, next in next }
        return NativeNavigationLayout(order: order, hidden: hidden, renamed: names)
    }

    func applying(_ local: NativeNavigationLayout, knownIDs: Set<String>, defaultOrder: [String]) throws -> DesktopNavigationLayout {
        guard local.valid else { throw HarborError(code: "navigation-sync-value") }
        let selected = Self.unique((local.order + defaultOrder).filter { knownIDs.contains($0) })
        var fields = raw.objectValue
        fields["order"] = .array(Self.replacingKnownSlots(order, with: selected, knownIDs: knownIDs).map(JSONValue.string))
        let hidden = Self.unique(self.hidden.filter { !knownIDs.contains($0) } + local.hidden.filter { knownIDs.contains($0) }.sorted())
        fields["hidden"] = .array(hidden.map(JSONValue.string))
        let names = renamed.filter { !knownIDs.contains($0.key) }.merging(local.renamed.filter { knownIDs.contains($0.key) }) { _, next in next }
        fields["renamed"] = .object(names.mapValues(JSONValue.string))
        return try DesktopNavigationLayout(.object(fields))
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>(); return ids.filter { seen.insert($0).inserted }
    }
    private static func replacingKnownSlots(_ original: [String], with ordered: [String], knownIDs: Set<String>) -> [String] {
        var next = ordered.makeIterator(), result: [String] = []
        for id in original {
            if knownIDs.contains(id) { if let replacement = next.next() { result.append(replacement) } }
            else { result.append(id) }
        }
        while let replacement = next.next() { result.append(replacement) }
        return result
    }
}

struct HarborLayoutDocument: Codable, Equatable, Sendable {
    let key: String
    let rev: Int64
    let value: JSONValue
    static let maximumRevision: Int64 = 9_007_199_254_740_991

    static func revision(_ value: JSONValue) throws -> Int64 {
        switch value {
        case .integer(let number) where number >= 0 && number <= maximumRevision: return number
        case .unsigned(let number) where number <= UInt64(maximumRevision): return Int64(number)
        case .number(let number) where number.isFinite && number >= 0 && number <= Double(maximumRevision) && number.rounded() == number: return Int64(number)
        default: throw HarborError(code: "layout-sync-response")
        }
    }
    static func document(_ raw: JSONValue, expectedKey: String) throws -> HarborLayoutDocument {
        guard raw["key"].string == expectedKey, case .object(let fields) = raw, let value = fields["value"] else { throw HarborError(code: "layout-sync-response") }
        return HarborLayoutDocument(key: expectedKey, rev: try revision(raw["rev"]), value: value)
    }
    static func state(_ raw: JSONValue, key: String) throws -> HarborLayoutDocument? {
        _ = try revision(raw["rev"])
        guard case .array(let docs) = raw["docs"], docs.count <= 10_000 else { throw HarborError(code: "layout-sync-response") }
        let matches = docs.filter { $0["key"].string == key }
        guard matches.count <= 1 else { throw HarborError(code: "layout-sync-response") }
        return try matches.first.map { try document($0, expectedKey: key) }
    }
    func write(_ next: JSONValue) throws -> JSONValue {
        guard !key.isEmpty, key.utf8.count <= 512, rev >= 0, rev <= Self.maximumRevision, try JSONEncoder().encode(next).count <= 96 * 1_024 else { throw HarborError(code: "layout-sync-size") }
        return .object(["writes": .array([.object(["key": .string(key), "baseRev": .integer(rev), "value": next])])])
    }
    enum Result: Sendable { case accepted(Int64), rejected(HarborLayoutDocument) }
    func result(_ raw: JSONValue) throws -> Result {
        guard case .array(let rows) = raw["results"], rows.count == 1, let result = rows.first,
              result["key"] == .null || result["key"].string == key else { throw HarborError(code: "layout-sync-response") }
        if result["ok"] == .bool(true) {
            let next = try Self.revision(result["rev"])
            guard next > rev else { throw HarborError(code: "layout-sync-response") }
            return .accepted(next)
        }
        guard result["ok"] == .bool(false) else { throw HarborError(code: "layout-sync-response") }
        let current = try Self.document(result["current"], expectedKey: key)
        guard current.rev >= rev else { throw HarborError(code: "layout-sync-response") }
        return .rejected(current)
    }
}
