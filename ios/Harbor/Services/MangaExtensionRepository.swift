import Foundation

struct MangaExtensionRepository: Identifiable, Sendable {
    let name: String
    let indexURL: String

    var id: String { indexURL }
    var location: String {
        guard let url = URLComponents(string: indexURL) else { return indexURL }
        let parts = url.path.split(separator: "/")
        return parts.count >= 2 ? parts.prefix(2).joined(separator: "/") : url.host ?? indexURL
    }

    static func indexURL(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URLComponents(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil, url.url != nil else { return nil }

        let path = url.path.lowercased()
        if path.hasSuffix("/index.json") || path.hasSuffix("/index.min.json") { return trimmed }

        let parts = url.percentEncodedPath.split(separator: "/").map(String.init)
        if host.lowercased() == "github.com", url.port == nil, url.query == nil,
           parts.count == 2 || (parts.count == 4 && parts[2].lowercased() == "tree") {
            let name = parts[1].lowercased().hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
            guard !name.isEmpty else { return nil }
            let branch = parts.count == 4 ? parts[3] : "repo"
            return "https://raw.githubusercontent.com/\(parts[0])/\(name)/\(branch)/index.min.json"
        }
        let directory = url.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        url.percentEncodedPath = directory.isEmpty ? "/index.min.json" : "/\(directory)/index.min.json"
        return url.url?.absoluteString
    }
}
