import Foundation

struct XtreamAccount: Codable, Hashable, Sendable {
    let base: String
    let username: String
    let password: String
    static func make(server: String, username: String, password: String) throws -> Self {
        let clean = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = LivePlaylistService.validURL(clean), let host = url.host, var origin = URLComponents(string: clean), origin.query == nil, origin.fragment == nil, !host.isEmpty else { throw HarborError(code: "xtream-url") }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines), pass = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !pass.isEmpty, user.utf8.count <= 1_024, pass.utf8.count <= 1_024, !(user + pass).unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw HarborError(code: "xtream-credentials") }
        origin.scheme = origin.scheme?.lowercased(); origin.path = ""; origin.query = nil; origin.fragment = nil
        guard let base = origin.url?.absoluteString else { throw HarborError(code: "xtream-url") }
        return Self(base: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")), username: user, password: pass)
    }
    static func fromPlaylist(_ raw: String) -> Self? {
        guard let url = URLComponents(string: raw), ["get.php", "player_api.php"].contains(url.path.split(separator: "/").last.map(String.init) ?? ""), let user = url.queryItems?.first(where: { $0.name == "username" })?.value, let pass = url.queryItems?.first(where: { $0.name == "password" })?.value else { return nil }
        var origin = url; origin.path = ""; origin.query = nil; origin.fragment = nil
        guard let server = origin.url?.absoluteString else { return nil }
        return try? make(server: server, username: user, password: pass)
    }
    func api(_ action: String?, extra: [String: String] = [:]) throws -> URL {
        guard var url = URLComponents(string: base) else { throw HarborError(code: "xtream-url") }
        url.path = "/player_api.php"
        var items = [URLQueryItem(name: "username", value: username), URLQueryItem(name: "password", value: password)]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        items.append(contentsOf: extra.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
        url.queryItems = items
        guard let result = url.url else { throw HarborError(code: "xtream-url") }; return result
    }
    func stream(kind: String, id: String, ext: String?, base override: String? = nil) throws -> String {
        guard ["live", "movie", "series"].contains(kind), !id.isEmpty, id.utf8.count < 24, id.allSatisfy({ $0.isASCII && $0.isNumber }), let root = URL(string: override ?? base) else { throw HarborError(code: "xtream-response") }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let user = username.addingPercentEncoding(withAllowedCharacters: allowed), let pass = password.addingPercentEncoding(withAllowedCharacters: allowed), var url = URLComponents(url: root, resolvingAgainstBaseURL: false) else { throw HarborError(code: "xtream-url") }
        let suffix = ext.flatMap { value in value.count <= 10 && value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) ? "." + value : nil } ?? ""
        url.percentEncodedPath = "/\(kind)/\(user)/\(pass)/\(id)\(suffix)"; url.query = nil; url.fragment = nil
        guard let result = url.url?.absoluteString else { throw HarborError(code: "xtream-url") }; return result
    }
}
struct XtreamCapabilities: Sendable { let formats: [String]; let streamBase: String }
struct LiveProgram: Identifiable, Sendable {
    let id: String
    let title: String
    let description: String?
    let start: Date
    let end: Date
}
