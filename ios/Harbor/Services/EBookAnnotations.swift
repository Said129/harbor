import Foundation
import JavaScriptCore
import Observation

struct EBookAnnotationRange: Codable, Equatable, Sendable { let line: Int; let start: Int; let end: Int }
struct EBookAnnotation: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var chapterID: String
    var chapterLabel: String?
    var volumeLabel: String?
    var ranges: [EBookAnnotationRange]
    var text: String
    var color = Self.inks[0]
    var density = 58.0
    var title = ""
    var body = ""
    var tags: [String] = []
    var reference = false
    var createdAt = Date().timeIntervalSince1970 * 1000
    static let inks = ["#f2c867", "#efa862", "#e89991", "#d184a5", "#bba4d9", "#9fc8dd", "#8fc9c2", "#b4cfa2"]
    enum CodingKeys: String, CodingKey { case id, chapterID = "chapterId", chapterLabel, volumeLabel, ranges, text, color, density, title, body, tags, reference, createdAt }
    var raw: JSONValue {
        .object(["id": .string(id), "chapterId": .string(chapterID), "ranges": .array(ranges.map { .object(["line": .integer(Int64($0.line)), "start": .integer(Int64($0.start)), "end": .integer(Int64($0.end))]) }), "text": .string(text), "color": .string(color), "density": .number(density), "reference": .bool(reference)])
    }
    func validated() throws -> Self {
        guard !id.isEmpty, id.utf8.count <= 256, !chapterID.isEmpty, chapterID.utf8.count <= 8192,
              Self.inks.contains(color), density.isFinite, (20...90).contains(density), createdAt.isFinite,
              !ranges.isEmpty, ranges.count <= 131072, ranges.allSatisfy({ $0.line >= 0 && $0.line < 131072 && $0.start >= 0 && $0.end > $0.start && $0.end <= 8 * 1024 * 1024 }),
              try JSONEncoder().encode(self).count <= 16 * 1024 * 1024 else { throw HarborError(code: "ebook-annotation") }
        return self
    }
    static func inserting(_ value: Self, in items: [Self]) -> [Self] { Array(([value] + items.filter { $0.id != value.id }).prefix(1000)) }
}

struct EBookAnnotationSelection: Equatable, Sendable { let ranges: [EBookAnnotationRange]; let text: String }
struct EBookAnnotationDocument: Sendable {
    struct Paragraph: Sendable {
        let line: Int; let block: Int; let text: String; let start: Int; let blockStart: Int
        var range: NSRange { .init(location: start, length: text.utf16.count) }
    }
    let text: String
    let paragraphs: [Paragraph]
    static func make(blocks: [EBookBlock]) async -> Self { Self(blocks: blocks) }
    init(blocks: [EBookBlock]) {
        var values: [Paragraph] = [], start = 0
        for block in blocks where block.image == nil && block.imageURL == nil {
            var blockStart = 0
            for paragraph in EBookPrintRules.paragraphs(block.text) {
                values.append(.init(line: values.count, block: block.id, text: paragraph, start: start, blockStart: blockStart))
                start += paragraph.utf16.count + 2; blockStart += paragraph.utf16.count + 2
            }
        }
        paragraphs = values; text = values.map(\.text).joined(separator: "\n\n")
    }
    func selection(_ range: NSRange) -> EBookAnnotationSelection? {
        let count = text.utf16.count
        guard range.location >= 0, range.location <= count, range.length > 0, range.length <= count - range.location else { return nil }
        let ranges = paragraphs.compactMap { paragraph -> EBookAnnotationRange? in
            let overlap = NSIntersectionRange(range, paragraph.range)
            guard overlap.length > 0 else { return nil }
            return .init(line: paragraph.line, start: overlap.location - paragraph.start, end: overlap.location + overlap.length - paragraph.start)
        }
        guard !ranges.isEmpty else { return nil }
        let whitespace = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}"))
        return .init(ranges: ranges, text: (text as NSString).substring(with: range).trimmingCharacters(in: whitespace))
    }
}

struct EBookAnnotationRun: Codable, Equatable, Sendable { let start: Int; let end: Int; let id: String; let color: String; let density: Double }
struct EBookAnnotationPaint: Sendable { let range: NSRange; let id: String; let color: String; let density: Double }

actor EBookAnnotationProgram {
    private struct Asset: Decodable {
        struct Program: Decodable { let source: String; let sha256: String }
        let schema: Int; let reference: String; let inputs: [String: String]; let inks: [String]; let program: Program
    }
    private var context: JSContext?
    func apply(_ input: JSONValue) throws -> JSONValue {
        try Task.checkCancellation()
        if context == nil {
            guard let url = Bundle.main.url(forResource: "EBookAnnotationAssets", withExtension: "json") else { throw HarborError(code: "ebook-annotation-program") }
            let asset = try JSONDecoder().decode(Asset.self, from: Data(contentsOf: url))
            guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987",
                  asset.inputs == ["src/views/ebook/harbor-reader.tsx": "167f062f191238e2bbf016e5902aefc4a47b49a1dd11ce4c5f65608be28871f8"], asset.inks == EBookAnnotation.inks,
                  EBookShelf.hash(Data(asset.program.source.utf8)) == asset.program.sha256,
                  asset.program.sha256 == "72865c75bffb806ffe71a3255f2f77967731572dcc14258561903cef1f47f26b", let engine = JSContext() else { throw HarborError(code: "ebook-annotation-program") }
            engine.evaluateScript(asset.program.source)
            guard engine.exception == nil else { throw HarborError(code: "ebook-annotation-program") }; context = engine
        }
        guard let context else { throw HarborError(code: "ebook-annotation-program") }
        let data = try JSONEncoder().encode(input); guard data.count <= 32 * 1024 * 1024 else { throw HarborError(code: "ebook-annotation-program") }
        context.exception = nil
        let value = context.objectForKeyedSubscript("harborEBookAnnotations")?.call(withArguments: [String(decoding: data, as: UTF8.self)])
        guard context.exception == nil, let text = value?.toString(), let result = text.data(using: .utf8) else { context.exception = nil; throw HarborError(code: "ebook-annotation-program") }
        try Task.checkCancellation(); return try JSONDecoder().decode(JSONValue.self, from: result)
    }
    func paint(_ document: EBookAnnotationDocument, chapterID: String, annotations: [EBookAnnotation]) throws -> [Int: [EBookAnnotationPaint]] {
        struct Painted: Decodable { let line: Int; let runs: [EBookAnnotationRun] }
        var result: [Int: [EBookAnnotationPaint]] = [:]
        guard !annotations.isEmpty else { return result }
        let paragraphs = document.paragraphs.map { JSONValue.object(["text": .string($0.text), "line": .integer(Int64($0.line))]) }
        let value = try apply(.object(["operation": .string("chapter"), "paragraphs": .array(paragraphs), "chapterId": .string(chapterID), "annotations": .array(annotations.map(\.raw))]))
        let painted = try JSONDecoder().decode([Painted].self, from: JSONEncoder().encode(value))
        for line in painted where document.paragraphs.indices.contains(line.line) {
            let paragraph = document.paragraphs[line.line]
            for run in line.runs where run.start >= 0 && run.end > run.start && run.end <= paragraph.text.utf16.count {
                result[paragraph.block, default: []].append(.init(range: .init(location: paragraph.blockStart + run.start, length: run.end - run.start), id: run.id, color: run.color, density: run.density))
            }
        }
        return result
    }
}

protocol EBookAnnotationPersistence: Sendable {
    func read() async throws -> [EBookAnnotation]
    func write(_ values: [EBookAnnotation]) async throws
}
actor EBookAnnotationFile: EBookAnnotationPersistence {
    private struct Document: Codable { var schema = 1; let owner: String; let book: String; let values: [EBookAnnotation] }
    private let owner: String, book: String, file: URL
    init(owner: String, book: String, directory: URL? = nil) throws {
        self.owner = EBookShelf.hash(owner); self.book = EBookShelf.hash(book)
        let root = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Harbor/Books/Annotations")
        file = root.appendingPathComponent(self.owner, isDirectory: true).appendingPathComponent(self.book + ".json")
    }
    func read() throws -> [EBookAnnotation] {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1024 * 1024 else { throw HarborError(code: "ebook-annotation-store") }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file))
        guard document.schema == 1, document.owner == owner, document.book == book, document.values.count <= 1000,
              Set(document.values.map(\.id)).count == document.values.count else { throw HarborError(code: "ebook-annotation-store") }
        return try document.values.map { try $0.validated() }
    }
    func write(_ values: [EBookAnnotation]) throws {
        try Task.checkCancellation()
        guard values.count <= 1000, Set(values.map(\.id)).count == values.count else { throw HarborError(code: "ebook-annotation-store") }
        let data = try JSONEncoder().encode(Document(owner: owner, book: book, values: values.map { try $0.validated() }))
        guard data.count <= 16 * 1024 * 1024 else { throw HarborError(code: "ebook-annotation-store") }
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        guard directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL, file.standardizedFileURL == file.resolvingSymlinksInPath().standardizedFileURL else { throw HarborError(code: "ebook-annotation-store") }
        try Task.checkCancellation(); try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

@MainActor @Observable final class EBookAnnotationStore {
    private let persistence: any EBookAnnotationPersistence
    private(set) var items: [EBookAnnotation] = []
    private(set) var ready = false
    private(set) var busy = false
    private(set) var error: String?
    private(set) var revision = 0
    init(owner: String, book: String, persistence: (any EBookAnnotationPersistence)? = nil) throws { self.persistence = try persistence ?? EBookAnnotationFile(owner: owner, book: book) }
    func load() async {
        guard !busy, !ready else { return }; busy = true; defer { busy = false }
        do { let values = try await persistence.read(); try Task.checkCancellation(); items = values; ready = true; error = nil; revision += 1 }
        catch is CancellationError { return }
        catch { error = DesktopInterfaceText.value("Error") }
    }
    func save(_ value: EBookAnnotation) async throws { try await commit(EBookAnnotation.inserting(try value.validated(), in: items)) }
    func remove(_ id: String) async throws { try await commit(items.filter { $0.id != id }) }
    private func commit(_ values: [EBookAnnotation]) async throws {
        guard ready, !busy else { throw HarborError(code: "ebook-annotation-store") }; busy = true; defer { busy = false }
        try await persistence.write(values); items = values; revision += 1; error = nil
    }
}
