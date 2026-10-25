import Foundation

struct LayoutEditSnapshot<Value: Codable & Sendable>: Sendable {
    let value: Value
    /// nil is a legacy record; empty means a server projection; otherwise a
    /// profile sync ID owns the local edit. This never enters a wire document.
    let editor: String?
    /// The complete value that produced the shared native settings. Per-profile
    /// revision shadows cannot identify the latest linked profile's projection.
    var projection: JSONValue? = nil
}

@MainActor enum LayoutEditStorage {
    private static let editorKey = "_nativeLocalLayoutEditor"
    private static let projectionKey = "_nativeLayoutProjection"
    private static func projection(_ raw: JSONValue) throws -> JSONValue? {
        if raw == .null { return nil }
        guard case .object = raw, try JSONEncoder().encode(raw).count <= 96 * 1_024 else { throw HarborError(code: "layout-preference-store") }
        return raw
    }
    private static func editor(_ raw: JSONValue) throws -> String? {
        if raw == .null { return nil }
        guard let value = raw.string, value.utf8.count <= 256 else { throw HarborError(code: "layout-preference-store") }
        return value
    }
    static func object<Value: Codable & Sendable>(_ key: String, as type: Value.Type) throws -> LayoutEditSnapshot<Value>? {
        guard let raw = try KeychainStore().read(key, as: JSONValue.self) else { return nil }
        let value = try JSONDecoder().decode(type, from: JSONEncoder().encode(raw))
        return LayoutEditSnapshot(value: value, editor: try editor(raw[editorKey]), projection: try projection(raw[projectionKey]))
    }
    static func writeObject<Value: Codable & Sendable>(_ snapshot: LayoutEditSnapshot<Value>, key: String) throws {
        _ = try editor(snapshot.editor.map(JSONValue.string) ?? .null)
        _ = try projection(snapshot.projection ?? .null)
        var fields = try JSONValue.encoded(snapshot.value).objectValue
        if let editor = snapshot.editor { fields[editorKey] = .string(editor) }
        if let projection = snapshot.projection { fields[projectionKey] = projection }
        try KeychainStore().write(JSONValue.object(fields), key: key)
    }
    static func dictionary(_ key: String) throws -> LayoutEditSnapshot<[String: Bool]>? {
        guard let raw = try KeychainStore().read(key, as: JSONValue.self) else { return nil }
        let wrapped = raw["_nativeLayoutDictionary"] == .bool(true)
        let value = try JSONDecoder().decode([String: Bool].self, from: JSONEncoder().encode(wrapped ? raw["values"] : raw))
        let origin = try editor(wrapped ? raw[editorKey] : .null)
        return LayoutEditSnapshot(value: value, editor: origin, projection: try projection(wrapped ? raw[projectionKey] : .null))
    }
    static func writeDictionary(_ snapshot: LayoutEditSnapshot<[String: Bool]>, key: String) throws {
        _ = try editor(snapshot.editor.map(JSONValue.string) ?? .null)
        _ = try projection(snapshot.projection ?? .null)
        try KeychainStore().write(JSONValue.object(["_nativeLayoutDictionary": .bool(true), "values": try .encoded(snapshot.value),
            editorKey: snapshot.editor.map(JSONValue.string) ?? .null, projectionKey: snapshot.projection ?? .null]), key: key)
    }
}
