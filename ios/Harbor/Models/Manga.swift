import Foundation
import Observation

struct MangaBook: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var author = ""
    var description = ""
    var cover: String?
    var server: String?
    var remoteID: String?
    var sourceID: String?
    var folderChapters: Bool?
}
struct MangaSource: Identifiable, Sendable {
    let id: String
    let name: String
    let language: String
    let latest: Bool
    let adult: Bool
}
struct MangaExtension: Identifiable, Sendable {
    let id: String
    let name: String
    let language: String
    let version: String
    let installed: Bool
    let update: Bool
    let obsolete: Bool
    let adult: Bool
}
struct MangaChapter: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var number: Double = 0
    var pages = 0
    var read = false
    var lastPage = 0
    var graphql = false
}
struct MangaPage: Identifiable, Sendable {
    let id: Int
    let path: String
}
struct MangaProgress: Codable, Sendable {
    var page = 0
    var completed = false
    var updated = Date()
}
struct MangaRecord: Codable, Identifiable, Sendable {
    var book: MangaBook
    var chapter = "local"
    var progress: [String: MangaProgress] = [:]
    var updated = Date()
    var id: String { book.id }
}

@MainActor @Observable
final class MangaShelf {
    let owner: String
    private(set) var records: [MangaRecord] = []
    private(set) var ready = false
    var error: String?
    private var key: String { "manga-shelf-" + EBookShelf.hash(owner) }
    init(owner: String) {
        self.owner = owner
        do { records = try KeychainStore().read(key, as: [MangaRecord].self) ?? []; ready = true }
        catch { self.error = "No se pudo leer tu biblioteca de Manga. Los archivos y el progreso se conservan." }
    }
    func record(_ book: MangaBook) -> MangaRecord? { records.first { $0.id == book.id } }
    func save(_ record: MangaRecord) throws {
        guard ready else { throw HarborError(code: "manga-store") }
        var next = records.filter { $0.id != record.id }; next.append(record)
        guard next.count <= 500, try JSONEncoder().encode(next).count <= 4 * 1024 * 1024 else { throw HarborError(code: "manga-store") }
        try KeychainStore().write(next, key: key); records = next
    }
    func remove(_ book: MangaBook) throws {
        guard ready else { throw HarborError(code: "manga-store") }
        let next = records.filter { $0.id != book.id }
        try KeychainStore().write(next, key: key); records = next
    }
}

struct MangaServer: Codable, Equatable, Sendable {
    var base: String
    var username = ""
    var password = ""
    var id: String { EBookShelf.hash(base + "|" + username) }
    var authorization: String? { username.isEmpty ? nil : "Basic " + Data((username + ":" + password).utf8).base64EncodedString() }
    static func normalized(_ raw: String, username: String, password: String) throws -> Self {
        guard var url = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw HarborError(code: "manga-server-url") }
        var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var changed = true
        while changed {
            changed = false
            for suffix in ["api/v1", "api/graphql", "graphql", "api"] where path.lowercased() == suffix || path.lowercased().hasSuffix("/" + suffix) {
                path = String(path.dropLast(suffix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")); changed = true; break
            }
        }
        url.path = path.isEmpty ? "" : "/" + path
        guard let base = url.url?.absoluteString, !username.contains(":"), !username.contains("\n"), !password.contains("\n") else { throw HarborError(code: "manga-server-url") }
        return Self(base: base, username: username, password: password)
    }
    func url(_ path: String) throws -> URL {
        guard let baseURL = URL(string: base), let result = URL(string: path.hasPrefix("http") ? path : base + (path.hasPrefix("/") ? path : "/" + path)), ["http", "https"].contains(result.scheme?.lowercased() ?? ""), result.user == nil, result.password == nil else { throw HarborError(code: "manga-server-url") }
        guard Self.sameOrigin(baseURL, result) else { throw HarborError(code: "manga-image-origin") }
        return result
    }
    nonisolated static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased() && (a.port ?? (a.scheme == "https" ? 443 : 80)) == (b.port ?? (b.scheme == "https" ? 443 : 80))
    }
}

@MainActor @Observable
final class MangaConnection {
    let owner: String
    private(set) var server: MangaServer?
    private(set) var ready = false
    var error: String?
    private var key: String { "manga-server-" + EBookShelf.hash(owner) }
    init(owner: String) {
        self.owner = owner
        do { server = try KeychainStore().read(key, as: MangaServer.self); ready = true }
        catch { self.error = "No se pudo recuperar la conexión de Manga. La configuración se conserva." }
    }
    func save(_ value: MangaServer?) throws {
        guard ready else { throw HarborError(code: "manga-store") }
        if let value { try KeychainStore().write(value, key: key) }
        else { try KeychainStore().remove(key) }
        server = value
    }
}
