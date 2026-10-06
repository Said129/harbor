import Foundation
import CryptoKit
import Observation

struct EBook: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var authors: [String] = []
    var description: String = ""
    var cover: String?
    var language: String?
    var epub: String?
    var source = "Project Gutenberg"
}

struct EBookBookmark: Codable, Identifiable, Sendable {
    let id: UUID
    let chapter: Int
    let block: Int
    let preview: String
}

struct EBookRecord: Codable, Identifiable, Sendable {
    var book: EBook
    var chapter = 0
    var block = 0
    var completed = false
    var updated = Date()
    var bookmarks: [EBookBookmark] = []
    var id: String { book.id }
}

@MainActor @Observable
final class EBookShelf {
    let owner: String
    private(set) var records: [EBookRecord] = []
    private(set) var ready = false
    var error: String?
    init(owner: String) {
        self.owner = owner
        do { records = try KeychainStore().read(Self.key(owner), as: [EBookRecord].self) ?? []; ready = true }
        catch { self.error = "No se pudo leer tu estantería. Los libros y el progreso se conservan." }
    }
    func record(_ book: EBook) -> EBookRecord? { records.first { $0.id == book.id } }
    func save(_ record: EBookRecord) throws {
        guard ready else { throw HarborError(code: "ebook-store") }
        var next = records.filter { $0.id != record.id }; next.append(record)
        guard next.count <= 500, try JSONEncoder().encode(next).count <= 2 * 1024 * 1024 else { throw HarborError(code: "ebook-store") }
        try KeychainStore().write(next, key: Self.key(owner)); records = next
    }
    func savePosition(_ book: EBook, chapter: Int, block: Int) throws {
        guard chapter >= 0, block >= 0 else { throw HarborError(code: "ebook-store") }
        // Merge only the position into the latest record. A delayed scroll save
        // must preserve bookmarks and read-state changes made in the meantime.
        var next = record(book) ?? EBookRecord(book: book)
        next.chapter = chapter; next.block = block; next.updated = Date()
        try save(next)
    }
    func remove(_ book: EBook) throws {
        guard ready else { throw HarborError(code: "ebook-store") }
        let next = records.filter { $0.id != book.id }
        try KeychainStore().write(next, key: Self.key(owner)); records = next
    }
    nonisolated static func hash(_ raw: String) -> String { SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined() }
    nonisolated private static func key(_ owner: String) -> String { "ebook-shelf-" + hash(owner) }
}

struct EBookChapter: Identifiable, Sendable {
    let path: String
    let title: String
    var id: String { path }
}
struct EBookPublication: Sendable {
    let title: String
    let authors: [String]
    let language: String?
    let chapters: [EBookChapter]
}
struct EBookBlock: Identifiable, Sendable {
    let id: Int
    let text: String
    var heading = false
    var image: Data?
}
