import Foundation
import ZIPFoundation

/// EPUB containers stay in memory; entries are never extracted to paths from
/// the book. Every read verifies CRC and bounds actual decompressed bytes.
final class EPUBReader {
    private let archive: Archive
    let publication: EBookPublication
    init(data: Data) throws {
        guard data.count <= 48 * 1024 * 1024 else { throw HarborError(code: "ebook-size") }
        let archive = try Archive(data: data, accessMode: .read)
        var count = 0, total: UInt64 = 0
        for entry in archive {
            count += 1
            guard count <= 5_000, entry.uncompressedSize <= 12 * 1024 * 1024, total <= 192 * 1024 * 1024 else { throw HarborError(code: "ebook-size") }
            total += entry.uncompressedSize
        }
        guard total <= 192 * 1024 * 1024 else { throw HarborError(code: "ebook-size") }
        guard archive["META-INF/encryption.xml"] == nil else { throw HarborError(code: "ebook-encrypted") }
        let container = try BookXML.parse(Self.read(archive, path: "META-INF/container.xml", limit: 256 * 1024))
        guard let opfPath = container.descendants("rootfile").first?.attributes["full-path"], Self.safePath(opfPath) else { throw HarborError(code: "ebook-format") }
        let opf = try BookXML.parse(Self.read(archive, path: opfPath, limit: 2 * 1024 * 1024))
        let manifest = opf.descendants("item")
        var paths: [String: String] = [:]
        for item in manifest {
            if let id = item.attributes["id"], let href = item.attributes["href"], let path = Self.resolve(href, base: opfPath) { paths[id] = path }
        }
        var titles: [String: String] = [:]
        if let nav = manifest.first(where: { ($0.attributes["properties"] ?? "").split(separator: " ").contains("nav") }), let id = nav.attributes["id"], let path = paths[id], let document = try? BookXML.parse(Self.read(archive, path: path, limit: 2 * 1024 * 1024)) {
            for link in document.descendants("a") {
                if let href = link.attributes["href"], let target = Self.resolve(href, base: path), titles[target] == nil { titles[target] = link.text.normalizedBookText }
            }
        }
        if titles.isEmpty, let ncx = manifest.first(where: { $0.attributes["media-type"] == "application/x-dtbncx+xml" }), let id = ncx.attributes["id"], let path = paths[id], let document = try? BookXML.parse(Self.read(archive, path: path, limit: 2 * 1024 * 1024)) {
            for point in document.descendants("navPoint") {
                if let href = point.descendants("content").first?.attributes["src"], let target = Self.resolve(href, base: path) { titles[target] = point.descendants("navLabel").first?.text.normalizedBookText }
            }
        }
        var seen = Set<String>()
        let chapters = opf.descendants("itemref").compactMap { reference -> EBookChapter? in
            guard reference.attributes["linear"] != "no", let id = reference.attributes["idref"], let path = paths[id], seen.insert(path).inserted,
                  let item = manifest.first(where: { $0.attributes["id"] == id }), ["application/xhtml+xml", "text/html"].contains(item.attributes["media-type"] ?? ""), archive[path] != nil else { return nil }
            return EBookChapter(path: path, title: titles[path].flatMap { $0.isEmpty ? nil : $0 } ?? "Sección \(seen.count)")
        }
        guard !chapters.isEmpty else { throw HarborError(code: "ebook-format") }
        self.archive = archive
        publication = EBookPublication(title: opf.descendants("title").first?.text.normalizedBookText ?? "eBook", authors: opf.descendants("creator").map { $0.text.normalizedBookText }, language: opf.descendants("language").first?.text.normalizedBookText, chapters: chapters)
    }
    func blocks(_ chapter: EBookChapter) throws -> [EBookBlock] {
        let document = try BookXML.parse(Self.read(archive, path: chapter.path, limit: 4 * 1024 * 1024))
        let root = document.descendants("body").first ?? document
        var blocks: [EBookBlock] = []
        let textNames: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "pre", "figcaption"]
        func image(_ node: BookXML.Node) {
            guard let raw = node.attributes["src"], let path = Self.resolve(raw, base: chapter.path), let data = try? Self.read(archive, path: path, limit: 12 * 1024 * 1024) else { return }
            blocks.append(EBookBlock(id: blocks.count, text: node.attributes["alt"] ?? "Ilustración", image: data))
        }
        func walk(_ node: BookXML.Node) {
            guard !BookXML.ignored.contains(node.name) else { return }
            if node.name == "img" { image(node); return }
            if textNames.contains(node.name) {
                let text = node.text.normalizedBookText
                if !text.isEmpty { blocks.append(EBookBlock(id: blocks.count, text: text, heading: node.name.hasPrefix("h") && node.name.count == 2)) }
                for illustration in node.descendants("img") { image(illustration) }
            } else {
                for content in node.content {
                    switch content {
                    case .element(let child): walk(child)
                    case .text(let text):
                        let value = text.normalizedBookText
                        if !value.isEmpty { blocks.append(EBookBlock(id: blocks.count, text: value)) }
                    }
                }
            }
        }
        walk(root)
        guard !blocks.isEmpty else { throw HarborError(code: "ebook-empty") }
        return blocks
    }
    private static func read(_ archive: Archive, path: String, limit: Int) throws -> Data {
        guard safePath(path), let entry = archive[path], entry.type == .file, entry.uncompressedSize <= UInt64(limit) else { throw HarborError(code: "ebook-format") }
        var data = Data()
        let crc = try archive.extract(entry) { chunk in
            try Task.checkCancellation()
            guard data.count <= limit - chunk.count else { throw HarborError(code: "ebook-size") }
            data.append(chunk)
        }
        guard data.count == Int(entry.uncompressedSize), crc == entry.checksum else { throw HarborError(code: "ebook-format") }
        return data
    }
    private static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && !path.split(separator: "/").contains("..")
    }
    private static func resolve(_ href: String, base: String) -> String? {
        guard !href.contains("\\"), let origin = URL(string: "https://epub.invalid/" + base), let url = URL(string: href, relativeTo: origin)?.absoluteURL, url.scheme == "https", url.host == "epub.invalid", url.port == nil, url.user == nil, url.password == nil else { return nil }
        let path = String(url.path.dropFirst())
        return safePath(path) ? path : nil
    }
}

private enum BookXML {
    static let ignored: Set<String> = ["script", "style", "noscript", "nav", "form", "svg", "head"]
    final class Node {
        enum Content { case text(String), element(Node) }
        let name: String
        let attributes: [String: String]
        var content: [Content] = []
        init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
        var text: String {
            guard !ignored.contains(name) else { return "" }
            return content.map { part in switch part { case .text(let value): value; case .element(let node): node.name == "br" ? "\n" : node.text } }.joined()
        }
        func descendants(_ name: String) -> [Node] {
            (self.name == name ? [self] : []) + content.flatMap { part -> [Node] in if case .element(let node) = part { return node.descendants(name) }; return [] }
        }
    }
    final class Parser: NSObject, XMLParserDelegate {
        let root = Node("root", [:])
        var stack: [Node] = []
        var count = 0
        override init() { super.init(); stack = [root] }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            count += 1
            guard count <= 40_000, stack.count <= 100 else { parser.abortParsing(); return }
            let node = Node(name.split(separator: ":").last.map(String.init) ?? name, attributes)
            stack.last?.content.append(.element(node)); stack.append(node)
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.content.append(.text(string)) }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if let text = String(data: CDATABlock, encoding: .utf8) { stack.last?.content.append(.text(text)) } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { if stack.count > 1 { stack.removeLast() } }
    }
    static func parse(_ data: Data) throws -> Node {
        let parser = XMLParser(data: data), delegate = Parser()
        parser.shouldResolveExternalEntities = false; parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        guard parser.parse() else { throw HarborError(code: "ebook-format") }
        return delegate.root
    }
}

private extension String {
    var normalizedBookText: String { replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
}
