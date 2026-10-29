import Foundation
import Libmpv

/// mpv receives a native string array. Joining HTTP headers with commas changes
/// values such as cookies, quoted tokens and URLs containing backslashes.
enum MusicStreamHeaders {
    static func fields(_ headers: [String: String]) throws -> (agent: String?, fields: [String]) {
        guard headers.count <= 16 else { throw HarborError(code: "music-stream-headers") }
        let token = Set("!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
        var fields: [String] = [], agent: String?
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            guard !name.isEmpty, name.utf8.count <= 128, value.utf8.count <= 8192,
                  name.utf8.allSatisfy({ token.contains($0) }),
                  value.utf8.allSatisfy({ $0 == 9 || $0 >= 32 && $0 != 127 }) else { throw HarborError(code: "music-stream-headers") }
            if name.lowercased() == "user-agent" { agent = value }
            else { fields.append(name + ": " + value) }
        }
        return (agent, fields)
    }
    static func apply(_ headers: [String: String], to handle: OpaquePointer, defaultAgent: String) throws {
        let validated = try fields(headers)
        guard mpv_set_property_string(handle, "user-agent", validated.agent ?? defaultAgent) >= 0 else { throw HarborError(code: "music-stream-headers") }
        let strings = validated.fields.map { strdup($0) }
        defer { strings.forEach { free($0) } }
        guard strings.allSatisfy({ $0 != nil }) else { throw HarborError(code: "music-stream-headers") }
        var nodes = strings.map { pointer -> mpv_node in var value = mpv_node(); value.format = MPV_FORMAT_STRING; value.u.string = pointer; return value }
        let status = nodes.withUnsafeMutableBufferPointer { buffer -> Int32 in
            var list = mpv_node_list(); list.num = Int32(buffer.count); list.values = buffer.baseAddress; list.keys = nil
            return withUnsafeMutablePointer(to: &list) { pointer in
                var root = mpv_node(); root.format = MPV_FORMAT_NODE_ARRAY; root.u.list = pointer
                return mpv_set_property(handle, "http-header-fields", MPV_FORMAT_NODE, &root)
            }
        }
        guard status >= 0 else { throw HarborError(code: "music-stream-headers") }
    }
}
