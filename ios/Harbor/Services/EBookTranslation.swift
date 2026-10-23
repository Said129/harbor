import Foundation
import JavaScriptCore

struct EBookTranslationSettings: Codable, Equatable, Sendable {
    var enabled = false
    var apiKey = ""
    var model = "deepseek-v4-flash"
    var targetLanguage = InterfaceLanguage.resolve(UserDefaults.standard.string(forKey: "uiLanguage") ?? "es")
    var automatic: Bool { enabled && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    static func key(_ owner: String) -> String { "ebook-translation-settings-" + EBookShelf.hash(owner) }
    static func load(owner: String) throws -> Self {
        var settings = try KeychainStore().read(key(owner), as: Self.self) ?? Self()
        if !InterfaceLanguage.all.contains(where: { $0.code == settings.targetLanguage }) { settings.targetLanguage = Self().targetLanguage }
        return settings
    }
    func save(owner: String) throws {
        guard apiKey.utf8.count <= 8192, apiKey.rangeOfCharacter(from: .controlCharacters) == nil,
              model.utf8.count <= 256, model.rangeOfCharacter(from: .controlCharacters) == nil,
              InterfaceLanguage.all.contains(where: { $0.code == targetLanguage }) else { throw EBookTranslationError.settings }
        var next = self; next.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try KeychainStore().write(next, key: Self.key(owner))
    }
    var raw: JSONValue { .object(["model": .string(model), "targetLanguage": .string(targetLanguage)]) }
}

struct EBookTranslation: Codable, Equatable, Sendable { let title: String; let text: String }
struct EBookTranslationProgress: Codable, Sendable { let percent: Int; let etaMs: Double? }
enum EBookTranslatedChapter {
    static func blocks(_ text: String, original: [EBookBlock]) -> [EBookBlock] {
        let paragraphs = EBookPrintRules.paragraphs(text), maximum = original.map(\.id).max() ?? 0
        var index = 0, result: [EBookBlock] = []
        for block in original {
            if block.image != nil || block.imageURL != nil { result.append(block) }
            else if paragraphs.indices.contains(index) {
                result.append(.init(id: block.id, text: paragraphs[index], heading: block.heading)); index += 1
            }
        }
        while paragraphs.indices.contains(index) {
            result.append(.init(id: maximum + index + 1, text: paragraphs[index])); index += 1
        }
        return result
    }
}
enum EBookTranslationError: Error, LocalizedError, Sendable {
    case settings, missingKey, response, truncated, http(Int)
    var errorDescription: String? {
        switch self {
        case .settings: DesktopInterfaceText.value("Translation failed")
        case .missingKey: DesktopInterfaceText.value("Add a DeepSeek API key in eBook Sources first")
        case .response: DesktopInterfaceText.value("Translation failed")
        case .truncated: DesktopInterfaceText.value("DeepSeek translation was truncated")
        case .http(let status): "DeepSeek HTTP \(status)"
        }
    }
}

/// Pinned Desktop request, stream validation and cache identity; no script bridges.
actor EBookTranslationProgram {
    private struct Asset: Decodable {
        struct Program: Decodable { let source: String; let sha256: String }
        let schema: Int; let reference: String; let inputs: [String: String]; let program: Program
    }
    private var context: JSContext?
    func apply(_ input: JSONValue) throws -> JSONValue {
        try Task.checkCancellation()
        if context == nil {
            guard let url = Bundle.main.url(forResource: "EBookTranslationAssets", withExtension: "json") else { throw EBookTranslationError.response }
            let asset = try JSONDecoder().decode(Asset.self, from: Data(contentsOf: url))
            guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987",
                  asset.inputs == ["src/lib/ebook/translation.ts": "de025486a30e1c271e8420555fa00264f460ce556769769b7b73d0c2a66aae69", "src/lib/ebook/translation-instructions.md": "bccfc4fe67d509f09d292d6c145da0bcbbd366030b1b981822f261c6380d62ba", "src/lib/i18n/languages.ts": "feeab8008569c3108c45b91dedb7c471d34426687ac9e6a800eae4947baa4f68"],
                  EBookShelf.hash(Data(asset.program.source.utf8)) == asset.program.sha256,
                  asset.program.sha256 == "22eaade87e991fa2766eb2d329d5390f10e385a88d157b660b3ef4e2e57ca0b9", let engine = JSContext() else { throw EBookTranslationError.response }
            engine.evaluateScript(asset.program.source)
            guard engine.exception == nil else { throw EBookTranslationError.response }; context = engine
        }
        guard let context else { throw EBookTranslationError.response }
        let data = try JSONEncoder().encode(input)
        guard data.count <= 24 * 1024 * 1024 else { throw EBookTranslationError.response }
        context.exception = nil
        let value = context.objectForKeyedSubscript("harborEBookTranslation")?.call(withArguments: [String(decoding: data, as: UTF8.self)])
        if let exception = context.exception {
            let truncated = exception.toString()?.contains("translation was truncated") == true
            context.exception = nil; throw truncated ? EBookTranslationError.truncated : EBookTranslationError.response
        }
        guard let text = value?.toString(), let result = text.data(using: .utf8) else { throw EBookTranslationError.response }
        try Task.checkCancellation(); return try JSONDecoder().decode(JSONValue.self, from: result)
    }
}

protocol EBookTranslationNetworking: Sendable {
    func stream(_ request: URLRequest, receive: @escaping @Sendable (String) async throws -> Void) async throws
}
private final class TranslationRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct EBookTranslationNetwork: EBookTranslationNetworking {
    func stream(_ request: URLRequest, receive: @escaping @Sendable (String) async throws -> Void) async throws {
        guard request.url?.absoluteString == "https://api.deepseek.com/chat/completions" else { throw EBookTranslationError.response }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: TranslationRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw EBookTranslationError.response }
            guard (200..<300).contains(http.statusCode) else { throw EBookTranslationError.http(http.statusCode) }
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.utf8.count <= 16 * 1024 * 1024 else { throw EBookTranslationError.response }
                try await receive(line)
            }
        } onCancel: { session.invalidateAndCancel() }
    }
}

actor EBookTranslationCache {
    private struct Document: Codable { var schema = 1; let owner: String; let slot: String; let value: EBookTranslation }
    private let owner: String
    private let directory: URL
    init(owner: String, directory: URL? = nil) throws {
        self.owner = EBookShelf.hash(owner)
        let root = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Harbor/Books/Translations")
        self.directory = root.appendingPathComponent(self.owner, isDirectory: true)
    }
    private func file(_ slot: String) -> URL { directory.appendingPathComponent(EBookShelf.hash(slot) + ".json") }
    func load(_ slot: String) throws -> EBookTranslation? {
        try Task.checkCancellation()
        let url = file(slot)
        guard FileManager.default.fileExists(atPath: url.path),
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 32 * 1024 * 1024 else { return nil }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard document.schema == 1, document.owner == owner, document.slot == slot, !document.value.text.isEmpty else { return nil }
        return document.value
    }
    func save(_ value: EBookTranslation, slot: String) throws {
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(Document(owner: owner, slot: slot, value: value))
        guard data.count <= 32 * 1024 * 1024 else { throw EBookTranslationError.response }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let url = file(slot)
        guard directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL,
              url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else { throw EBookTranslationError.response }
        try Task.checkCancellation(); try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

actor EBookTranslationClient {
    private struct Prepared: Decodable { let slot: String; let body: JSONValue }
    private struct Pending { let id: UUID; let task: Task<EBookTranslation, Error> }
    private let network: any EBookTranslationNetworking
    private let cache: EBookTranslationCache
    private var pending: [String: Pending] = [:]
    init(owner: String, network: any EBookTranslationNetworking = EBookTranslationNetwork(), cache: EBookTranslationCache? = nil) throws {
        self.network = network; self.cache = try cache ?? EBookTranslationCache(owner: owner)
    }
    func translate(source: String, title: String, settings: EBookTranslationSettings, manual: Bool = false, cacheResult: Bool = true,
                   progress: @escaping @MainActor @Sendable (EBookTranslationProgress) -> Void = { _ in }) async throws -> EBookTranslation {
        try Task.checkCancellation()
        let original = EBookTranslation(title: title, text: source)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return original }
        guard source.utf8.count <= 8 * 1024 * 1024 else { throw EBookTranslationError.response }
        let program = EBookTranslationProgram()
        let input: JSONValue = .object(["operation": .string("prepare"), "source": .string(source), "title": .string(title), "settings": settings.raw])
        let prepared = try JSONDecoder().decode(Prepared.self, from: JSONEncoder().encode(try await program.apply(input)))
        if cacheResult, let saved = try? await cache.load(prepared.slot) { await progress(.init(percent: 100, etaMs: 0)); return saved }
        if !settings.enabled && !manual { return original }
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { if manual { throw EBookTranslationError.missingKey }; return original }
        guard key.utf8.count <= 8192, key.rangeOfCharacter(from: .controlCharacters) == nil else { throw EBookTranslationError.settings }
        if let found = pending[prepared.slot] { return try await result(found.task, progress: progress) }
        let id = UUID(), network = network, cache = cache
        let task = Task<EBookTranslation, Error> {
            await progress(.init(percent: 0, etaMs: nil))
            _ = try await program.apply(.object(["operation": .string("start"), "source": .string(source), "title": .string(title)]))
            var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 300)
            request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(prepared.body)
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            try await network.stream(request) { line in
                let value = try await program.apply(.object(["operation": .string("feed"), "line": .string(line), "now": .number(ProcessInfo.processInfo.systemUptime * 1000)]))
                if value != .null { await progress(try JSONDecoder().decode(EBookTranslationProgress.self, from: JSONEncoder().encode(value))) }
            }
            let value = try await program.apply(.object(["operation": .string("finish")]))
            let translation = try JSONDecoder().decode(EBookTranslation.self, from: JSONEncoder().encode(value))
            try Task.checkCancellation()
            if cacheResult { try? await cache.save(translation, slot: prepared.slot) }
            return translation
        }
        pending[prepared.slot] = .init(id: id, task: task)
        defer { if pending[prepared.slot]?.id == id { pending[prepared.slot] = nil } }
        return try await result(task, progress: progress)
    }
    private func result(_ task: Task<EBookTranslation, Error>, progress: @escaping @MainActor @Sendable (EBookTranslationProgress) -> Void) async throws -> EBookTranslation {
        let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation(); await progress(.init(percent: 100, etaMs: 0)); return value
    }
}
