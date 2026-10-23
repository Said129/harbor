import Foundation
import CryptoKit
import NaturalLanguage

struct EBookNarrationVoice: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let locale: String
    let gender: String
    let name: String
    var label: String { name.replacingOccurrences(of: "Microsoft ", with: "").replacingOccurrences(of: " Online (Natural)", with: "") }
}
struct EBookNarrationBoundary: Codable, Equatable, Sendable { let offsetMs: Double; let durationMs: Double; let text: String }
struct EBookNarrationAudio: Codable, Sendable { let audio: Data; let boundaries: [EBookNarrationBoundary] }
struct EBookNarrationProgress: Equatable, Sendable { let completed: Int; let total: Int; var percent: Int { completed * 100 / max(1, total) } }
enum EBookNarrationError: Error { case input, response, emptyAudio, timeout }
struct EBookNarrationCatalog: Decodable, Sendable {
    let schema: Int; let reference: String; let inputs: [String: String]
    let voices: [EBookNarrationVoice]; let samples: [String: String]; let locales: [String: String]
    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "EBookNarrationAssets", withExtension: "json") else { throw EBookNarrationError.response }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.schema == 1, value.reference == "8274f05485554e531cf5654574de84108f16bdb7",
              value.inputs == ["src/views/ebook/harbor-reader.tsx": "f7e467b133daf92e7b8b882a070cf2a3254592ad5d09cbc29a34b6fc3a81679f"], value.voices.count == 20 else { throw EBookNarrationError.response }
        return value
    }
    func sample(locale: String, fallback: String) -> String { locales[locale] ?? samples[locale.components(separatedBy: "-")[0].lowercased()] ?? String(fallback.prefix(320)) }
}

/// Wire format and chunk rules from Harbor's ebook_tts.rs and its pinned
/// kothok-edge-tts 0.2.10 dependency. See EBookNarrationNotices.txt.
enum EBookEdgeProtocol {
    static let token = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    static let version = "1-143.0.3650.75"
    static func validID(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 96 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 } }
    static func validLocale(_ value: String) -> Bool { (2...24).contains(value.utf8.count) && value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || $0 == 45 } }
    static func gec(at date: Date, skew: Int = 0) -> String {
        let seconds = UInt64(max(0, date.timeIntervalSince1970 + Double(skew))) + 11_644_473_600
        let ticks = (seconds - seconds % 300) * 10_000_000
        return SHA256.hash(data: Data((String(ticks) + token).utf8)).map { String(format: "%02X", $0) }.joined()
    }
    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return formatter.string(from: date)
    }
    static func request(voices: Bool, date: Date = Date(), skew: Int = 0) throws -> URLRequest {
        let prefix = voices ? "https" : "wss", path = voices ? "voices/list" : "edge/v1"
        var components = URLComponents(string: "\(prefix)://speech.platform.bing.com/consumer/speech/synthesize/readaloud/\(path)")!
        components.queryItems = [.init(name: "TrustedClientToken", value: token), .init(name: "Sec-MS-GEC", value: gec(at: date, skew: skew)), .init(name: "Sec-MS-GEC-Version", value: version)]
        if !voices { components.queryItems?.append(.init(name: "ConnectionId", value: UUID().uuidString.replacingOccurrences(of: "-", with: ""))) }
        guard let url = components.url else { throw EBookNarrationError.input }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("muid=\(UUID().uuidString.replacingOccurrences(of: "-", with: ""));", forHTTPHeaderField: "Cookie")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }
    static func chunks(_ text: String) throws -> [String] {
        let scalars = text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
        guard !scalars.isEmpty, scalars.count <= 500_000 else { throw EBookNarrationError.input }
        var start = scalars.startIndex, result: [String] = []
        while start < scalars.endIndex {
            var end = start, bytes = 0, split: String.UnicodeScalarView.Index?
            while end < scalars.endIndex {
                let scalar = scalars[end], size = scalar.utf8.count
                if bytes + size > 3600 { break }
                bytes += size; end = scalars.index(after: end)
                if bytes >= 1800, scalar.properties.isWhitespace || ".!?؟؛".unicodeScalars.contains(scalar) { split = end }
            }
            if end < scalars.endIndex, let split { end = split }
            let value = String(scalars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { result.append(value) }
            start = end
            while start < scalars.endIndex, scalars[start].properties.isWhitespace { start = scalars.index(after: start) }
        }
        return result
    }
    static func ssml(_ text: String, voice: String, locale: String, rate: Int) throws -> String {
        guard validID(voice), validLocale(locale) else { throw EBookNarrationError.input }
        let clean = String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            scalar.value <= 8 || scalar.value == 11 || scalar.value == 12 || (14...31).contains(scalar.value) ? UnicodeScalar(32)! : scalar
        }))
        let escaped = clean.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "'", with: "&apos;").replacingOccurrences(of: "\"", with: "&quot;")
        let speed = min(100, max(-50, rate))
        return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(locale)'><voice name='\(voice)'><prosody pitch='+0Hz' rate='\(speed >= 0 ? "+" : "")\(speed)%' volume='+0%'>\(escaped)</prosody></voice></speak>"
    }
    static func configuration(date: Date) -> String {
        "X-Timestamp:\(timestamp(date))\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"true\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n"
    }
    static func binaryAudio(_ data: Data) -> Data? {
        guard data.count >= 2 else { return nil }; let bytes = [UInt8](data.prefix(2))
        let length = Int(bytes[0]) * 256 + Int(bytes[1]); guard length <= data.count - 2 else { return nil }
        let header = String(decoding: data.dropFirst(2).prefix(length), as: UTF8.self)
        guard header.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "Path:audio" }) else { return nil }
        return Data(data.dropFirst(2 + length))
    }
    static func textMessage(_ value: String) -> (path: String, body: String) {
        guard let split = value.range(of: "\r\n\r\n") else { return ("", "") }
        let header = value[..<split.lowerBound].components(separatedBy: .newlines)
        let path = header.first { $0.hasPrefix("Path:") }?.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (path, String(value[split.upperBound...]))
    }
    static func boundaries(_ body: String) -> [EBookNarrationBoundary] {
        struct Envelope: Decodable {
            struct Item: Decodable {
                struct Value: Decodable {
                    struct Word: Decodable { let text: String; enum CodingKeys: String, CodingKey { case text = "Text" } }
                    let offset: UInt64; let duration: UInt64; let text: Word
                    enum CodingKeys: String, CodingKey { case offset = "Offset", duration = "Duration", text }
                }
                let type: String; let data: Value?
                enum CodingKeys: String, CodingKey { case type = "Type", data = "Data" }
                init(from decoder: Decoder) throws {
                    let values = try decoder.container(keyedBy: CodingKeys.self)
                    type = (try? values.decode(String.self, forKey: .type)) ?? ""
                    data = try? values.decode(Value.self, forKey: .data)
                }
            }
            let metadata: [Item]
            enum CodingKeys: String, CodingKey { case metadata = "Metadata" }
        }
        guard body.utf8.count <= 2 * 1024 * 1024, let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(body.utf8)) else { return [] }
        return envelope.metadata.compactMap { item in
            guard item.type == "WordBoundary", let value = item.data else { return nil }
            return .init(offsetMs: Double(value.offset) / 10_000, durationMs: Double(value.duration) / 10_000, text: value.text.text)
        }
    }
}

protocol EBookNarrationTransport: Sendable {
    func voices() async throws -> [EBookNarrationVoice]
    func synthesize(_ text: String, voice: String, locale: String, rate: Int) async throws -> EBookNarrationAudio
}
struct EBookEdgeTransport: EBookNarrationTransport {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }
    func voices() async throws -> [EBookNarrationVoice] {
        struct Voice: Decodable { let ShortName: String; let Locale: String; let Gender: String; let FriendlyName: String }
        let (data, response) = try await session.data(for: EBookEdgeProtocol.request(voices: true))
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2 * 1024 * 1024 else { throw EBookNarrationError.response }
        let voices = try JSONDecoder().decode([Voice].self, from: data).filter { EBookEdgeProtocol.validID($0.ShortName) && EBookEdgeProtocol.validLocale($0.Locale) }
        guard !voices.isEmpty else { throw EBookNarrationError.response }
        return voices.map { .init(id: $0.ShortName, locale: $0.Locale, gender: $0.Gender, name: $0.FriendlyName) }
    }
    func synthesize(_ text: String, voice: String, locale: String, rate: Int) async throws -> EBookNarrationAudio {
        let ssml = try EBookEdgeProtocol.ssml(text, voice: voice, locale: locale, rate: rate)
        var skew = 0
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let socket = session.webSocketTask(with: try EBookEdgeProtocol.request(voices: false, skew: skew))
            socket.maximumMessageSize = 2 * 1024 * 1024; socket.resume()
            do {
                return try await withTaskCancellationHandler {
                    defer { socket.cancel(with: .normalClosure, reason: nil) }
                    let date = Date()
                    try await socket.send(.string(EBookEdgeProtocol.configuration(date: date)))
                    try await socket.send(.string("X-RequestId:\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:\(EBookEdgeProtocol.timestamp(date))Z\r\nPath:ssml\r\n\r\n\(ssml)"))
                    var audio = Data(), boundaries: [EBookNarrationBoundary] = []
                    while true {
                        try Task.checkCancellation()
                        let message: URLSessionWebSocketTask.Message
                        do { message = try await Self.receive(socket) }
                        catch {
                            if socket.closeCode == .normalClosure, !audio.isEmpty { return EBookNarrationAudio(audio: audio, boundaries: boundaries) }
                            throw error
                        }
                        switch message {
                        case .data(let data):
                            if let bytes = EBookEdgeProtocol.binaryAudio(data) { audio.append(bytes) }
                        case .string(let text):
                            let message = EBookEdgeProtocol.textMessage(text)
                            if message.path == "audio.metadata" { boundaries += EBookEdgeProtocol.boundaries(message.body) }
                            if message.path == "turn.end" {
                                guard !audio.isEmpty else { throw EBookNarrationError.emptyAudio }
                                return EBookNarrationAudio(audio: audio, boundaries: boundaries)
                            }
                        @unknown default: break
                        }
                        guard audio.count <= 128 * 1024 * 1024, boundaries.count <= 500_000 else { throw EBookNarrationError.response }
                    }
                } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
            } catch {
                socket.cancel(with: .goingAway, reason: nil); try Task.checkCancellation()
                let code = (socket.response as? HTTPURLResponse)?.statusCode
                if code == 401 || code == 403 { skew += 60 }
                if attempt == 2 { throw error }
            }
        }
        throw EBookNarrationError.response
    }
    private static func receive(_ socket: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await socket.receive() }
            group.addTask { try await Task.sleep(for: .seconds(30)); socket.cancel(with: .goingAway, reason: nil); throw EBookNarrationError.timeout }
            defer { group.cancelAll() }
            guard let message = try await group.next() else { throw CancellationError() }; return message
        }
    }
}

actor EBookNarrationClient {
    private struct Cached: Codable { let created: Date; let key: String; let value: EBookNarrationAudio }
    private let transport: any EBookNarrationTransport
    private let directory: URL
    private var voiceList: [EBookNarrationVoice]?
    private var cacheGeneration = UUID()
    init(owner: String, directory: URL? = nil, transport: any EBookNarrationTransport = EBookEdgeTransport()) throws {
        let root = try directory ?? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Harbor/Narration")
        self.directory = root.appendingPathComponent(EBookShelf.hash(owner), isDirectory: true); self.transport = transport
    }
    func voices() async throws -> [EBookNarrationVoice] {
        if let voiceList { return voiceList }; let values = try await transport.voices(); voiceList = values; return values
    }
    func synthesize(_ text: String, voice: String, locale: String, rate: Int = 0, progress: @escaping @Sendable (EBookNarrationProgress) async -> Void = { _ in }) async throws -> EBookNarrationAudio {
        guard EBookEdgeProtocol.validID(voice), EBookEdgeProtocol.validLocale(locale) else { throw EBookNarrationError.input }
        let chunks = try EBookEdgeProtocol.chunks(text), speed = min(100, max(-50, rate)), generation = cacheGeneration
        let key = EBookShelf.hash(voice + "\n" + locale + "\n" + String(speed) + "\n" + text), file = directory.appendingPathComponent(key + ".json")
        try Task.checkCancellation()
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 192 * 1024 * 1024,
           let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(Cached.self, from: data), cached.key == key,
           Date().timeIntervalSince(cached.created) >= 0, Date().timeIntervalSince(cached.created) < 30 * 24 * 60 * 60, !cached.value.audio.isEmpty {
            await progress(.init(completed: 1, total: 1)); try Task.checkCancellation(); return cached.value
        }
        var audio = Data(), boundaries: [EBookNarrationBoundary] = [], timeline = 0.0
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation(); let value = try await transport.synthesize(chunk, voice: voice, locale: locale, rate: speed)
            try Task.checkCancellation(); guard !value.audio.isEmpty else { throw EBookNarrationError.emptyAudio }
            audio.append(value.audio)
            let valid = value.boundaries.filter { $0.offsetMs.isFinite && $0.durationMs.isFinite && $0.offsetMs >= 0 && $0.durationMs >= 0 }
            boundaries += valid.map { .init(offsetMs: timeline + $0.offsetMs, durationMs: $0.durationMs, text: $0.text) }
            timeline += valid.map { $0.offsetMs + $0.durationMs }.max() ?? 0
            guard audio.count <= 128 * 1024 * 1024 else { throw EBookNarrationError.response }
            await progress(.init(completed: index + 1, total: chunks.count))
        }
        let value = EBookNarrationAudio(audio: audio, boundaries: boundaries)
        try Task.checkCancellation()
        // A full cache or failed cache write must not prevent playback.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        if cacheGeneration == generation, directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL,
           let data = try? JSONEncoder().encode(Cached(created: Date(), key: key, value: value)) {
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return value
    }
    func clearCache() throws {
        cacheGeneration = UUID()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        guard directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL else { throw EBookNarrationError.input }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "json" { try FileManager.default.removeItem(at: file) }
    }
}

struct EBookNarrationWindow: Sendable {
    let start: Int; let end: Int; let text: String; let wordEnds: [Int]; let weights: [Int]
    static func prepare(_ paragraphs: [EBookSearchParagraph], start: Int, step: Int, locale: String) async -> Self? { make(paragraphs, start: start, step: step, locale: locale) }
    static func make(_ paragraphs: [EBookSearchParagraph], start: Int, step: Int, locale: String) -> Self? {
        guard paragraphs.indices.contains(start) else { return nil }; let budgets = [700, 1500, 3000, 4000], budget = budgets[min(max(0, step), 3)]
        var end = start, size = 0, words = 0, wordEnds: [Int] = [], weights: [Int] = []
        while end < paragraphs.count {
            let text = paragraphs[end].text, count = text.utf16.count + 2
            if size > 0, size + count > budget { break }
            size += count; end += 1; weights.append(max(1, text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count))
            let tokenizer = NLTokenizer(unit: .word); tokenizer.string = text; tokenizer.setLanguage(NLLanguage(rawValue: locale.components(separatedBy: "-")[0]))
            var wordCount = 0; tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in wordCount += 1; return true }
            words += max(1, wordCount); wordEnds.append(words)
        }
        return .init(start: start, end: end, text: paragraphs[start..<end].map(\.text).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines), wordEnds: wordEnds, weights: weights)
    }
    func paragraph(position: Double, duration: Double, boundaries: [EBookNarrationBoundary]) -> Int {
        if !boundaries.isEmpty {
            var low = 0, high = boundaries.count
            while low < high { let middle = (low + high) / 2; if boundaries[middle].offsetMs <= position * 1000 { low = middle + 1 } else { high = middle } }
            if let offset = wordEnds.firstIndex(where: { max(0, low - 1) < $0 }) { return start + offset }
        }
        guard duration > 0 else { return start }; let target = min(1, max(0, position / duration)) * Double(weights.reduce(0, +))
        var accumulated = 0
        for (offset, weight) in weights.enumerated() { accumulated += weight; if target <= Double(accumulated) { return start + offset } }
        return max(start, end - 1)
    }
}
