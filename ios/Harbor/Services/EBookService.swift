import Foundation
import PDFKit

actor EBookService {
    static let shared = EBookService()
    private var readers: [String: EPUBReader] = [:]
    private var recent: [String] = []
    func catalog(query: String, language: String, page: Int) async throws -> ([EBook], Bool) {
        // Query the publisher directly; an unavailable mirror delayed every first search.
        return try await GutenbergCatalog.catalog(query: query, language: language, page: page)
    }
    func open(_ book: EBook, owner: String, imported: Data? = nil) async throws -> EBookPublication {
        let key = Self.key(book, owner)
        if let cached = readers[key] { return cached.publication }
        let file = try Self.file(book, owner)
        let persist = imported != nil || !FileManager.default.fileExists(atPath: file.path)
        let data: Data
        if let imported { data = imported }
        else if FileManager.default.fileExists(atPath: file.path) {
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 48 * 1024 * 1024 else { throw HarborError(code: "ebook-size") }
            data = try Data(contentsOf: file)
        } else {
            guard let raw = book.epub, let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw HarborError(code: "ebook-missing") }
            data = try await Self.fetchEPUB(url)
        }
        try Task.checkCancellation()
        let reader = try EPUBReader(data: data)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        if persist { try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        recent.removeAll { $0 == key }; recent.append(key); readers[key] = reader
        while recent.count > 2 { readers.removeValue(forKey: recent.removeFirst()) }
        return reader.publication
    }
    nonisolated private static func fetchEPUB(_ url: URL) async throws -> Data {
        for attempt in 0..<2 {
            try Task.checkCancellation()
            do { return try await fetchEPUBAttempt(url) }
            catch let error as URLError {
                try Task.checkCancellation()
                if error.code == .cancelled { throw CancellationError() }
                guard attempt == 0, error.code == .networkConnectionLost || error.code == .timedOut else { throw HarborError(code: "ebook-network") }
            } catch let error as HarborError {
                try Task.checkCancellation()
                await Diagnostics.shared.recordFailure(error)
                guard error.code.hasPrefix("http-") else { throw error }
                guard attempt == 0, error.code == "http-429" || error.code.hasPrefix("http-5") else { throw HarborError(code: "ebook-network") }
            }
            // Repeat this GET once with a fresh connection. A partial EPUB
            // remains local to the failed attempt and is never persisted.
            try await Task.sleep(for: .milliseconds(500))
        }
        throw HarborError(code: "ebook-network")
    }
    nonisolated private static func fetchEPUBAttempt(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
        configuration.urlCache = nil; configuration.timeoutIntervalForResource = 90
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60))
        guard let response = response as? HTTPURLResponse else { throw HarborError(code: "ebook-network") }
        guard (200..<300).contains(response.statusCode) else { throw HarborError(code: "http-\(response.statusCode)") }
        let limit = 48 * 1024 * 1024
        guard response.expectedContentLength <= Int64(limit) else { throw HarborError(code: "ebook-size") }
        var payload = Data()
        payload.reserveCapacity(Int(max(0, response.expectedContentLength)))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard payload.count < limit else { throw HarborError(code: "ebook-size") }
            payload.append(byte)
        }
        try Task.checkCancellation()
        return payload
    }
    func blocks(_ book: EBook, owner: String, chapter: Int) async throws -> [EBookBlock] {
        _ = try await open(book, owner: owner)
        guard let reader = readers[Self.key(book, owner)], reader.publication.chapters.indices.contains(chapter) else { throw HarborError(code: "ebook-format") }
        return try reader.blocks(reader.publication.chapters[chapter])
    }
    func remove(_ book: EBook, owner: String) throws {
        let key = Self.key(book, owner), file = try Self.file(book, owner)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        let cover = file.deletingPathExtension().appendingPathExtension("cover.jpg")
        if FileManager.default.fileExists(atPath: cover.path) { try FileManager.default.removeItem(at: cover) }
        readers[key] = nil; recent.removeAll { $0 == key }
    }
    func importDocument(_ url: URL, owner: String) async throws -> EBook {
        let ext = url.pathExtension.lowercased()
        guard url.isFileURL, ["pdf", "epub"].contains(ext) else { throw HarborError(code: "ebook-format") }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var payload: Data?
        var readingError: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { file in
            do {
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 48 * 1024 * 1024 else { throw HarborError(code: "ebook-size") }
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var data = Data()
                while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    guard data.count <= 48 * 1024 * 1024 - chunk.count else { throw HarborError(code: "ebook-size") }
                    data.append(chunk)
                }
                payload = data
            } catch { readingError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readingError { throw readingError }
        guard let data = payload, !data.isEmpty, data.count <= 48 * 1024 * 1024 else { throw HarborError(code: "ebook-size") }
        try Task.checkCancellation()
        var book = EBook(id: "local:" + EBookShelf.hash(data), title: url.deletingPathExtension().lastPathComponent, source: "Archivo local", format: ext)
        if ext == "epub" {
            let publication = try await open(book, owner: owner, imported: data)
            book.title = publication.title; book.authors = publication.authors; book.language = publication.language
        } else {
            guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else { throw HarborError(code: "ebook-format") }
            book.title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? book.title
            if let author = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String { book.authors = [author] }
            let destination = try Self.file(book, owner)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return book
    }
    func cover(_ book: EBook, owner: String) async throws -> Data? {
        let original = try Self.file(book, owner)
        guard FileManager.default.fileExists(atPath: original.path) else { return nil }
        let destination = original.deletingPathExtension().appendingPathExtension("cover.jpg")
        if FileManager.default.fileExists(atPath: destination.path) { return try Data(contentsOf: destination) }
        let data: Data
        if book.isPDF { data = try ReadingArtwork.pdfPage(original) }
        else {
            _ = try await open(book, owner: owner)
            guard let reader = readers[Self.key(book, owner)] else { return nil }
            if let cover = reader.coverData { data = try ReadingArtwork.thumbnail(cover) }
            else {
                var first: Data?
                for chapter in reader.publication.chapters.prefix(3) {
                    if let image = try? reader.blocks(chapter).first(where: { $0.image != nil })?.image { first = image; break }
                }
                guard let first else { return nil }
                data = try ReadingArtwork.thumbnail(first)
            }
        }
        try Task.checkCancellation()
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return data
    }
    func pdfURL(_ book: EBook, owner: String) throws -> URL {
        let file = try Self.file(book, owner)
        guard book.isPDF, FileManager.default.fileExists(atPath: file.path) else { throw HarborError(code: "ebook-missing") }
        return file
    }
    nonisolated private static func key(_ book: EBook, _ owner: String) -> String { EBookShelf.hash(owner + "|" + book.id) }
    nonisolated private static func file(_ book: EBook, _ owner: String) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).resolvingSymlinksInPath().standardizedFileURL
        let file = support.appendingPathComponent("Harbor/eBooks/" + key(book, owner) + (book.isPDF ? ".pdf" : ".epub"))
        guard file.standardizedFileURL.path == file.resolvingSymlinksInPath().standardizedFileURL.path else { throw HarborError(code: "ebook-store") }
        return file
    }
}
