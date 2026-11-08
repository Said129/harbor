import Foundation

/// Desktop's custom subtitle font rules (`lib/custom-fonts.ts`): accepted files, the size limit and the display name.
/// The import itself is not ported: the iOS subtitle renderer lives in `Player` and only knows the built-in families.
enum SubtitleCustomFontRules {
    static let formats: [String: String] = ["ttf": "truetype", "otf": "opentype", "woff": "woff", "woff2": "woff2"]
    static let maximumBytes = 32 * 1024 * 1024

    /// The format for a file name's extension, matched without case, or nil when the file is not an accepted font.
    static func format(forFileName name: String) -> String? {
        let extensionPart = name.split(separator: ".", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return formats[extensionPart.lowercased()]
    }

    static func accepts(byteCount: Int) -> Bool {
        byteCount <= maximumBytes
    }

    /// Desktop's `prettyName`: drop the last extension, turn dashes and underscores into spaces, collapse spaces, cut to 36 characters.
    static func displayName(forFileName name: String) -> String {
        var base = name
        if let dot = name.lastIndex(of: "."), name.index(after: dot) < name.endIndex {
            base = String(name[..<dot])
        }
        let spaced = base.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
        let collapsed = spaced.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "Custom font" : String(collapsed.prefix(36))
    }
}
