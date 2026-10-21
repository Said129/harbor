import CryptoKit
import Foundation
import JavaScriptCore

struct EBookBrowseFilters: Codable, Equatable, Sendable {
    var group = "All"
    var genre = ""
    var status = "any"
    var language = "any"
    var sort = "popular"
    var sourceTag: String { status == "any" ? "sort:" + sort : "status:" + status }
}

struct EBookCatalogDefinitions: Decodable, Sendable {
    let categories: [String: [String]]
    let genres: [String]
}

struct EBookCatalogResult: Sendable {
    let books: [EBook]
    let titles: [String: String]
}

/// A serial, off-UI execution context for pinned Desktop pure functions only.
/// No installed script, native object, account, network or filesystem bridge is exported.
actor EBookCatalogProgram {
    private struct Asset: Decodable {
        struct Program: Decodable { let source: String; let sha256: String }
        let schema: Int
        let reference: String
        let inputs: [String: String]
        let program: Program
        let definitions: EBookCatalogDefinitions
    }
    private var context: JSContext?
    private var definitions: EBookCatalogDefinitions?

    func filter(_ books: [EBook], filters: EBookBrowseFilters, titleLanguage: String) throws -> EBookCatalogResult {
        try Task.checkCancellation()
        let flattened = books.flatMap { $0.alternativeSources ?? [$0] }
        var native: [String: EBook] = [:]
        let raw = flattened.map { book -> JSONValue in
            native[book.id] = book
            var fields = book.metadata?.objectValue ?? [:]
            fields["id"] = .string(book.id); fields["title"] = .string(book.title)
            fields["authors"] = .array(book.authors.map(JSONValue.string))
            if fields["source"] == nil { fields["source"] = .string("source") }
            if fields["genres"] == nil { fields["genres"] = .array([]) }
            return .object(fields)
        }
        let result = try apply(.object(["books": .array(raw), "filters": try .encoded(filters), "titleLanguage": .string(titleLanguage)]))
        var output: [EBook] = [], titles: [String: String] = [:]
        for row in result.array {
            guard let id = row["id"].string, var book = native[id] else { continue }
            let routes = row["routes"].array.compactMap { $0.string.flatMap { native[$0] } }
            book.alternativeSources = routes.count > 1 ? routes : nil
            output.append(book); titles[id] = row["title"].string ?? book.title
        }
        try Task.checkCancellation()
        return .init(books: output, titles: titles)
    }

    func filterDefinitions() throws -> EBookCatalogDefinitions {
        try load()
        guard let definitions else { throw HarborError(code: "ebook-catalog") }
        return definitions
    }

    func apply(_ input: JSONValue) throws -> JSONValue {
        try Task.checkCancellation(); try load()
        guard let context else { throw HarborError(code: "ebook-catalog") }
        let data = try JSONEncoder().encode(input)
        context.exception = nil
        let result = context.objectForKeyedSubscript("harborEBookCatalog")?.call(withArguments: [String(decoding: data, as: UTF8.self)])
        guard context.exception == nil, let text = result?.toString(), let output = text.data(using: .utf8) else {
            context.exception = nil
            throw HarborError(code: "ebook-catalog")
        }
        try Task.checkCancellation()
        return try JSONDecoder().decode(JSONValue.self, from: output)
    }

    private func load() throws {
        guard context == nil else { return }
        guard let url = Bundle.main.url(forResource: "EBookCatalogAssets", withExtension: "json") else { throw HarborError(code: "ebook-catalog") }
        let asset = try JSONDecoder().decode(Asset.self, from: Data(contentsOf: url))
        let hash = SHA256.hash(data: Data(asset.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
        guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987", asset.inputs.count == 3,
              hash == asset.program.sha256, hash == "53346856ad401229d174d033c070b0bddfa6aea1536a96541b11c346f63d41b1", let engine = JSContext() else { throw HarborError(code: "ebook-catalog") }
        engine.evaluateScript(asset.program.source)
        guard engine.exception == nil else { throw HarborError(code: "ebook-catalog") }
        context = engine; definitions = asset.definitions
    }
}
