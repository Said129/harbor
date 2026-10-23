import CryptoKit
import Foundation
import JavaScriptCore

struct EBookSearchParagraph: Sendable {
    let block: Int
    let text: String
    static func make(_ blocks: [EBookBlock]) -> [Self] {
        blocks.filter { $0.image == nil && $0.imageURL == nil }.flatMap { block in
            EBookPrintRules.paragraphs(block.text).map { Self(block: block.id, text: $0) }
        }
    }
}
struct EBookPassageSearch: Decodable, Sendable {
    struct Result: Decodable, Identifiable, Sendable {
        let index: Int
        let text: String
        var id: Int { index }
        var preview: String { (text as NSString).substring(to: min(220, (text as NSString).length)) }
    }
    let shown: [Result]
    let hidden: Int
    let total: Int
    static let empty = Self(shown: [], hidden: 0, total: 0)
}
struct EBookReadingJump: Sendable {
    let id = UUID()
    let block: Int
}

/// The original pure chapter search executes without network or native script bridges.
actor EBookSearchProgram {
    private struct Asset: Decodable {
        struct Program: Decodable { let source: String; let sha256: String }
        let schema: Int; let reference: String; let inputs: [String: String]; let program: Program
    }
    private var context: JSContext?
    func search(_ paragraphs: [String], query: String, current: Int, revealFuture: Bool) throws -> EBookPassageSearch {
        let input: JSONValue = .object(["paragraphs": .array(paragraphs.map(JSONValue.string)), "query": .string(query), "current": .integer(Int64(current)), "showFutureResults": .bool(revealFuture)])
        return try JSONDecoder().decode(EBookPassageSearch.self, from: JSONEncoder().encode(apply(input)))
    }
    func apply(_ input: JSONValue) throws -> JSONValue {
        try Task.checkCancellation()
        let paragraphs = input["paragraphs"].array
        guard paragraphs.count <= 131072, paragraphs.allSatisfy({ $0.string != nil }),
              paragraphs.reduce(0, { $0 + ($1.string?.utf8.count ?? 0) }) <= 8 * 1024 * 1024,
              let query = input["query"].string, query.utf8.count <= 4096 else { throw HarborError(code: "ebook-search") }
        try load(); guard let context else { throw HarborError(code: "ebook-search") }
        let data = try JSONEncoder().encode(input)
        context.exception = nil
        let value = context.objectForKeyedSubscript("harborEBookSearch")?.call(withArguments: [String(decoding: data, as: UTF8.self)])
        guard context.exception == nil, let text = value?.toString(), let result = text.data(using: .utf8) else {
            context.exception = nil; throw HarborError(code: "ebook-search")
        }
        try Task.checkCancellation()
        return try JSONDecoder().decode(JSONValue.self, from: result)
    }
    private func load() throws {
        guard context == nil else { return }
        guard let url = Bundle.main.url(forResource: "EBookSearchAssets", withExtension: "json") else { throw HarborError(code: "ebook-search") }
        let asset = try JSONDecoder().decode(Asset.self, from: Data(contentsOf: url))
        let sha = SHA256.hash(data: Data(asset.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
        guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987",
              asset.inputs == ["src/views/ebook/harbor-reader.tsx": "167f062f191238e2bbf016e5902aefc4a47b49a1dd11ce4c5f65608be28871f8"],
              sha == asset.program.sha256, sha == "3a0bd21fce10c7499ec64f2e7b754d70f5197ac0f817eb0f9ee99a100a85841a", let engine = JSContext() else { throw HarborError(code: "ebook-search") }
        engine.evaluateScript(asset.program.source)
        guard engine.exception == nil else { throw HarborError(code: "ebook-search") }; context = engine
    }
}
