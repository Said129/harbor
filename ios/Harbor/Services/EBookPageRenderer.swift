import Foundation
import CoreText
import ImageIO
import UniformTypeIdentifiers

struct EBookPrintedRow: Codable, Equatable, Sendable {
    let text: String
    let paragraph: Int
}
struct EBookPrintLayout: Codable, Equatable, Sendable {
    let bodySize: Int
    let rowHeight: Int
    let rowsPerPage: Int
    let pages: [[EBookPrintedRow]]
    var paragraphStarts: [Int] { pages.map { $0.first?.paragraph ?? 0 } }
}

/// Layout rules from Desktop 0.9.132 lib/ebook/book-pages.ts. Measurement is supplied by the native font.
enum EBookPrintRules {
    static let width = 1200, height = 1600, padX = 118, padY = 124
    static let whitespaceScalars: [UInt32] = [9, 10, 11, 12, 13, 32, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288, 65279]
    private static let whitespace = CharacterSet(charactersIn: String(String.UnicodeScalarView(whitespaceScalars.compactMap { UnicodeScalar($0) })))
    static func paragraphs(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: whitespace) }.filter { !$0.isEmpty }
    }
    static func validate(_ text: String, fontSize: Double, lineHeight: Double) throws {
        try Task.checkCancellation()
        guard fontSize.isFinite, lineHeight.isFinite, (1...1024).contains(fontSize), (0.1...10).contains(lineHeight), text.utf8.count <= 8 * 1024 * 1024 else { throw HarborError(code: "ebook-page-layout") }
    }
    static func layout(_ text: String, fontSize: Double, lineHeight: Double, measure: (String) -> Double) throws -> EBookPrintLayout {
        try validate(text, fontSize: fontSize, lineHeight: lineHeight)
        let bodySize = Int((fontSize * 1.72).rounded()), rowHeight = max(1, Int((Double(bodySize) * lineHeight).rounded()))
        let rowsPerPage = max(8, (height - padY * 2) / rowHeight)
        var rows: [EBookPrintedRow] = []
        for (paragraph, text) in paragraphs(text).enumerated() {
            try Task.checkCancellation()
            var line = "", position = 0
            for word in text.components(separatedBy: whitespace).filter({ !$0.isEmpty }) {
                if position % 64 == 0 { try Task.checkCancellation() }; position += 1
                let next = line.isEmpty ? word : line + " " + word
                if line.isEmpty || measure(next) <= Double(width - padX * 2) { line = next }
                else { rows.append(.init(text: line, paragraph: paragraph)); line = word }
            }
            if !line.isEmpty { rows.append(.init(text: line, paragraph: paragraph)) }
            rows.append(.init(text: "", paragraph: paragraph))
        }
        let pages = stride(from: 0, to: rows.count, by: rowsPerPage).map { Array(rows[$0..<min(rows.count, $0 + rowsPerPage)]) }
        return .init(bodySize: bodySize, rowHeight: rowHeight, rowsPerPage: rowsPerPage, pages: pages)
    }
    static func resumePage(starts: [Int], paragraph: Int) -> Int {
        starts.lastIndex(where: { $0 <= paragraph }) ?? 0
    }
}

enum EBookPaper: String, Sendable {
    case dark, dim, light
    var desk: String { switch self { case .dark: "090a0c"; case .dim: "17130f"; case .light: "c8c0b3" } }
    var page: String { switch self { case .dark: "17181b"; case .dim: "2d261e"; case .light: "f4eddf" } }
    var ink: String { switch self { case .dark: "e9e3d8"; case .dim: "eadbc5"; case .light: "29251f" } }
    var muted: String { switch self { case .dark: "8f8b84"; case .dim: "aa9a86"; case .light: "776f64" } }
    static func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [CGFloat((value >> 16) & 255) / 255, CGFloat((value >> 8) & 255) / 255, CGFloat(value & 255) / 255, alpha])!
    }
}
struct EBookPrintFont: Sendable {
    let face: String
    var data: Data?
    func create(_ size: CGFloat) throws -> CTFont {
        if let data {
            guard let provider = CGDataProvider(data: data as CFData), let graphic = CGFont(provider) else { throw HarborError(code: "reading-font-format") }
            return CTFontCreateWithGraphicsFont(graphic, size, nil, nil)
        }
        let name = face == "classic" ? "Palatino-Roman" : face == "arabic" ? "Vazirmatn-Regular" : "Georgia"
        return CTFontCreateWithName(name as CFString, size, nil)
    }
}
struct EBookPrintedDocument: Sendable {
    let id: String
    let layout: EBookPrintLayout
    let font: EBookPrintFont
    let paper: EBookPaper
    let rtl: Bool
    let title: String
    let blockIDs: [Int]
    func block(at page: Int) -> Int {
        guard layout.pages.indices.contains(page) else { return blockIDs.first ?? 0 }
        let paragraph = layout.paragraphStarts[page]
        return blockIDs.indices.contains(paragraph) ? blockIDs[paragraph] : blockIDs.first ?? 0
    }
    func resumePage(block: Int) -> Int {
        let paragraph = blockIDs.firstIndex(of: block) ?? 0
        return EBookPrintRules.resumePage(starts: layout.paragraphStarts, paragraph: paragraph)
    }
}

/// Only requested pages are rasterized. The actor keeps at most eight compressed pages, not a chapter of bitmaps.
actor EBookPageRenderer {
    static let shared = EBookPageRenderer()
    private let cache = NSCache<NSString, NSData>()
    init() { cache.countLimit = 8; cache.totalCostLimit = 16 * 1024 * 1024 }
    private func line(_ text: String, font: CTFont, color: CGColor, rtl: Bool) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): color,
            .init(kCTWritingDirectionAttributeName as String): [rtl ? 1 : 0],
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
    func prepare(blocks: [EBookBlock], font: EBookPrintFont, fontSize: Double, lineHeight: Double, paper: EBookPaper, rtl: Bool, title: String, owner: String) throws -> EBookPrintedDocument {
        let textBlocks = blocks.filter { $0.image == nil && $0.imageURL == nil }
        let text = textBlocks.map(\.text).joined(separator: "\n\n")
        try EBookPrintRules.validate(text, fontSize: fontSize, lineHeight: lineHeight)
        let nativeFont = try font.create(CGFloat((fontSize * 1.72).rounded()))
        let ink = EBookPaper.color(paper.ink)
        let layout = try EBookPrintRules.layout(text, fontSize: fontSize, lineHeight: lineHeight) { value in
            CTLineGetTypographicBounds(line(value, font: nativeFont, color: ink, rtl: rtl), nil, nil, nil)
        }
        let identity = [owner, text, title, String(fontSize), String(lineHeight), font.face, font.data.map(EBookShelf.hash) ?? "", paper.rawValue, String(rtl)].joined(separator: "\u{0}")
        let ids = textBlocks.flatMap { block in EBookPrintRules.paragraphs(block.text).map { _ in block.id } }
        return .init(id: EBookShelf.hash(identity), layout: layout, font: font, paper: paper, rtl: rtl, title: title, blockIDs: ids)
    }
    func page(_ document: EBookPrintedDocument, index: Int) throws -> Data {
        try Task.checkCancellation()
        guard document.layout.pages.indices.contains(index) else { throw HarborError(code: "ebook-page-layout") }
        let key = (document.id + ":" + String(index)) as NSString
        if let data = cache.object(forKey: key) { return data as Data }
        let width = EBookPrintRules.width, height = EBookPrintRules.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw HarborError(code: "ebook-page-layout") }
        context.setFillColor(EBookPaper.color(document.paper.page)); context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let colors = document.rtl ? [EBookPaper.color("000000", alpha: 0), EBookPaper.color("000000", alpha: 0.13)] : [EBookPaper.color("000000", alpha: 0.13), EBookPaper.color("000000", alpha: 0)]
        let stops: [CGFloat] = document.rtl ? [0.72, 0.94] : [0.06, 0.28]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: stops) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: CGFloat(width), y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        let font = try document.font.create(CGFloat(document.layout.bodySize))
        for (rowIndex, row) in document.layout.pages[index].enumerated() {
            try Task.checkCancellation()
            let text = line(row.text, font: font, color: EBookPaper.color(document.paper.ink), rtl: document.rtl)
            let advance = CTLineGetTypographicBounds(text, nil, nil, nil)
            let x = document.rtl ? Double(width - EBookPrintRules.padX) - advance : Double(EBookPrintRules.padX)
            context.textPosition = CGPoint(x: x, y: Double(height - EBookPrintRules.padY - rowIndex * document.layout.rowHeight) - CTFontGetAscent(font))
            CTLineDraw(text, context)
        }
        let footer = line(document.title + "  ·  " + String(index + 1), font: try document.font.create(22), color: EBookPaper.color(document.paper.muted), rtl: document.rtl)
        context.textPosition = CGPoint(x: (Double(width) - CTLineGetTypographicBounds(footer, nil, nil, nil)) / 2, y: 62 - CTFontGetAscent(try document.font.create(22)))
        CTLineDraw(footer, context)
        try Task.checkCancellation()
        guard let image = context.makeImage() else { throw HarborError(code: "ebook-page-layout") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw HarborError(code: "ebook-page-layout") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw HarborError(code: "ebook-page-layout") }
        try Task.checkCancellation(); cache.setObject(data, forKey: key, cost: data.length)
        return data as Data
    }
    func clearImages() { cache.removeAllObjects() }
}
