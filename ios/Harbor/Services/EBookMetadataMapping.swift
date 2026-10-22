import Foundation

enum EBookMetadataMapping {
    static func detail(_ value: JSONValue, preserving book: EBook) -> EBook {
        var fields = raw(book).objectValue
        for (key, value) in value.objectValue where key != "id" {
            if value == .null || value == .string("") || value == .array([]) { continue }
            fields[key] = value
        }
        return books(.array([.object(fields)]), preserving: [book]).first ?? book
    }
    static func raw(_ book: EBook) -> JSONValue {
        var value = book.metadata?.objectValue ?? [:]
        value["id"] = .string(book.id); value["title"] = .string(book.title)
        value["authors"] = .array(book.authors.map(JSONValue.string)); value["description"] = .string(book.description)
        if let cover = book.cover { value["cover"] = .string(cover) }
        if value["source"] == nil { value["source"] = .string("source") }
        if value["genres"] == nil { value["genres"] = .array([]) }
        if let alternatives = book.alternativeSources { value["books"] = .array(alternatives.map(raw)) }
        else { value["books"] = nil }
        return .object(value)
    }
    static func books(_ value: JSONValue, preserving originals: [EBook] = []) -> [EBook] {
        var known: [String: EBook] = [:]
        for book in originals.flatMap({ [$0] + ($0.alternativeSources ?? []) }) { known[book.id] = book }
        func map(_ row: JSONValue) -> EBook? {
            guard let id = row["id"].string, let title = row["title"].string else { return nil }
            var book = known[id] ?? EBook(id: id, title: title)
            book.title = title; book.authors = row["authors"].array.compactMap(\.string)
            book.description = row["description"].string ?? book.description; book.cover = row["cover"].string ?? book.cover
            book.metadata = row
            if known[id] == nil {
                switch row["source"].string {
                case "googlebooks": book.source = "Google Books"
                case "anilist": book.source = "AniList"
                case "wikidata": book.source = "Wikidata"
                case "openlibrary": book.source = "Open Library"
                default: book.source = row["providerName"].string ?? "Books"
                }
            }
            let alternatives = row["books"].array.compactMap(map)
            book.alternativeSources = alternatives.count > 1 ? alternatives : nil
            return book
        }
        return value.array.compactMap(map)
    }
}
