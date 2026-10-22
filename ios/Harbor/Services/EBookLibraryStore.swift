import Foundation
import Observation

enum EBookLibraryList: String, Codable, CaseIterable, Hashable, Sendable {
    case saved, favorites, readLater
    var title: String {
        switch self {
        case .saved: "Bookmarked"
        case .favorites: "Favorites"
        case .readLater: "Read later"
        }
    }
    var symbol: String {
        switch self {
        case .saved: "bookmark"
        case .favorites: "heart"
        case .readLater: "clock"
        }
    }
}

struct EBookLibraryDocument: Codable, Sendable {
    var schema = 1
    let owner: String
    var lists: [String: [EBook]]
}

@MainActor protocol EBookLibraryPersistence {
    func read(_ key: String) throws -> EBookLibraryDocument?
    func write(_ value: EBookLibraryDocument, key: String) throws
}
@MainActor private struct KeychainBookLibrary: EBookLibraryPersistence {
    func read(_ key: String) throws -> EBookLibraryDocument? { try KeychainStore().read(key, as: EBookLibraryDocument.self) }
    func write(_ value: EBookLibraryDocument, key: String) throws { try KeychainStore().write(value, key: key) }
}

/// Desktop bookmarks, favorites and read-later are independent from reading progress.
@MainActor @Observable final class EBookLibraryStore {
    let owner: String
    private(set) var ready = false
    private(set) var error: String?
    private var document: EBookLibraryDocument
    @ObservationIgnored private let persistence: any EBookLibraryPersistence
    @ObservationIgnored private let legacy: [EBook]?
    init(owner: String, legacy: [EBook]? = [], persistence: (any EBookLibraryPersistence)? = nil) {
        self.owner = owner; self.legacy = legacy; self.persistence = persistence ?? KeychainBookLibrary()
        document = .init(owner: EBookShelf.hash(owner), lists: [:]); reload()
    }
    func reload() {
        do {
            let loaded = try persistence.read(Self.key(owner))
            let next: EBookLibraryDocument
            if let loaded { next = loaded }
            else {
                guard let legacy else { throw HarborError(code: "ebook-store") }
                next = .init(owner: EBookShelf.hash(owner), lists: [EBookLibraryList.saved.rawValue: legacy.map(\.withoutAlternatives)])
            }
            try validate(next)
            if loaded == nil { try persistence.write(next, key: Self.key(owner)) }
            document = next; ready = true; error = nil
        } catch { ready = false; self.error = "No se pudieron cargar tus listas de libros. Los datos anteriores se conservan." }
    }
    func books(_ list: EBookLibraryList) -> [EBook] { document.lists[list.rawValue] ?? [] }
    func contains(_ book: EBook, in list: EBookLibraryList) -> Bool { books(list).contains { $0.id == book.id } }
    func add(_ book: EBook, to list: EBookLibraryList) throws {
        guard !contains(book, in: list) else { return }
        var next = document; next.lists[list.rawValue] = [book.withoutAlternatives] + books(list); try commit(next)
    }
    func toggle(_ book: EBook, in list: EBookLibraryList) throws {
        var next = document
        next.lists[list.rawValue] = contains(book, in: list) ? books(list).filter { $0.id != book.id } : [book.withoutAlternatives] + books(list)
        try commit(next)
    }
    func removeEverywhere(_ book: EBook) throws {
        var next = document
        for list in EBookLibraryList.allCases { next.lists[list.rawValue] = books(list).filter { $0.id != book.id } }
        try commit(next)
    }
    private func commit(_ next: EBookLibraryDocument) throws {
        guard ready else { throw HarborError(code: "ebook-store") }
        try validate(next); try persistence.write(next, key: Self.key(owner)); document = next; error = nil
    }
    private func validate(_ value: EBookLibraryDocument) throws {
        guard value.schema == 1, value.owner == EBookShelf.hash(owner),
              value.lists.keys.allSatisfy({ EBookLibraryList(rawValue: $0) != nil }),
              value.lists.values.allSatisfy({ $0.count <= 500 && Set($0.map(\.id)).count == $0.count }),
              try JSONEncoder().encode(value).count <= 4 * 1024 * 1024 else { throw HarborError(code: "ebook-store") }
    }
    nonisolated static func key(_ owner: String) -> String { "ebook-lists-" + EBookShelf.hash(owner) }
}
