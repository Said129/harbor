import Foundation

private final class MangaRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let next = request.url, MangaServer.sameOrigin(original, next), next.user == nil, next.password == nil else { completionHandler(nil); return }
        completionHandler(request)
    }
}

/// The same GraphQL/REST operations used by Desktop's Suwayomi provider.
/// Chapter identifiers retain their protocol: a GraphQL ID is not a REST index.
actor SuwayomiClient {
    let server: MangaServer
    private let session: URLSession
    private var graphql: Bool?
    private var progressTail: Task<Void, Error>?
    private var progressGeneration = UUID()
    private let images = NSCache<NSString, NSData>()
    init(server: MangaServer) {
        self.server = server
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration, delegate: MangaRedirectPolicy(), delegateQueue: nil)
        images.totalCostLimit = 32 * 1024 * 1024
    }
    deinit { session.invalidateAndCancel() }
    func sources() async throws -> [MangaSource] {
        let list: [JSONValue]
        do {
            let data = try await gql("query { sources { nodes { id name lang supportsLatest isNsfw } } }")
            guard case .array(let nodes) = data["sources"]["nodes"] else { throw HarborError(code: "manga-protocol") }
            graphql = true; list = nodes
        } catch {
            if Self.authorizationError(error) { throw error }
            let response = try await json("/api/v1/source/list")
            guard case .array(let nodes) = response else { throw HarborError(code: "manga-protocol") }
            graphql = false; list = nodes
        }
        var seen = Set<String>()
        return list.compactMap { value -> MangaSource? in
            guard let id = value["id"].mangaID else { return nil }
            return MangaSource(id: id, name: value["name"].string ?? value["displayName"].string ?? id, language: value["lang"].string ?? "", latest: value["supportsLatest"].mangaBool, adult: value["isNsfw"].mangaBool)
        }.filter { seen.insert($0.id).inserted }
    }
    func browse(source: String, latest: Bool, query: String, page: Int) async throws -> ([MangaBook], Bool) {
        guard Self.digits(source) else { throw HarborError(code: "manga-protocol") }
        if graphql == nil { _ = try await sources() }
        let response: JSONValue, values: [JSONValue]
        if graphql == true {
            let kind = !query.isEmpty ? "SEARCH" : latest ? "LATEST" : "POPULAR"
            response = try await gql("mutation($page: Int!, $query: String) { fetchSourceManga(input: { source: \"\(source)\", type: \(kind), page: $page, query: $query }) { hasNextPage mangas { id title author artist description } } }", variables: ["page": .integer(Int64(page)), "query": query.isEmpty ? .null : .string(query)])["fetchSourceManga"]
            guard case .array(let list) = response["mangas"] else { throw HarborError(code: "manga-protocol") }
            values = list
        } else {
            if query.isEmpty { response = try await json("/api/v1/source/\(source)/\(latest ? "latest" : "popular")/\(page)") }
            else {
                var path = URLComponents(); path.path = "/api/v1/source/\(source)/search"; path.queryItems = [URLQueryItem(name: "searchTerm", value: query), URLQueryItem(name: "pageNum", value: String(page))]
                response = try await json(path.string!)
            }
            if case .array(let list) = response { values = list }
            else if case .array(let list) = response["mangaList"] { values = list }
            else { throw HarborError(code: "manga-protocol") }
        }
        return (values.compactMap { book($0, source: source) }, response["hasNextPage"].mangaBool)
    }
    func library() async throws -> [MangaBook] {
        if graphql == nil { _ = try await sources() }
        let values: [JSONValue]
        if graphql == true {
            let response = try await gql("query { mangas(condition: { inLibrary: true }) { nodes { id title author artist description sourceId } } }")
            guard case .array(let nodes) = response["mangas"]["nodes"] else { throw HarborError(code: "manga-protocol") }
            values = nodes
        } else {
            let response = try await json("/api/v1/library")
            if case .array(let nodes) = response { values = nodes }
            else if case .array(let nodes) = response["mangaList"] { values = nodes }
            else { throw HarborError(code: "manga-protocol") }
        }
        return values.compactMap { book($0, source: $0["sourceId"].mangaID ?? "") }
    }
    func setLibrary(_ book: MangaBook, enabled: Bool) async throws {
        let id = try remoteID(book)
        if graphql == nil { _ = try await sources() }
        if graphql == true {
            guard let number = Int64(id) else { throw HarborError(code: "manga-protocol") }
            let data = try await gql("mutation($id: Int!, $inLibrary: Boolean!) { updateManga(input: { id: $id, patch: { inLibrary: $inLibrary } }) { manga { id } } }", variables: ["id": .integer(number), "inLibrary": .bool(enabled)])
            guard data["updateManga"]["manga"]["id"].mangaID != nil else { throw HarborError(code: "manga-protocol") }
        } else { _ = try await bytes("/api/v1/manga/\(id)/library", method: enabled ? "GET" : "DELETE", limit: 1024 * 1024) }
    }
    func detail(_ input: MangaBook) async throws -> MangaBook {
        let id = try remoteID(input)
        if graphql == nil { _ = try await sources() }
        let value: JSONValue
        if graphql == true {
            let data = try await gql("query { manga(id: \(id)) { id title author artist description sourceId initialized } }")
            if data["manga"]["initialized"] == .bool(false) {
                value = try await gql("mutation { fetchMangaAndChapters(input: { id: \(id), fetchManga: true, fetchChapters: false }) { manga { id title author artist description sourceId } } }")["fetchMangaAndChapters"]["manga"]
            } else { value = data["manga"] }
        } else { value = try await json("/api/v1/manga/\(id)/full") }
        guard let result = book(value, source: value["sourceId"].mangaID ?? input.sourceID ?? "") else { throw HarborError(code: "manga-protocol") }
        return result
    }
    func extensions() async throws -> [MangaExtension] {
        if graphql == nil { _ = try await sources() }
        let values: [JSONValue]
        if graphql == true { values = try await gql("query { extensions { nodes { pkgName name lang versionName isInstalled hasUpdate isObsolete isNsfw } } }")["extensions"]["nodes"].array }
        else { values = try await json("/api/v1/extension/list").array }
        return values.compactMap { value in
            guard let id = value["pkgName"].string else { return nil }
            return MangaExtension(id: id, name: value["name"].string ?? id, language: value["lang"].string ?? "", version: value["versionName"].string ?? "", installed: value[graphql == true ? "isInstalled" : "installed"].mangaBool, update: value["hasUpdate"].mangaBool, obsolete: value[graphql == true ? "isObsolete" : "obsolete"].mangaBool, adult: value["isNsfw"].mangaBool)
        }
    }
    func changeExtension(_ entry: MangaExtension, action: String) async throws {
        guard ["install", "uninstall", "update"].contains(action), !entry.id.isEmpty, entry.id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }) else { throw HarborError(code: "manga-protocol") }
        if graphql == nil { _ = try await sources() }
        if graphql == true {
            let data = try await gql("mutation($id: String!) { updateExtension(input: { id: $id, patch: { \(action): true } }) { extension { pkgName isInstalled } } }", variables: ["id": .string(entry.id)])
            guard data["updateExtension"]["extension"]["pkgName"].string != nil else { throw HarborError(code: "manga-protocol") }
        } else { _ = try await bytes("/api/v1/extension/\(action)/\(entry.id)", limit: 1024 * 1024) }
    }
    func chapters(_ book: MangaBook) async throws -> [MangaChapter] {
        let id = try remoteID(book)
        if graphql == nil { _ = try await sources() }
        let values: [JSONValue]
        if graphql == true {
            let cached = try await gql("query { chapters(condition: { mangaId: \(id) }) { nodes { id name chapterNumber scanlator pageCount isRead lastPageRead } } }")["chapters"]["nodes"]
            if !cached.array.isEmpty { values = cached.array }
            else {
                let response = try await gql("mutation { fetchChapters(input: { mangaId: \(id) }) { chapters { id name chapterNumber scanlator pageCount isRead lastPageRead } } }")
                guard case .array(let nodes) = response["fetchChapters"]["chapters"] else { throw HarborError(code: "manga-protocol") }
                values = nodes
            }
        } else {
            let response = try await json("/api/v1/manga/\(id)/chapters")
            guard case .array(let nodes) = response else { throw HarborError(code: "manga-protocol") }
            values = nodes
        }
        let useGraphQL = graphql == true
        return values.compactMap { value -> MangaChapter? in
            guard let key = value[useGraphQL ? "id" : "index"].mangaID else { return nil }
            let number = value["chapterNumber"].mangaNumber ?? 0
            let title = value["name"].string ?? "Capítulo \(number.formatted())"
            let scanlator = value["scanlator"].string ?? ""
            return MangaChapter(id: key, title: scanlator.isEmpty ? title : title + " · " + scanlator, number: number, pages: value["pageCount"].integer ?? 0, read: value[useGraphQL ? "isRead" : "read"].mangaBool, lastPage: value["lastPageRead"].integer ?? 0, graphql: useGraphQL)
        }.sorted { $0.number == $1.number ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.number < $1.number }
    }
    func pages(_ book: MangaBook, chapter: MangaChapter) async throws -> [MangaPage] {
        let manga = try remoteID(book)
        guard Self.digits(chapter.id) else { throw HarborError(code: "manga-protocol") }
        if chapter.graphql {
            let data = try await gql("mutation { fetchChapterPages(input: { chapterId: \(chapter.id) }) { pages } }")
            guard case .array(let pages) = data["fetchChapterPages"]["pages"], !pages.isEmpty, pages.count <= 5_000 else { throw HarborError(code: "manga-pages") }
            return try pages.enumerated().map { index, value in
                guard let path = value.string else { throw HarborError(code: "manga-pages") }
                _ = try imageURL(path)
                return MangaPage(id: index, path: path)
            }
        }
        let data = try await json("/api/v1/manga/\(manga)/chapter/\(chapter.id)")
        guard let count = data["pageCount"].integer, (1...5_000).contains(count) else { throw HarborError(code: "manga-pages") }
        return (0..<count).map { MangaPage(id: $0, path: "/api/v1/manga/\(manga)/chapter/\(chapter.id)/page/\($0)") }
    }
    func progress(_ book: MangaBook, chapter: MangaChapter, page: Int, completed: Bool) async throws {
        let previous = progressTail, token = UUID(); progressGeneration = token
        let task = Task {
            _ = try? await previous?.value
            try await sendProgress(book, chapter: chapter, page: page, completed: completed)
        }
        progressTail = task
        defer { if progressGeneration == token { progressTail = nil } }
        try await task.value
    }
    private func sendProgress(_ book: MangaBook, chapter: MangaChapter, page: Int, completed: Bool) async throws {
        let id = try remoteID(book)
        guard Self.digits(chapter.id) else { throw HarborError(code: "manga-protocol") }
        if chapter.graphql {
            guard let number = Int64(chapter.id) else { throw HarborError(code: "manga-protocol") }
            // Never send false: opening an earlier page must not unfinish a chapter.
            let patch = completed ? "isRead: true, lastPageRead: $last" : "lastPageRead: $last"
            let data = try await gql("mutation($id: Int!, $last: Int!) { updateChapter(input: { id: $id, patch: { \(patch) } }) { chapter { id } } }", variables: ["id": .integer(number), "last": .integer(Int64(max(0, page)))])
            guard data["updateChapter"]["chapter"]["id"].mangaID != nil else { throw HarborError(code: "manga-protocol") }
        } else {
            let body = "lastPageRead=\(max(0, page))" + (completed ? "&read=true" : "")
            _ = try await bytes("/api/v1/manga/\(id)/chapter/\(chapter.id)", method: "PATCH", body: Data(body.utf8), contentType: "application/x-www-form-urlencoded", limit: 1024 * 1024)
        }
    }
    func image(_ path: String) async throws -> Data {
        let url = try imageURL(path), key = url.absoluteString as NSString
        if let cached = images.object(forKey: key) { return cached as Data }
        var request = URLRequest(url: url, timeoutInterval: 40)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        if let base = URL(string: server.base), MangaServer.sameOrigin(base, url) { request.setValue(server.authorization, forHTTPHeaderField: "Authorization") }
        let data = try await receive(request, limit: 32 * 1024 * 1024)
        images.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }
    private func imageURL(_ path: String) throws -> URL {
        guard let url = URL(string: path.hasPrefix("http") ? path : server.base + (path.hasPrefix("/") ? path : "/" + path)), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else { throw HarborError(code: "manga-image-origin") }
        return url
    }
    private func remoteID(_ book: MangaBook) throws -> String {
        guard book.server == server.id, let id = book.remoteID, Self.digits(id) else { throw HarborError(code: "manga-connection") }
        return id
    }
    private func book(_ value: JSONValue, source: String) -> MangaBook? {
        guard let id = value["id"].mangaID, let title = value["title"].string else { return nil }
        return MangaBook(id: server.id + ":" + id, title: title, author: value["author"].string ?? value["artist"].string ?? "", description: value["description"].string ?? "", cover: "/api/v1/manga/\(id)/thumbnail", server: server.id, remoteID: id, sourceID: source)
    }
    private func gql(_ query: String, variables: [String: JSONValue] = [:]) async throws -> JSONValue {
        let data = try await bytes("/api/graphql", method: "POST", body: JSONEncoder().encode(JSONValue.object(["query": .string(query), "variables": .object(variables)])), limit: 8 * 1024 * 1024)
        let response = try JSONDecoder().decode(JSONValue.self, from: data)
        guard response["errors"].array.isEmpty, case .object = response["data"] else { throw HarborError(code: "manga-protocol") }
        return response["data"]
    }
    private func json(_ path: String) async throws -> JSONValue {
        let data = try await bytes(path, limit: 8 * 1024 * 1024)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    private func bytes(_ path: String, method: String = "GET", body: Data? = nil, contentType: String = "application/json", limit: Int) async throws -> Data {
        var request = URLRequest(url: try server.url(path), timeoutInterval: 45)
        request.httpMethod = method; request.httpBody = body
        request.setValue(server.authorization, forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await receive(request, limit: limit)
    }
    private func receive(_ request: URLRequest, limit: Int) async throws -> Data {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw HarborError(code: "manga-network") }
            if [401, 403].contains(response.statusCode) { throw HarborError(code: "manga-authorization") }
            guard (200..<300).contains(response.statusCode) else { throw HarborError(code: "manga-network") }
            guard response.expectedContentLength <= Int64(limit) else { throw HarborError(code: "manga-size") }
            var payload = Data()
            for try await byte in bytes { try Task.checkCancellation(); guard payload.count < limit else { throw HarborError(code: "manga-size") }; payload.append(byte) }
            return payload
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as HarborError { throw error }
        catch { throw HarborError(code: "manga-network") }
    }
    nonisolated private static func digits(_ value: String) -> Bool { !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) } }
    nonisolated private static func authorizationError(_ error: Error) -> Bool { (error as? HarborError)?.code == "manga-authorization" || error is CancellationError }
}

private extension JSONValue {
    var mangaID: String? {
        switch self {
        case .string(let value): !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) } ? value : nil
        case .integer(let value): value >= 0 ? String(value) : nil
        case .unsigned(let value): String(value)
        default: nil
        }
    }
    var mangaBool: Bool { if case .bool(let value) = self { return value }; return false }
    var mangaNumber: Double? {
        switch self {
        case .number(let value): value.isFinite ? value : nil
        case .integer(let value): Double(value)
        case .string(let value): Double(value).flatMap { $0.isFinite ? $0 : nil }
        default: nil
        }
    }
}
