import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import HarborCore

/// One font the person imported for subtitles (Desktop's `customFonts` entry: `id`, `name`, `family`, `format`).
/// `family` is the name inside the file, which is what libass matches, and `postScript` is what UIKit and SwiftUI match.
struct SubtitleCustomFont: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let family: String
    let postScript: String
    let fileExtension: String
    let bytes: Int

    var fileName: String { id + "." + fileExtension }
}

/// How the selected font is stored in `PlaybackOptions.subtitleFont`: a built-in id, or `custom:<id>` as on Desktop.
enum SubtitleFontSelection {
    static let prefix = "custom:"

    static func customID(in selection: String) -> String? {
        guard selection.hasPrefix(prefix) else { return nil }
        let id = String(selection.dropFirst(prefix.count))
        return isValidID(id) ? id : nil
    }

    static func selection(forID id: String) -> String {
        prefix + id
    }

    /// Eight lower-case hexadecimal characters, like Desktop's `randomUuid().slice(0, 8)`.
    static func isValidID(_ id: String) -> Bool {
        guard id.utf8.count == 8 else { return false }
        return id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func newID() -> String {
        let text = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(text.prefix(8))
    }

    /// The family mpv is told to use. A custom font that is gone falls back to Inter, like any unknown id.
    static func mpvFamily(for selection: String, builtIn: String) -> String {
        guard let id = customID(in: selection) else { return builtIn }
        return SubtitleFontFamilies.shared.family(forID: id) ?? builtIn
    }

    /// The UIKit font name for the preview and the second line. Nothing found gives Inter.
    static func uiFontName(for selection: String) -> String {
        if let id = customID(in: selection), let name = SubtitleFontFamilies.shared.postScript(forID: id), !name.isEmpty { return name }
        return SubtitleStyleFont(rawValue: selection)?.family ?? "Inter-Regular"
    }

    /// Same, reading the profile's font list first the one time it has not been read in this launch. A font that is gone does not
    /// send the preview and the second line back to the disk on every redraw.
    static func uiFontName(for selection: String, owner: String) -> String {
        if let id = customID(in: selection), SubtitleFontFamilies.shared.postScript(forID: id) == nil,
           !SubtitleFontFamilies.shared.hasListed(owner: owner) {
            _ = SubtitleFontStore.shared.list(owner: owner)
        }
        return uiFontName(for: selection)
    }
}

/// A small thread-safe lookup, because `PlaybackOptions` builds its mpv options away from the main actor.
final class SubtitleFontFamilies: @unchecked Sendable {
    static let shared = SubtitleFontFamilies()
    private let lock = NSLock()
    private var families: [String: String] = [:]
    private var postScripts: [String: String] = [:]
    private var listedOwners = Set<String>()

    func hasListed(owner: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return listedOwners.contains(owner)
    }

    func markListed(owner: String) {
        lock.lock(); defer { lock.unlock() }
        listedOwners.insert(owner)
    }

    func family(forID id: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return families[id]
    }

    func postScript(forID id: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return postScripts[id]
    }

    func replace(with fonts: [SubtitleCustomFont]) {
        lock.lock(); defer { lock.unlock() }
        families = [:]
        postScripts = [:]
        for font in fonts {
            families[font.id] = font.family
            postScripts[font.id] = font.postScript
        }
    }
}

/// The profile's subtitle fonts. mpv composes subtitles itself and reads only one folder (`sub-fonts-dir`), so every imported font is
/// copied into that folder, beside the bundled families the font picker offers. Nothing here touches the reading fonts.
final class SubtitleFontStore: @unchecked Sendable {
    static let shared = SubtitleFontStore()
    static let maximumFonts = 24
    static let maximumDecodedBytes = 128 * 1024 * 1024
    /// The bundled files for the built-in picker choices (`SubtitleStyleFont`), copied into the folder mpv reads.
    static let bundledFontNames = ["Inter", "Fredoka", "Vazirmatn"]

    private let root: URL?
    private let lock = NSLock()
    private var registered = Set<String>()

    init(root: URL? = nil) {
        self.root = root
    }

    /// A short, stable folder name for one profile.
    static func ownerKey(_ owner: String) -> String {
        let digest = SHA256.hash(data: Data(owner.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The fonts that are still on disk, best listed by name. Also makes them known to the player and to UIKit for this launch.
    func list(owner: String) -> [SubtitleCustomFont] {
        lock.lock(); defer { lock.unlock() }
        let fonts = usableFonts(owner: owner)
        SubtitleFontFamilies.shared.replace(with: fonts)
        SubtitleFontFamilies.shared.markListed(owner: owner)
        register(fonts, owner: owner)
        return fonts
    }

    /// Imports one TTF, OTF, WOFF or WOFF2 file. A web font is converted to TTF or OTF first, because libass cannot read it.
    func importFont(from url: URL, owner: String) throws -> SubtitleCustomFont {
        guard url.isFileURL, let format = SubtitleCustomFontRules.format(forFileName: url.lastPathComponent) else {
            throw HarborError(code: "subtitle-font-format")
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else { throw HarborError(code: "subtitle-font-format") }
        guard SubtitleCustomFontRules.accepts(byteCount: size) else { throw HarborError(code: "subtitle-font-size") }
        let original = try Data(contentsOf: url)
        guard original.count == size else { throw HarborError(code: "subtitle-font-format") }
        let isWebFont = format == "woff" || format == "woff2"
        var data = original
        if isWebFont { data = try Self.decodeWebFont(original) }
        guard let names = Self.fontNames(in: data) else { throw HarborError(code: "subtitle-font-format") }
        let font = SubtitleCustomFont(id: SubtitleFontSelection.newID(), name: SubtitleCustomFontRules.displayName(forFileName: url.lastPathComponent),
                                      family: names.family, postScript: names.postScript, fileExtension: Self.sfntExtension(data), bytes: data.count)
        lock.lock(); defer { lock.unlock() }
        var fonts = usableFonts(owner: owner)
        guard fonts.count < Self.maximumFonts else { throw HarborError(code: "subtitle-font-capacity") }
        let folder = try fontsFolder(owner: owner, create: true)
        let file = folder.appendingPathComponent(font.fileName)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        fonts.append(font)
        do {
            try writeIndex(fonts, owner: owner)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        SubtitleFontFamilies.shared.replace(with: fonts)
        register([font], owner: owner)
        return font
    }

    func remove(id: String, owner: String) throws {
        guard SubtitleFontSelection.isValidID(id) else { throw HarborError(code: "subtitle-font-format") }
        lock.lock(); defer { lock.unlock() }
        let fonts = usableFonts(owner: owner)
        guard let font = fonts.first(where: { $0.id == id }) else { return }
        let folder = try fontsFolder(owner: owner, create: false)
        let file = folder.appendingPathComponent(font.fileName)
        let remaining = fonts.filter { $0.id != id }
        try writeIndex(remaining, owner: owner)
        if registered.contains(id) {
            var error: Unmanaged<CFError>?
            _ = CTFontManagerUnregisterFontsForURL(file as CFURL, .process, &error)
            registered.remove(id)
        }
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        SubtitleFontFamilies.shared.replace(with: remaining)
    }

    /// The folder mpv should read as `sub-fonts-dir`, or nil when the profile has no imported font or the folder cannot be prepared.
    /// A nil keeps the bundled folder, so a font problem never reaches playback.
    func playerDirectory(owner: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        let fonts = usableFonts(owner: owner)
        SubtitleFontFamilies.shared.replace(with: fonts)
        SubtitleFontFamilies.shared.markListed(owner: owner)
        register(fonts, owner: owner)
        guard !fonts.isEmpty, let folder = try? fontsFolder(owner: owner, create: false) else { return nil }
        guard copyBundledFonts(into: folder) else { return nil }
        return folder
    }

    // MARK: Files

    private func usableFonts(owner: String) -> [SubtitleCustomFont] {
        guard let folder = try? fontsFolder(owner: owner, create: false),
              let data = try? Data(contentsOf: indexURL(owner: owner)),
              let fonts = try? JSONDecoder().decode([SubtitleCustomFont].self, from: data) else { return [] }
        let usable = fonts.filter { font in
            SubtitleFontSelection.isValidID(font.id) && ["ttf", "otf"].contains(font.fileExtension) && !font.family.isEmpty
                && FileManager.default.fileExists(atPath: folder.appendingPathComponent(font.fileName).path)
        }
        return usable.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func writeIndex(_ fonts: [SubtitleCustomFont], owner: String) throws {
        let folder = try ownerFolder(owner: owner)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let data = try JSONEncoder().encode(fonts)
        try data.write(to: indexURL(owner: owner), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func ownerFolder(owner: String) throws -> URL {
        let base: URL
        if let root {
            base = root
        } else {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            base = support.appendingPathComponent("Harbor", isDirectory: true).appendingPathComponent("SubtitleFonts", isDirectory: true)
        }
        return base.appendingPathComponent(Self.ownerKey(owner), isDirectory: true)
    }

    /// The folder mpv reads. The index lives one level up, so libass never scans it.
    private func fontsFolder(owner: String, create: Bool) throws -> URL {
        let folder = try ownerFolder(owner: owner).appendingPathComponent("mpv", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return folder
    }

    private func indexURL(owner: String) throws -> URL {
        try ownerFolder(owner: owner).appendingPathComponent("index.json")
    }

    /// Copies the bundled picker fonts next to the imported ones when they are missing or changed size (an app update).
    private func copyBundledFonts(into folder: URL) -> Bool {
        var copied = 0
        for name in Self.bundledFontNames {
            guard let source = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            let target = folder.appendingPathComponent(name + ".ttf")
            let sourceSize = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
            let targetSize = (try? target.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -2
            if sourceSize == targetSize { copied += 1; continue }
            try? FileManager.default.removeItem(at: target)
            do {
                try FileManager.default.copyItem(at: source, to: target)
                copied += 1
            } catch {
                return false
            }
        }
        return copied > 0
    }

    /// Makes the font known to UIKit and SwiftUI for this launch, so the preview and the second line can draw it.
    private func register(_ fonts: [SubtitleCustomFont], owner: String) {
        guard let folder = try? fontsFolder(owner: owner, create: false) else { return }
        for font in fonts where !registered.contains(font.id) {
            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(folder.appendingPathComponent(font.fileName) as CFURL, .process, &error)
            registered.insert(font.id)
        }
    }

    // MARK: Font data

    /// The family and PostScript names inside the font data, or nil when it is not a usable font.
    static func fontNames(in data: Data) -> (family: String, postScript: String)? {
        guard !data.isEmpty, let provider = CGDataProvider(data: data as CFData), let graphic = CGFont(provider) else { return nil }
        let font = CTFontCreateWithGraphicsFont(graphic, 12, nil, nil)
        let family = (CTFontCopyFamilyName(font) as String).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !family.isEmpty else { return nil }
        let postScript = (graphic.postScriptName as String?) ?? ""
        return (family: family, postScript: postScript)
    }

    /// "otf" for an OpenType font with CFF outlines (`OTTO`), otherwise "ttf".
    static func sfntExtension(_ data: Data) -> String {
        data.starts(with: [0x4F, 0x54, 0x54, 0x4F]) ? "otf" : "ttf"
    }

    private static func decodeWebFont(_ data: Data) throws -> Data {
        var count = 0
        let output = data.withUnsafeBytes { bytes in harbor_ios_font_decode(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &count) }
        guard let output else { throw HarborError(code: "subtitle-font-format") }
        guard count > 0, count <= maximumDecodedBytes else {
            harbor_ios_font_free(output, count)
            throw HarborError(code: "subtitle-font-format")
        }
        return Data(bytesNoCopy: output, count: count, deallocator: .custom { pointer, length in
            harbor_ios_font_free(pointer.assumingMemoryBound(to: UInt8.self), length)
        })
    }
}
