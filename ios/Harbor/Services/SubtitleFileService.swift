import Foundation

struct ImportedSubtitle: Sendable {
    let url: URL
    let title: String
}

/// Desktop's `lib/subtitles/encoding.ts`, as far as iOS needs it before mpv reads a subtitle file. A UTF-16 byte-order mark is decoded,
/// UTF-8 is kept byte for byte, and any other file takes the legacy code page that scores best, in Desktop's order.
enum SubtitleTextEncoding {
    /// The file as UTF-8, or nil when the bytes stay as they are: UTF-8 already, or a UTF-8 mark (mpv reads it).
    static func convertedUTF8(_ data: Data, language: String?) -> Data? {
        if data.starts(with: [0xFF, 0xFE]) { return String(data: Data(data.dropFirst(2)), encoding: .utf16LittleEndian).map { Data($0.utf8) } }
        if data.starts(with: [0xFE, 0xFF]) { return String(data: Data(data.dropFirst(2)), encoding: .utf16BigEndian).map { Data($0.utf8) } }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) || String(data: data, encoding: .utf8) != nil { return nil }
        var candidates: [(encoding: String, text: String)] = [(encoding: "utf-8", text: String(decoding: data, as: UTF8.self))]
        for name in legacyEncodings(language: language) {
            if let text = decodeLegacy(data, name) { candidates.append((encoding: name, text: text)) }
        }
        // Desktop's reduce: the first candidate with the highest score wins, so a tie keeps the earlier one.
        var selected: (text: String, score: Double)?
        for candidate in candidates {
            let value = score(candidate.text, language: language)
            if let current = selected, value <= current.score { continue }
            selected = (text: candidate.text, score: value)
        }
        return selected.map { Data($0.text.utf8) }
    }

    /// Desktop's `ARABIC_SINGLE_BYTE_ENCODINGS` and `GENERAL_SINGLE_BYTE_ENCODINGS`, named for CoreFoundation.
    static func legacyEncodings(language: String?) -> [String] {
        isArabic(language) ? ["windows-1256", "iso-8859-6", "windows-1252"] : ["windows-1252", "windows-1256", "iso-8859-6"]
    }

    private static func isArabic(_ language: String?) -> Bool {
        let normalized = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: "-")
        return ["ar", "ara", "arabic"].contains(normalized) || normalized.hasPrefix("ar-")
    }

    private static func decodeLegacy(_ data: Data, _ name: String) -> String? {
        let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard encoding != CFStringEncoding(kCFStringEncodingInvalidId) else { return nil }
        return String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding)))
    }

    /// Desktop's `assessCandidate`. The Arabic word-list plausibility term is not ported, so Arabic ties can differ from Desktop.
    private static func score(_ text: String, language: String?) -> Double {
        let scalars = Array(text.unicodeScalars)
        let content = scalars.filter { !$0.properties.isWhitespace }
        let denominator = Double(max(1, content.count))
        let replacement = scalars.filter { $0.value == 0xFFFD }.count
        let controls = scalars.filter { isControl($0) }.count
        let printable = content.filter { $0.value != 0xFFFD && !isControl($0) }.count
        let printableRatio = Double(printable) / denominator
        let mojibake = matchCount(text, "(?:Ã.|Â.|â.|Ø.|Ù.)")
        let timestamps = matchCount(text, "[0-9]{1,2}:[0-9]{2}:[0-9]{2}[,.][0-9]{1,3}\\s*-->")
            + matchCount(text, "^Dialogue:[^\\n]*,[0-9]+:[0-9]{2}:[0-9]{2}\\.[0-9]{1,3},", options: [.anchorsMatchLines, .caseInsensitive])
        let letters = matchCount(text, "\\p{L}")
        let arabic = matchCount(text, "\\p{Script=Arabic}")
        let arabicRatio = Double(arabic) / Double(max(1, letters))
        let trimmed = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let arabicLanguage = isArabic(language)
        var value = 0.16 + printableRatio * 0.64
        if replacement > 0 { value -= 0.32 + min(0.4, Double(replacement) / denominator) }
        value -= min(0.5, Double(controls) / Double(max(1, scalars.count)) * 6)
        value -= min(0.35, Double(mojibake) / denominator * 8)
        if timestamps > 0 { value += 0.06 }
        if trimmed.isEmpty && arabicRatio >= 0.25 { value += 0.03 }
        if !trimmed.isEmpty && !arabicLanguage && arabicRatio >= 0.25 { value -= 0.08 }
        if arabicLanguage {
            if arabicRatio >= 0.25 { value += 0.05 } else if letters >= 8 { value -= 0.18 }
            if letters >= 8 { value -= (1 - arabicRatio) * 0.08 }
        }
        return min(1, max(0, value))
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        let code = scalar.value
        if code == 0x0A || code == 0x0D || code == 0x09 { return false }
        return code < 0x20 || (code >= 0x7F && code <= 0x9F)
    }

    private static func matchCount(_ text: String, _ pattern: String, options: NSRegularExpression.Options = []) -> Int {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return 0 }
        return expression.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
    }
}

/// A Files selection is copied while its security-scoped access is held.
/// Session copies remain available to mpv until that player has closed.
actor SubtitleFileService {
    static let shared = SubtitleFileService()
    static let extensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub"]
    private static let maximumSize = 8 * 1024 * 1024
    private static let remoteSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    static func remoteRequest(_ text: String) throws -> URLRequest {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { throw HarborError(code: "subtitle-file") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Harbor-iOS/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, text/vtt, application/octet-stream, */*", forHTTPHeaderField: "Accept")
        return request
    }

    func download(_ input: PlaybackSource.Subtitle, session: UUID) async throws -> ImportedSubtitle {
        try Task.checkCancellation()
        let request = try Self.remoteRequest(input.url)
        let root = try directory(session, create: true)
        guard try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count < 24 else { throw HarborError(code: "subtitle-capacity") }
        let (bytes, response) = try await Self.remoteSession.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              response.expectedContentLength <= Int64(Self.maximumSize) else { throw HarborError(code: "subtitle-file") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.maximumSize else { throw HarborError(code: "subtitle-file") }
            data.append(byte)
        }
        try Task.checkCancellation()
        if let converted = SubtitleTextEncoding.convertedUTF8(data, language: input.lang) { data = converted }
        let prefix = String(data: data.prefix(1024), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !data.isEmpty, !prefix.hasPrefix("<!doctype html"), !prefix.hasPrefix("<html"), data.prefix(2) != Data([0x50, 0x4b]) else { throw HarborError(code: "subtitle-file") }
        let supplied = request.url?.pathExtension.lowercased() ?? ""
        let ext = Self.extensions.contains(supplied) ? supplied : prefix.contains("[script info]") ? "ass" : prefix.hasPrefix("webvtt") ? "vtt" : "srt"
        let url = root.appendingPathComponent(UUID().uuidString + "." + ext)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return ImportedSubtitle(url: url, title: input.title ?? "Addon")
    }

    private func directory(_ session: UUID, create: Bool) throws -> URL {
        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: create)
        let root = base.appendingPathComponent("HarborSubtitles", isDirectory: true).appendingPathComponent(session.uuidString, isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var protected = root
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try protected.setResourceValues(values)
        }
        return root
    }

    func copy(_ input: URL, session: UUID) async throws -> ImportedSubtitle {
        let access = input.startAccessingSecurityScopedResource()
        defer { if access { input.stopAccessingSecurityScopedResource() } }
        let ext = input.pathExtension.lowercased()
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard Self.extensions.contains(ext), values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= Self.maximumSize else { throw HarborError(code: "subtitle-file") }
        let root = try directory(session, create: true)
        guard try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count < 24 else { throw HarborError(code: "subtitle-capacity") }
        let staging = root.appendingPathComponent("." + UUID().uuidString + ".import")
        defer { try? FileManager.default.removeItem(at: staging) }
        guard FileManager.default.createFile(atPath: staging.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw HarborError(code: "subtitle-file") }
        let reader = try FileHandle(forReadingFrom: input), writer = try FileHandle(forWritingTo: staging)
        defer { try? reader.close(); try? writer.close() }
        var copied = 0
        while let bytes = try reader.read(upToCount: 64 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            copied += bytes.count
            guard copied <= size else { throw HarborError(code: "subtitle-file") }
            try writer.write(contentsOf: bytes)
            await Task.yield()
        }
        guard copied == size else { throw HarborError(code: "subtitle-file") }
        try Task.checkCancellation()
        try writer.synchronize(); try writer.close()
        let raw = try Data(contentsOf: staging)
        if let converted = SubtitleTextEncoding.convertedUTF8(raw, language: nil) {
            try converted.write(to: staging, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let url = root.appendingPathComponent(UUID().uuidString + "." + ext)
        try FileManager.default.moveItem(at: staging, to: url)
        let title = String(input.lastPathComponent.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(200))
        return ImportedSubtitle(url: url, title: title.isEmpty ? "Subtítulo importado" : title)
    }

    func discard(_ file: ImportedSubtitle, session: UUID) {
        guard let root = try? directory(session, create: false), file.url.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: file.url)
    }

    func synchronized(_ text: String, vtt: Bool, session: UUID) throws -> ImportedSubtitle {
        let data = Data(text.utf8)
        guard !data.isEmpty, data.count <= Self.maximumSize else { throw HarborError(code: "subtitle-file") }
        let root = try directory(session, create: true)
        guard try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count < 24 else { throw HarborError(code: "subtitle-capacity") }
        let url = root.appendingPathComponent(UUID().uuidString + (vtt ? ".vtt" : ".srt"))
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return ImportedSubtitle(url: url, title: "Sincronizado automáticamente")
    }

    func cleanup(_ session: UUID) {
        guard let root = try? directory(session, create: false) else { return }
        try? FileManager.default.removeItem(at: root)
    }
}
