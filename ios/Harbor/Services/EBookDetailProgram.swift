import CryptoKit
import Foundation
import JavaScriptCore

struct EBookVolume: Decodable, Identifiable, Sendable {
    let volume: String
    let label: String
    let number: Double?
    let chapters: [JSONValue]
    var id: String { volume }
}

struct EBookInformationRow: Decodable, Sendable {
    let label: String
    let value: String
}

/// Only pinned, pure Desktop presentation rules execute here, without native bridges.
actor EBookDetailProgram {
    private struct Asset: Decodable {
        struct Program: Decodable { let source: String; let sha256: String }
        let schema: Int
        let reference: String
        let inputs: [String: String]
        let program: Program
    }
    private var context: JSContext?

    func groups(_ chapters: [EBookChapter]) throws -> [EBookVolume] {
        try decode(apply(.object(["operation": .string("groups"), "chapters": .array(chapters.map(\.raw))])))
    }

    func ordered(_ chapters: [EBookChapter], volume: String, query: String, newest: Bool) throws -> [EBookChapter] {
        let value = try apply(.object(["chapters": .array(chapters.map(\.raw)), "volume": .string(volume), "query": .string(query), "sort": .string(newest ? "newest" : "oldest")]))
        let known = Dictionary(chapters.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return value.array.compactMap { $0["id"].string.flatMap { known[$0] } }
    }

    func information(_ book: EBook, translations: [String: String]) throws -> [EBookInformationRow] {
        try decode(apply(.object(["operation": .string("information"), "book": EBookMetadataMapping.raw(book), "translations": .object(translations.mapValues(JSONValue.string))])))
    }

    func apply(_ input: JSONValue) throws -> JSONValue {
        try Task.checkCancellation(); try load()
        guard let context else { throw HarborError(code: "ebook-catalog") }
        let data = try JSONEncoder().encode(input)
        context.exception = nil
        let result = context.objectForKeyedSubscript("harborEBookDetail")?.call(withArguments: [String(decoding: data, as: UTF8.self)])
        guard context.exception == nil, let text = result?.toString(), let output = text.data(using: .utf8) else {
            context.exception = nil; throw HarborError(code: "ebook-catalog")
        }
        try Task.checkCancellation()
        return try JSONDecoder().decode(JSONValue.self, from: output)
    }

    private func decode<T: Decodable>(_ value: JSONValue) throws -> T { try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value)) }
    private func load() throws {
        guard context == nil else { return }
        guard let url = Bundle.main.url(forResource: "EBookDetailAssets", withExtension: "json") else { throw HarborError(code: "ebook-catalog") }
        let asset = try JSONDecoder().decode(Asset.self, from: Data(contentsOf: url))
        let hash = SHA256.hash(data: Data(asset.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
        guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987",
              asset.inputs == ["src/views/ebook.tsx": "5a4c1e436eaa0936c4de72f8253c66a90ae4c71958cef63bbdf5323f3dd763dc"],
              hash == asset.program.sha256, hash == "7bd0fd5b881f8918f9b87b375c432a793498903b2e83ed939b77dfb221e7cdca", let engine = JSContext() else { throw HarborError(code: "ebook-catalog") }
        engine.evaluateScript(asset.program.source)
        guard engine.exception == nil else { throw HarborError(code: "ebook-catalog") }
        context = engine
    }
}
