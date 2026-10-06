import Foundation

enum GutenbergCatalog {
    private struct Entry: Sendable { let url: URL; let title: String }
    private static let base = URL(string: "https://www.gutenberg.org")!

    static func catalog(query: String, language: String, page: Int) async throws -> ([EBook], Bool) {
        var components = URLComponents(url: base.appendingPathComponent("ebooks/search.opds/"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "start_index", value: String((max(1, min(10_000, page)) - 1) * 25 + 1))]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        let tree = try BookXML.parse(await data(components.url!))
        guard let feed = tree.descendants("feed").first else { throw HarborError(code: "ebook-format") }
        let next = feed.elements.contains { $0.name == "link" && $0.attributes["rel"] == "next" }
        let entries = feed.elements.filter { $0.name == "entry" }.prefix(32).compactMap { node -> Entry? in
            guard let title = node.elements.first(where: { $0.name == "title" })?.text,
                  let href = node.elements.first(where: { $0.name == "link" && $0.attributes["rel"] == "subsection" })?.attributes["href"],
                  let url = publisherURL(href), url.path.range(of: "^/ebooks/[0-9]+\\.opds$", options: .regularExpression) != nil else { return nil }
            return Entry(url: url, title: title)
        }
        let (books, failed) = try await withThrowingTaskGroup(of: (Int, EBook?, Bool).self) { group in
            var results: [(Int, EBook)] = []
            var failures = 0
            var cursor = 0
            func enqueue(_ index: Int) {
                let entry = entries[index]
                group.addTask {
                    do { return (index, try await book(entry, language: language), false) }
                    catch { try Task.checkCancellation(); return (index, nil, true) }
                }
            }
            while cursor < min(4, entries.count) { enqueue(cursor); cursor += 1 }
            for try await (index, book, failed) in group {
                if failed { failures += 1 }
                if let book { results.append((index, book)) }
                if cursor < entries.count { enqueue(cursor); cursor += 1 }
            }
            return (results.sorted { $0.0 < $1.0 }.map(\.1), failures)
        }
        guard entries.isEmpty || failed < entries.count else { throw HarborError(code: "ebook-network") }
        return (books, next)
    }

    private static func book(_ entry: Entry, language: String) async throws -> EBook? {
        let tree = try BookXML.parse(await data(entry.url))
        for node in tree.descendants("entry") {
            let links = node.elements.filter { $0.name == "link" }
            guard let epub = links.first(where: { $0.attributes["type"]?.hasPrefix("application/epub+zip") == true && $0.attributes["rel"]?.contains("acquisition") == true })?.attributes["href"].flatMap(publisherURL) else { continue }
            let languages = node.elements.filter { $0.name == "language" }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard language.isEmpty || languages.contains(language) else { continue }
            let id = entry.url.lastPathComponent.replacingOccurrences(of: ".opds", with: "")
            let authors = node.elements.filter { $0.name == "author" }.compactMap { $0.elements.first(where: { $0.name == "name" })?.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            let cover = links.first(where: { $0.attributes["rel"] == "http://opds-spec.org/image" })?.attributes["href"].flatMap(publisherURL)
            return EBook(id: "gutendex:" + id, title: node.elements.first(where: { $0.name == "title" })?.text ?? entry.title, authors: authors,
                cover: cover?.absoluteString, language: languages.first, epub: epub.absoluteString)
        }
        return nil
    }

    private static func publisherURL(_ value: String) -> URL? {
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL,
              url.scheme == "https", ["www.gutenberg.org", "gutenberg.org"].contains(url.host ?? ""), url.user == nil, url.password == nil else { return nil }
        return url
    }

    private static func data(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
        request.setValue("Harbor-iOS/0.1", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), response.expectedContentLength <= 2 * 1024 * 1024 else { throw HarborError(code: "ebook-network") }
        var result = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard result.count < 2 * 1024 * 1024 else { throw HarborError(code: "ebook-size") }
            result.append(byte)
        }
        return result
    }
}
