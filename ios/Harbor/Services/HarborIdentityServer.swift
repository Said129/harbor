import Foundation

struct HarborIdentityServer: Codable, Equatable, Sendable {
    static let community = try! HarborIdentityServer("https://harborcommunity.site")
    static let original = try! HarborIdentityServer("https://harbor.site")
    let base: String
    var retired: Bool { base == Self.original.base }
    var host: String { URLComponents(string: base)!.host! }

    init(_ value: String) throws {
        guard value.utf8.count <= 512,
              var parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", parts.port == nil || (1...65535).contains(parts.port!) else {
            throw HarborError(code: "harbor-server-url")
        }
        parts.scheme = "https"; parts.host = host.lowercased(); parts.path = ""
        if parts.port == 443 { parts.port = nil }
        guard let normalized = parts.url?.absoluteString else { throw HarborError(code: "harbor-server-url") }
        base = normalized
    }

    init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(base) }

    func account(_ id: String) -> String {
        // The original realm keeps its existing journals. The same provider ID
        // on a replacement server must never inherit those private namespaces.
        self == .original ? id : "realm-v1-" + HouseholdProfileScope.hash([base, id])
    }
}
