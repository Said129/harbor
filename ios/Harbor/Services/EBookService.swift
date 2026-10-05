import Foundation

actor EBookService {
    static let shared = EBookService()
    private var readers: [String: EPUBReader] = [:]
    private var recent: [String] = []
    func catalog(query: String, language: String, page: Int) async throws -> ([EBook], Bool) {
        var components = URLComponents(string: "https://gutendex.com/books/")!
        components.queryItems = [URLQueryItem(name: "page", value: String(max(1, page))), URLQueryItem(name: "mime_type", value: "application/epub+zip")]
        if !query.isEmpty { components.queryItems?.append(URLQueryItem(name: "search", value: query)) }
        if !language.isEmpty { components.queryItems?.append(URLQueryItem(name: "languages", value: language)) }
        let response = try await HTTPClient().json(components.url!.absoluteString, timeout: 30)
        let books = response["results"].array.compactMap { value -> EBook? in
            guard let id = value["id"].integer, let title = value["title"].string else { return nil }
            let formats = value["formats"].objectValue
            guard let epub = formats.first(where: { $0.key.hasPrefix("application/epub+zip") && $0.value.string?.hasSuffix(".zip") != true })?.value.string else { return nil }
            let authors = value["authors"].array.compactMap { $0["name"].string }.map { name -> String in let parts = name.components(separatedBy: ", "); return parts.count == 2 ? parts.reversed().joined(separator: " ") : name }
            return EBook(id: "gutendex:\(id)", title: title, authors: authors, description: value["summaries"].array.compactMap(\.string).joined(separator: "\n\n"), cover: formats.first(where: { $0.key.hasPrefix("image/jpeg") })?.value.string, language: value["languages"].array.first?.string, epub: epub)
        }
        return (books, response["next"].string != nil)
    }
    func open(_ book: EBook, owner: String, imported: Data? = nil) async throws -> EBookPublication {
        let key = Self.key(book, owner)
        if let cached = readers[key] { return cached.publication }
        let file = try Self.file(book, owner)
        let data: Data
        if let imported { data = imported }
        else if FileManager.default.fileExists(atPath: file.path) {
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 48 * 1024 * 1024 else { throw HarborError(code: "ebook-size") }
            data = try Data(contentsOf: file)
        } else {
            guard let raw = book.epub, let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw HarborError(code: "ebook-missing") }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(for: URLRequest(url: url, timeoutInterval: 60))
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw HarborError(code: "ebook-network") }
            let limit = 48 * 1024 * 1024
            guard response.expectedContentLength <= Int64(limit) else { throw HarborError(code: "ebook-size") }
            var payload = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard payload.count < limit else { throw HarborError(code: "ebook-size") }
                payload.append(byte)
            }
            data = payload
        }
        try Task.checkCancellation()
        let reader = try EPUBReader(data: data)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        recent.removeAll { $0 == key }; recent.append(key); readers[key] = reader
        while recent.count > 2 { readers.removeValue(forKey: recent.removeFirst()) }
        return reader.publication
    }
    func blocks(_ book: EBook, owner: String, chapter: Int) async throws -> [EBookBlock] {
        _ = try await open(book, owner: owner)
        guard let reader = readers[Self.key(book, owner)], reader.publication.chapters.indices.contains(chapter) else { throw HarborError(code: "ebook-format") }
        return try reader.blocks(reader.publication.chapters[chapter])
    }
    func remove(_ book: EBook, owner: String) throws {
        let key = Self.key(book, owner), file = try Self.file(book, owner)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        readers[key] = nil; recent.removeAll { $0 == key }
    }
    nonisolated private static func key(_ book: EBook, _ owner: String) -> String { EBookShelf.hash(owner + "|" + book.id) }
    nonisolated private static func file(_ book: EBook, _ owner: String) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).resolvingSymlinksInPath().standardizedFileURL
        let file = support.appendingPathComponent("Harbor/eBooks/" + key(book, owner) + ".epub")
        guard file.standardizedFileURL == file.resolvingSymlinksInPath().standardizedFileURL else { throw HarborError(code: "ebook-store") }
        return file
    }
}
