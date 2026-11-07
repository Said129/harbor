import Foundation

/// Pure theme logic shared by the iPhone/iPad theme library, import and export.
/// Mirrors Desktop's custom theme JSON (src/lib/custom-themes.ts: parseThemeJson,
/// exportThemeJson, TOKEN_KEYS) for the parts iOS can render: name, blurb, swatch,
/// the 12 color tokens and an optional background image with its dim value.
/// Desktop-only parts (css, js, html, layouts, card/button styles, chrome, logo,
/// fonts, nav) are ignored on import and never written on export.

enum ThemeTokenNames {
    /// Token order from Desktop TOKEN_KEYS, without the "--color-" prefix.
    static let all: [String] = [
        "canvas", "surface", "elevated", "raised", "ink", "ink-muted", "ink-subtle",
        "edge", "edge-soft", "accent", "accent-soft", "danger",
    ]

    static func desktopKey(_ token: String) -> String {
        "--color-" + token
    }
}

enum ThemeBackgroundDefaults {
    /// Desktop default settings.theme.backgroundDim (src/lib/theme.ts).
    static let dim = 0.65
    /// Desktop MAX_IMAGE_BYTES (src/views/settings/theme-panel/image-utils.ts).
    static let maxImportBytes = 8_000_000
    static let maxNameLength = 60
    static let maxBlurbLength = 160
}

/// Validation failures. The views turn these into Desktop's English messages
/// (custom-themes-section.tsx localizeImportError), each passed through DesktopInterfaceText.value.
enum ThemeFileError: Error, Equatable {
    case unreadable
    case notATheme
    case missingName
    case invalidSwatch
    case missingColors
    /// Carries the Desktop key, for example "--color-accent".
    case missingColor(String)
}

struct ThemeImportBackground: Equatable {
    var imageData: Data
    /// Valid Desktop dim (0...1) or ThemeBackgroundDefaults.dim when missing or out of range.
    var dim: Double
}

struct ThemeImport: Equatable {
    var name: String
    var blurb: String
    /// Keys are token names without "--color-", values are RGBA components in 0...1.
    var tokens: [String: [Double]]
    var background: ThemeImportBackground?
}

struct ThemeLibraryEntry: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var blurb: String
    var tokens: [String: [Double]]
    /// The background image itself lives in ThemeBackgroundStore under `ThemeBackgroundStore.name(for: id)`.
    var hasBackground: Bool
    var backgroundDim: Double
}

struct ThemeLibrary: Codable, Equatable {
    private(set) var entries: [ThemeLibraryEntry]

    init(entries: [ThemeLibraryEntry] = []) {
        self.entries = entries
    }

    /// Replaces the entry with the same id, or appends it.
    mutating func save(_ entry: ThemeLibraryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    func entry(id: String) -> ThemeLibraryEntry? {
        entries.first { $0.id == id }
    }

    /// Loads stored data, dropping any entry that would not pass validation.
    static func restored(from data: Data?) -> ThemeLibrary {
        guard let data, let decoded = try? JSONDecoder().decode(ThemeLibrary.self, from: data) else {
            return ThemeLibrary()
        }
        return ThemeLibrary(entries: decoded.entries.filter { isValid($0) })
    }

    /// Builds a new entry. The name is trimmed and clamped to Desktop's 60 characters,
    /// the blurb to 160, and the dim to 0...1.
    static func makeEntry(
        name: String,
        blurb: String = "",
        tokens: [String: [Double]],
        hasBackground: Bool,
        backgroundDim: Double,
        id: String = UUID().uuidString
    ) throws -> ThemeLibraryEntry {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ThemeFileError.missingName }
        var checked: [String: [Double]] = [:]
        for token in ThemeTokenNames.all {
            guard let values = tokens[token], ThemeColorCodec.isValidRGBA(values) else {
                throw ThemeFileError.missingColor(ThemeTokenNames.desktopKey(token))
            }
            checked[token] = values
        }
        let dim = backgroundDim.isFinite ? min(1, max(0, backgroundDim)) : ThemeBackgroundDefaults.dim
        return ThemeLibraryEntry(
            id: id,
            name: String(trimmed.prefix(ThemeBackgroundDefaults.maxNameLength)),
            blurb: String(blurb.prefix(ThemeBackgroundDefaults.maxBlurbLength)),
            tokens: checked,
            hasBackground: hasBackground,
            backgroundDim: dim
        )
    }

    static func isValid(_ entry: ThemeLibraryEntry) -> Bool {
        guard !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return ThemeTokenNames.all.allSatisfy { token in
            entry.tokens[token].map { ThemeColorCodec.isValidRGBA($0) } ?? false
        }
    }
}

enum ThemeFileCodec {
    /// Mirrors parseThemeJson: same checks, same order, same messages.
    static func decode(_ data: Data) -> Result<ThemeImport, ThemeFileError> {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(.unreadable)
        }
        guard let root = object as? [String: Any] else {
            return .failure(.notATheme)
        }
        let name = ((root["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.missingName) }
        let blurb = (root["blurb"] as? String) ?? ""
        guard let swatch = root["swatch"] as? [String], swatch.count == 3,
              swatch.allSatisfy({ ThemeColorCodec.isHexText($0) }) else {
            return .failure(.invalidSwatch)
        }
        guard let rawTokens = root["tokens"] as? [String: Any] else {
            return .failure(.missingColors)
        }
        var tokens: [String: [Double]] = [:]
        for token in ThemeTokenNames.all {
            let key = ThemeTokenNames.desktopKey(token)
            let text = ((rawTokens[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let values = ThemeColorCodec.parse(text) else {
                return .failure(.missingColor(key))
            }
            tokens[token] = values
        }
        let imported = ThemeImport(
            name: String(name.prefix(ThemeBackgroundDefaults.maxNameLength)),
            blurb: String(blurb.prefix(ThemeBackgroundDefaults.maxBlurbLength)),
            tokens: tokens,
            background: decodeBackground(root["background"])
        )
        return .success(imported)
    }

    /// Returns nil for anything iOS cannot show (URLs, gradients, SVG), as Desktop drops invalid backgrounds.
    private static func decodeBackground(_ raw: Any?) -> ThemeImportBackground? {
        guard let object = raw as? [String: Any], let image = object["image"] as? String else { return nil }
        let text = image.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "data:image/"
        let marker = ";base64,"
        guard text.hasPrefix(prefix), let range = text.range(of: marker) else { return nil }
        let subtype = String(text[text.index(text.startIndex, offsetBy: prefix.count)..<range.lowerBound])
        guard ["png", "jpeg", "jpg", "webp", "gif"].contains(subtype) else { return nil }
        let payload = String(text[range.upperBound...])
        guard let data = Data(base64Encoded: payload), !data.isEmpty,
              data.count <= ThemeBackgroundDefaults.maxImportBytes else { return nil }
        let dim = (object["dim"] as? Double).flatMap { value -> Double? in
            value.isFinite && value >= 0 && value <= 1 ? value : nil
        } ?? ThemeBackgroundDefaults.dim
        return ThemeImportBackground(imageData: data, dim: dim)
    }

    /// Writes Desktop's JSON shape: name, blurb, swatch, tokens with "--color-" keys, optional background.
    static func encode(_ entry: ThemeLibraryEntry, imageData: Data?) throws -> Data {
        var tokens: [String: String] = [:]
        for token in ThemeTokenNames.all {
            tokens[ThemeTokenNames.desktopKey(token)] = ThemeColorCodec.hex(entry.tokens[token] ?? [0, 0, 0, 1])
        }
        let swatch = ["canvas", "elevated", "accent"].map { ThemeColorCodec.hex(entry.tokens[$0] ?? [0, 0, 0, 1]) }
        var background: ThemeFileBackground?
        if entry.hasBackground, let imageData, !imageData.isEmpty {
            background = ThemeFileBackground(
                image: "data:image/jpeg;base64," + imageData.base64EncodedString(),
                dim: entry.backgroundDim
            )
        }
        let document = ThemeFileDocument(
            name: entry.name,
            blurb: entry.blurb,
            swatch: swatch,
            tokens: tokens,
            background: background
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// Same file name rule as Desktop's export: runs of characters outside [a-z0-9-_] become "-".
    static func fileName(for name: String) -> String {
        var output = ""
        for character in name.lowercased() {
            let keep = character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
            if keep {
                output.append(character)
            } else if output.last != "-" {
                output.append("-")
            }
        }
        return (output.isEmpty ? "theme" : output) + ".json"
    }
}

private struct ThemeFileDocument: Encodable {
    let name: String
    let blurb: String
    let swatch: [String]
    let tokens: [String: String]
    let background: ThemeFileBackground?
}

private struct ThemeFileBackground: Encodable {
    let image: String
    let dim: Double
}

enum ThemeColorCodec {
    static func isHexText(_ text: String) -> Bool {
        guard text.hasPrefix("#") else { return false }
        let digits = text.dropFirst()
        return (digits.count == 6 || digits.count == 8) && digits.allSatisfy { $0.isHexDigit }
    }

    static func isValidRGBA(_ values: [Double]) -> Bool {
        values.count == 4 && values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
    }

    /// Parses the color forms Desktop themes use that iPhone can show: #rrggbb, #rrggbbaa,
    /// rgb()/rgba() and oklch(). Returns nil for anything else.
    static func parse(_ text: String) -> [Double]? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") { return parseHex(value) }
        if let inner = functionBody(value, prefix: "rgba(") ?? functionBody(value, prefix: "rgb(") {
            return parseRGB(inner)
        }
        if let inner = functionBody(value, prefix: "oklch(") {
            return parseOKLCH(inner)
        }
        return nil
    }

    /// Writes #rrggbb, or #rrggbbaa only when the color is not fully opaque.
    static func hex(_ rgba: [Double]) -> String {
        guard rgba.count == 4 else { return "#000000" }
        var text = String(format: "#%02x%02x%02x", byteValue(rgba[0]), byteValue(rgba[1]), byteValue(rgba[2]))
        if rgba[3] < 1 {
            text += String(format: "%02x", byteValue(rgba[3]))
        }
        return text
    }

    private static func byteValue(_ value: Double) -> Int {
        let clamped = value.isFinite ? min(1, max(0, value)) : 0
        return Int((clamped * 255).rounded())
    }

    private static func functionBody(_ value: String, prefix: String) -> String? {
        guard value.hasPrefix(prefix), value.hasSuffix(")") else { return nil }
        return String(value.dropFirst(prefix.count).dropLast())
    }

    private static func parseHex(_ value: String) -> [Double]? {
        guard isHexText(value) else { return nil }
        let digits = Array(value.dropFirst())
        var output: [Double] = []
        var index = 0
        while index < digits.count {
            let pair = String(digits[index]) + String(digits[index + 1])
            guard let byte = Int(pair, radix: 16) else { return nil }
            output.append(Double(byte) / 255)
            index += 2
        }
        if output.count == 3 { output.append(1) }
        return output
    }

    /// Splits "a b c / d" or "a, b, c, d" into three or four parts.
    private static func arguments(_ body: String) -> [String]? {
        let halves = body.split(separator: "/", omittingEmptySubsequences: false)
        guard halves.count == 1 || halves.count == 2 else { return nil }
        var parts = halves[0].split(whereSeparator: { $0 == " " || $0 == "," }).map { String($0) }
        if halves.count == 2 {
            let alpha = String(halves[1]).trimmingCharacters(in: .whitespaces)
            guard !alpha.isEmpty else { return nil }
            parts.append(alpha)
        }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        return parts
    }

    private static func percentValue(_ text: String) -> Double? {
        guard text.hasSuffix("%") else { return nil }
        return Double(String(text.dropLast()))
    }

    private static func parseRGB(_ body: String) -> [Double]? {
        guard let parts = arguments(body) else { return nil }
        var output: [Double] = []
        for part in parts.prefix(3) {
            let channel: Double
            if let percent = percentValue(part) {
                channel = percent / 100
            } else if let number = Double(part) {
                channel = number / 255
            } else {
                return nil
            }
            output.append(min(1, max(0, channel)))
        }
        output.append(alphaComponent(parts.count == 4 ? parts[3] : "1") ?? 1)
        return output.allSatisfy({ $0.isFinite }) ? output : nil
    }

    private static func alphaComponent(_ text: String) -> Double? {
        if let percent = percentValue(text) { return min(1, max(0, percent / 100)) }
        guard let number = Double(text) else { return nil }
        return min(1, max(0, number))
    }

    /// Converts oklch(L C H [/ A]) to sRGB, clamped to gamut.
    private static func parseOKLCH(_ body: String) -> [Double]? {
        guard let parts = arguments(body) else { return nil }
        let lightness: Double
        if let percent = percentValue(parts[0]) {
            lightness = percent / 100
        } else if let number = Double(parts[0]) {
            lightness = number
        } else {
            return nil
        }
        let chroma: Double
        if let percent = percentValue(parts[1]) {
            chroma = percent / 100 * 0.4
        } else if let number = Double(parts[1]) {
            chroma = number
        } else {
            return nil
        }
        let hueText = parts[2].hasSuffix("deg") ? String(parts[2].dropLast(3)) : parts[2]
        guard let hue = Double(hueText) else { return nil }
        let radians = hue * Double.pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)
        let lRoot = lightness + 0.3963377774 * a + 0.2158037573 * b
        let mRoot = lightness - 0.1055613458 * a - 0.0638541728 * b
        let sRoot = lightness - 0.0894841775 * a - 1.2914855480 * b
        let l = lRoot * lRoot * lRoot
        let m = mRoot * mRoot * mRoot
        let s = sRoot * sRoot * sRoot
        let red = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let green = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let blue = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        let alpha = alphaComponent(parts.count == 4 ? parts[3] : "1") ?? 1
        let output = [gammaEncode(red), gammaEncode(green), gammaEncode(blue), alpha]
        return output.allSatisfy({ $0.isFinite }) ? output : nil
    }

    private static func gammaEncode(_ linear: Double) -> Double {
        let clamped = linear.isFinite ? min(1, max(0, linear)) : 0
        let encoded = clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        return min(1, max(0, encoded))
    }
}
