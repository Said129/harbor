import Foundation
import Observation

@MainActor @Observable final class HarborReadingPluginManager {
    struct BulkProgress {
        let repository: String
        let total: Int
        var completed = 0
        var installed = 0
        var failed = 0
    }
    private final class Worker {
        let plugin: HarborInstalledReadingPlugin
        let runtime: HarborPluginRuntime
        var active = 0
        var used = ProcessInfo.processInfo.systemUptime
        init(_ plugin: HarborInstalledReadingPlugin, _ runtime: HarborPluginRuntime) { self.plugin = plugin; self.runtime = runtime }
    }
    let scope: PluginExecutionScope
    let adapter: HarborReadingPluginProgram
    private let currentScope: @MainActor () -> PluginExecutionScope
    private let store: HarborReadingPluginStore
    private let network: any HarborNativeNetworkCalling
    private var workers: [String: Worker] = [:]
    private var starting: [String: (id: UUID, task: Task<HarborPluginRuntime, Error>)] = [:]
    private var mutation: Task<Void, Error>?
    private var pageHeaders: [String: [String: String]] = [:]
    private var headerOrder: [String] = []
    private let imageCache = NSCache<NSString, NSData>()
    private var images: [String: (id: UUID, task: Task<Data, Error>)] = [:]
    private var operations: [UUID: Task<JSONValue, Error>] = [:]
    private var ebookTags: [String: Set<String>] = [:]
    private var ebookTagLoads: [String: Task<Set<String>, Error>] = [:]
    private var disposed = false
    private var metadataClient: EBookMetadataClient?
    private(set) var document = HarborReadingPluginDocument()
    private(set) var ready = false
    private(set) var busy = false
    private(set) var bulkProgress: BulkProgress?
    private(set) var entryFailures: [String: String] = [:]

    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
         store: HarborReadingPluginStore, network: any HarborNativeNetworkCalling = HarborNativeNetwork()) {
        self.scope = scope; self.currentScope = currentScope; self.store = store; self.network = network
        adapter = HarborReadingPluginProgram(scope: scope, currentScope: currentScope)
        imageCache.totalCostLimit = 32 * 1024 * 1024; imageCache.countLimit = 80
    }
    func load() async throws { try validate(); document = try await store.load(); try validate(); ready = true }
    func ebookMetadata() throws -> EBookMetadataClient {
        try validate()
        if let metadataClient { return metadataClient }
        let client = try EBookMetadataClient(scope: scope, currentScope: currentScope, network: network)
        metadataClient = client; return client
    }
    func installed(_ kind: HarborReadingPluginKind, includeAdult: Bool = false) -> [HarborInstalledReadingPlugin] {
        document.plugins.filter { $0.kind == kind && $0.enabled && (includeAdult || !$0.entry.adult) }
    }
    func addRepository(_ raw: String, kind: HarborReadingPluginKind) async throws {
        try await mutate {
            let normalized = try HarborPluginManifest.normalizeURL(raw)
            guard !self.document.repositories.contains(where: { $0.kind == kind && $0.url == normalized }) else { throw HarborPluginRepositoryError("already-added") }
            var result: HarborReadingPluginRepository?, last: Error = HarborPluginRepositoryError("no-answer")
            for candidate in HarborPluginManifest.candidates(normalized) {
                do {
                    let repository = try await self.fetchRepository(candidate, kind: kind)
                    if !repository.entries.isEmpty || repository.foreign != nil { result = repository; break }
                    result = repository
                } catch is CancellationError { throw CancellationError() } catch { last = error }
            }
            guard let result else { throw last }
            guard !self.document.repositories.contains(where: { $0.kind == kind && $0.url == result.url }) else { throw HarborPluginRepositoryError("already-added") }
            var next = self.document; next.repositories.append(result); try await self.save(next)
        }
    }
    func refresh(_ repository: HarborReadingPluginRepository) async throws {
        try await mutate {
            let refreshed = try await self.fetchRepository(repository.url, kind: repository.kind)
            guard let index = self.document.repositories.firstIndex(where: { $0.id == repository.id }) else { throw HarborPluginRepositoryError("not-a-repo") }
            var next = self.document; next.repositories[index] = refreshed; try await self.save(next)
        }
    }
    func removeRepository(_ repository: HarborReadingPluginRepository) async throws {
        try await mutate {
            var next = self.document
            let removed = next.plugins.filter { $0.kind == repository.kind && $0.repository == repository.url }
            let ids = Set(removed.map(\.id))
            next.repositories.removeAll { $0.id == repository.id }; next.plugins.removeAll { ids.contains($0.id) }
            try await self.save(next); removed.forEach { self.invalidate($0.id) }
        }
    }
    func install(_ entry: HarborReadingPluginEntry, repository: HarborReadingPluginRepository) async throws {
        try await mutate { try await self.installEntry(entry, repository: repository) }
    }
    func installAll(_ repository: HarborReadingPluginRepository, updatesOnly: Bool = false) async throws {
        try await mutate {
            guard self.document.repositories.contains(repository) else { throw HarborPluginRepositoryError("not-a-repo") }
            let entries = repository.entries.filter { entry in
                let installed = self.document.plugins.first { $0.kind == repository.kind && $0.repository == repository.url && $0.entry.id == entry.id }
                return updatesOnly ? installed != nil && installed?.entry.version != entry.version : entry.mangayomi || installed == nil
            }
            self.bulkProgress = .init(repository: repository.id, total: entries.count)
            defer { self.bulkProgress = nil }
            var firstFailure: Error?
            for entry in entries {
                try self.validate()
                do { try await self.installEntry(entry, repository: repository); self.bulkProgress?.installed += 1 }
                catch is CancellationError { throw CancellationError() }
                catch {
                    try self.validate()
                    firstFailure = firstFailure ?? error
                    self.entryFailures[repository.id + "|" + entry.id] = HarborPluginMessages.error(error)
                    self.bulkProgress?.failed += 1
                }
                self.bulkProgress?.completed += 1
            }
            if self.bulkProgress?.installed == 0, let firstFailure { throw firstFailure }
        }
    }
    func removeInstalled(in repository: HarborReadingPluginRepository) async throws {
        try await mutate {
            guard self.document.repositories.contains(repository) else { throw HarborPluginRepositoryError("not-a-repo") }
            let removed = self.document.plugins.filter { $0.kind == repository.kind && $0.repository == repository.url }
            var next = self.document; next.plugins.removeAll { $0.kind == repository.kind && $0.repository == repository.url }
            try await self.save(next); removed.forEach { self.invalidate($0.id) }
        }
    }
    func cancelBulk() { if bulkProgress != nil { mutation?.cancel() } }
    private func installEntry(_ entry: HarborReadingPluginEntry, repository: HarborReadingPluginRepository) async throws {
        guard document.repositories.contains(where: { $0.id == repository.id && $0.entries.contains(entry) }),
              let url = URL(string: entry.location, relativeTo: URL(string: repository.url))?.absoluteURL else { throw HarborPluginRepositoryError("not-a-repo") }
        let payload = try await fetch(url.absoluteString)
        var source = String(decoding: payload, as: UTF8.self)
        if source.hasPrefix("\u{feff}") { source.removeFirst() }
        guard source.utf16.count <= 2 * 1024 * 1024 else { throw HarborPluginRepositoryError("too-large") }
        var plugin = HarborInstalledReadingPlugin(kind: repository.kind, entry: entry, repository: repository.url,
            repositoryName: repository.name, source: source, hash: HarborReadingPluginStore.digest(source))
        let runtime = try await makeWorker(plugin)
        defer { runtime.dispose() }
        // Desktop retains a downloaded reading source if its optional metadata probe fails.
        do { let meta = try await runtime.metadata(); plugin.hasTags = meta["hasTags"] == .bool(true) }
        catch is CancellationError { throw CancellationError() } catch { plugin.hasTags = false }
        try validate()
        var next = document; next.plugins.removeAll { $0.id == plugin.id }; next.plugins.append(plugin)
        try await save(next); invalidate(plugin.id); entryFailures[repository.id + "|" + entry.id] = nil
    }
    func remove(_ plugin: HarborInstalledReadingPlugin) async throws {
        try await mutate {
            var next = self.document; next.plugins.removeAll { $0.id == plugin.id }
            if plugin.manualHTML, let index = next.repositories.firstIndex(where: { $0.kind == plugin.kind && $0.url == plugin.repository }) {
                next.repositories[index].entries.removeAll { $0.id == plugin.entry.id }
                if next.repositories[index].entries.isEmpty { next.repositories.remove(at: index) }
            }
            try await self.save(next); self.invalidate(plugin.id)
        }
    }
    func saveHTML(kind: HarborReadingPluginKind, raw: String, name: String = "", logo: String = "", language: String = "all", replacing previous: HarborInstalledReadingPlugin? = nil) async throws {
        try await mutate {
            guard raw.utf8.count <= 256 * 1024 else { throw HarborPluginRepositoryError("too-large") }
            if let previous {
                guard previous.kind == kind, previous.manualHTML, self.document.plugins.contains(previous) else { throw HarborPluginRepositoryError("plugin-store-conflict") }
            }
            var object = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)).objectValue
            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { object["name"] = .string(name.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if !logo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { object["iconUrl"] = .string(logo.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let text = String(decoding: try JSONEncoder().encode(JSONValue.object(object)), as: UTF8.self)
            let input: JSONValue = .object(["kind": .string(kind.rawValue), "raw": .string(text), "resolveIcon": .bool(kind == .manga && logo.isEmpty)])
            let encoded = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
            let probe = HarborPluginRuntime(id: "manual-html-validation", name: "Harbor", source: encoded, format: .trustedHTML,
                scope: self.scope, currentScope: self.currentScope, transport: HarborNativePluginTransport(policy: .reading(baseURL: nil, blockedHosts: []), network: self.network))
            defer { probe.dispose() }
            let meta = try await probe.metadata()
            try self.validate()
            guard let id = meta["id"].string, let title = meta["name"].string, let base = meta["config"]["baseUrl"].string else { throw HarborPluginRepositoryError("reading-html-config") }
            guard !self.document.plugins.contains(where: { $0.kind == kind && $0.entry.id == id && !$0.manualHTML }) else { throw HarborPluginRepositoryError("already-added") }
            let config = meta["config"]
            let normalized = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
            let source = String(decoding: try JSONEncoder().encode(["kind": kind.rawValue, "raw": normalized]), as: UTF8.self)
            let repositoryURL = "harbor://manual-html/" + kind.rawValue
            var fields: [String: JSONValue] = ["id": .string(id), "name": .string(title), "format": .string("manual-html"), "lang": .string(language), "baseUrl": .string(base), "htmlConfig": config]
            if let icon = meta["icon"].string { fields["icon"] = .string(icon) }
            let entry = HarborReadingPluginEntry(raw: .object(fields))
            var next = self.document
            next.plugins.removeAll { ($0.kind == kind && $0.entry.id == id) || $0.id == previous?.id }
            var plugin = HarborInstalledReadingPlugin(kind: kind, entry: entry, repository: repositoryURL, repositoryName: "Manual sources", source: source, hash: HarborReadingPluginStore.digest(source))
            plugin.enabled = previous?.enabled ?? true
            next.plugins.append(plugin)
            if let index = next.repositories.firstIndex(where: { $0.kind == kind && $0.url == repositoryURL }) {
                next.repositories[index].entries.removeAll { $0.id == id || $0.id == previous?.entry.id }
                next.repositories[index].entries.append(entry)
            } else {
                next.repositories.append(.init(kind: kind, url: repositoryURL, name: "Manual sources", entries: [entry], foreign: "manual-html", checkedAt: Date()))
            }
            try await self.save(next)
            if let previous { self.invalidate(previous.id) }; self.invalidate(plugin.id)
        }
    }
    func setEnabled(_ plugin: HarborInstalledReadingPlugin, _ enabled: Bool) async throws {
        try await mutate {
            guard let index = self.document.plugins.firstIndex(where: { $0.id == plugin.id }) else { throw HarborPluginRepositoryError("plugin-not-installed") }
            var next = self.document; next.plugins[index].enabled = enabled
            try await self.save(next); self.invalidate(plugin.id)
        }
    }
    func call(_ plugin: HarborInstalledReadingPlugin, _ method: String, arguments: [JSONValue], timeout: TimeInterval) async throws -> JSONValue {
        try validate()
        guard ready, plugin.enabled, document.plugins.contains(plugin) else { throw HarborPluginRepositoryError("plugin-unavailable") }
        let id = UUID()
        let task = Task {
            try await HarborPluginCallGate.shared.acquire(); defer { HarborPluginCallGate.shared.release() }
            try self.validate()
            let worker = try await self.workerFor(plugin)
            worker.active += 1
            defer { worker.active -= 1; worker.used = ProcessInfo.processInfo.systemUptime; self.trim() }
            let value: JSONValue
            do { value = try await worker.runtime.call(method, arguments: arguments, timeout: timeout) }
            catch { try self.validate(); guard self.document.plugins.contains(plugin) else { throw CancellationError() }; throw error }
            try self.validate()
            guard self.document.plugins.contains(plugin) else { throw CancellationError() }
            return value
        }
        operations[id] = task; defer { operations[id] = nil }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    func dispose() {
        guard !disposed else { return }; disposed = true; ready = false
        metadataClient?.dispose(); metadataClient = nil
        mutation?.cancel(); mutation = nil
        bulkProgress = nil; entryFailures = [:]
        images.values.forEach { $0.task.cancel() }; images = [:]; imageCache.removeAllObjects()
        operations.values.forEach { $0.cancel() }; operations = [:]
        ebookTagLoads.values.forEach { $0.cancel() }; ebookTagLoads = [:]; ebookTags = [:]
        starting.values.forEach { $0.task.cancel() }; starting = [:]
        workers.values.forEach { $0.runtime.dispose() }; workers = [:]; pageHeaders = [:]; headerOrder = []; adapter.dispose(); document = .init()
    }
    private func invalidate(_ id: String, discardTags: Bool = true) {
        starting.removeValue(forKey: id)?.task.cancel(); workers.removeValue(forKey: id)?.runtime.dispose()
        if discardTags { ebookTagLoads.removeValue(forKey: id)?.cancel(); ebookTags[id] = nil }
    }
    private func workerFor(_ plugin: HarborInstalledReadingPlugin) async throws -> Worker {
        if let old = workers[plugin.id], old.plugin == plugin, !old.runtime.isDisposed { return old }
        let ticket: UUID, task: Task<HarborPluginRuntime, Error>
        if let pending = starting[plugin.id] { ticket = pending.id; task = pending.task }
        else {
            invalidate(plugin.id, discardTags: false); ticket = UUID()
            task = Task {
                let runtime = try await self.makeWorker(plugin)
                do {
                    try self.validate()
                    guard self.document.plugins.contains(plugin), self.starting[plugin.id]?.id == ticket else { throw CancellationError() }
                    return runtime
                } catch { runtime.dispose(); throw error }
            }
            starting[plugin.id] = (ticket, task)
        }
        defer { if starting[plugin.id]?.id == ticket { starting[plugin.id] = nil } }
        let runtime = try await task.value; try validate()
        guard document.plugins.contains(plugin) else { runtime.dispose(); throw CancellationError() }
        if let old = workers[plugin.id], old.runtime === runtime { return old }
        let worker = Worker(plugin, runtime); workers[plugin.id] = worker; return worker
    }
    private func trim() {
        let idle = workers.values.filter { $0.active == 0 }.sorted { $0.used < $1.used }
        for worker in idle.prefix(max(0, idle.count - 4)) { invalidate(worker.plugin.id, discardTags: false) }
    }
    private func makeWorker(_ plugin: HarborInstalledReadingPlugin) async throws -> HarborPluginRuntime {
        var source = plugin.source
        if plugin.entry.mangayomi {
            let entry = plugin.entry
            var record: [String: JSONValue] = [
                "id": .string(entry.id), "name": .string(entry.name), "lang": .string(entry.language), "baseUrl": .string(entry.baseURL ?? ""),
                "apiUrl": .string(entry.raw["apiUrl"].string ?? ""), "version": .string(entry.version), "isNsfw": .bool(entry.adult), "source": .string(source)]
            if let icon = entry.icon { record["iconUrl"] = .string(icon) }
            source = try await adapter.apply("mangayomi-source", raw: .object(record)).string ?? ""
        }
        try validate()
        return HarborPluginRuntime(id: plugin.id, name: plugin.entry.name, source: source, format: plugin.manualHTML ? .trustedHTML : .raw, configuration: plugin.configuration,
            scope: scope, currentScope: currentScope, transport: HarborNativePluginTransport(policy: .reading(baseURL: plugin.entry.baseURL, blockedHosts: []), network: network))
    }
    private func fetchRepository(_ url: String, kind: HarborReadingPluginKind) async throws -> HarborReadingPluginRepository {
        let raw = try JSONDecoder().decode(JSONValue.self, from: await fetch(url))
        let value = try await adapter.apply("repository", raw: raw, extra: ["kind": .string(kind.rawValue), "url": .string(url)])
        try validate()
        return .init(kind: kind, url: url, name: value["name"].string ?? "Repository", entries: value["entries"].array.map { .init(raw: $0) },
            foreign: value["foreign"]["kind"].string, checkedAt: Date())
    }
    private func fetch(_ url: String) async throws -> Data {
        try validate()
        var request = HarborNetworkRequest(url: url); request.timeoutMs = 20_000; request.maxResponseBytes = 2 * 1024 * 1024; request.strictLimit = true
        let response = try await network.perform(request); try validate()
        guard response.ok else { throw HarborPluginRepositoryError("no-answer") }
        return try response.bytes()
    }
    private func validate() throws {
        try Task.checkCancellation()
        guard !disposed, scope == currentScope() else { throw CancellationError() }
    }
    private func save(_ next: HarborReadingPluginDocument) async throws {
        try validate(); let saved = try await store.commit(next, expected: document.revision); try validate(); document = saved
    }
    private func mutate(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        try validate(); guard ready, !busy else { throw HarborPluginRepositoryError("plugin-busy") }
        busy = true; defer { busy = false; mutation = nil }
        let task = Task { try self.validate(); try await operation(); try self.validate() }; mutation = task
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func image(_ path: String, pluginID: String) async throws -> Data {
        try validate()
        guard let plugin = document.plugins.first(where: { $0.id == pluginID }), plugin.enabled else { throw HarborPluginRepositoryError("plugin-unavailable") }
        let headers = pageHeaders[pluginID + "|" + path] ?? (plugin.manualHTML ? plugin.entry.raw["htmlConfig"]["headers"].objectValue.compactMapValues(\.string) : [:])
        let headerKey = headers.keys.sorted().map { $0 + ":" + (headers[$0] ?? "") }.joined(separator: "\n")
        let key = pluginID + "|" + plugin.hash + "|" + path + "|" + headerKey
        if let cached = imageCache.object(forKey: key as NSString) { return cached as Data }
        let ticket: UUID, task: Task<Data, Error>
        if let pending = images[key] { ticket = pending.id; task = pending.task }
        else {
            ticket = UUID()
            task = Task {
                let transport = HarborNativePluginTransport(policy: .reading(baseURL: plugin.entry.baseURL, blockedHosts: []), network: self.network)
                let result = try await transport.perform(.http, payload: .object(["url": .string(path), "opts": .object([
                    "responseType": .string("base64"), "headers": .object(headers.mapValues(JSONValue.string))])]))
                try self.validate()
                guard self.document.plugins.contains(plugin), result["ok"] == .bool(true), let encoded = result["body"].string,
                      let data = Data(base64Encoded: encoded) else { throw HarborPluginRuntimeError("plugin-image") }
                return data
            }
            images[key] = (ticket, task)
        }
        defer { if images[key]?.id == ticket { images[key] = nil } }
        let data = try await task.value; try validate()
        guard document.plugins.contains(plugin) else { throw CancellationError() }
        imageCache.setObject(data as NSData, forKey: key as NSString, cost: data.count); return data
    }
    func mangaBrowse(_ plugin: HarborInstalledReadingPlugin, query: String, offset: Int, tag: String? = nil) async throws -> [MangaBook] {
        let popular = query.isEmpty && tag == nil
        let args: [JSONValue] = popular ? [.integer(Int64(max(0, offset))), .null]
            : [.string(query), .integer(Int64(max(0, offset))), tag.map(JSONValue.string) ?? .null]
        let raw = try await call(plugin, popular ? "popular" : "search", arguments: args, timeout: 20)
        let values = try await adapter.apply("manga-books", raw: raw)
        return values.array.compactMap { mangaBook($0, plugin: plugin) }
    }
    func mangaDetail(_ book: MangaBook) async throws -> MangaBook {
        let plugin = try readingPlugin(book.pluginID, kind: .manga)
        guard let remote = book.remoteID else { throw HarborPluginRuntimeError("plugin-item") }
        let raw = try await call(plugin, "detail", arguments: [.string(remote)], timeout: 20)
        let value = try await adapter.apply("manga-detail", raw: raw)
        return mangaBook(value, plugin: plugin) ?? book
    }
    private func mangaBook(_ raw: JSONValue, plugin: HarborInstalledReadingPlugin) -> MangaBook? {
        guard let remote = raw["id"].string, let title = raw["title"].string else { return nil }
        return .init(id: plugin.entry.id + "::" + remote, title: title, author: raw["author"].string ?? "",
            description: raw["description"].string ?? "", cover: raw["cover"].string, remoteID: remote, sourceID: plugin.entry.id,
            pluginID: plugin.id, metadata: raw)
    }
    func mangaChapters(_ book: MangaBook) async throws -> [MangaChapter] {
        let plugin = try readingPlugin(book.pluginID, kind: .manga)
        guard let remote = book.remoteID else { throw HarborPluginRuntimeError("plugin-item") }
        let raw = try await call(plugin, "chapters", arguments: [.string(remote)], timeout: 25)
        let values = try await adapter.apply("manga-chapters", raw: raw)
        return values.array.compactMap { value in
            guard let id = value["id"].string else { return nil }
            return MangaChapter(id: plugin.entry.id + "::" + id, title: value["title"].string ?? value["chapter"].string ?? id,
                number: Double(value["chapter"].string ?? "") ?? 0, pages: value["pages"].integer ?? 0)
        }
    }
    func mangaPages(_ book: MangaBook, chapter: MangaChapter) async throws -> [MangaPage] {
        let plugin = try readingPlugin(book.pluginID, kind: .manga)
        let prefix = plugin.entry.id + "::"
        let remote = chapter.id.hasPrefix(prefix) ? String(chapter.id.dropFirst(prefix.count)) : chapter.id
        let raw = try await call(plugin, "pageUrls", arguments: [.string(remote)], timeout: 30)
        let values = try await adapter.apply("manga-pages", raw: raw, extra: ["baseUrl": .string(plugin.entry.baseURL ?? "")])
        var pages: [MangaPage] = []
        for value in values.array {
            guard let url = value["url"].string else { continue }
            let key = plugin.id + "|" + url
            let headers = value["headers"].objectValue.compactMapValues(\.string)
            if headers.isEmpty {
                if pageHeaders.removeValue(forKey: key) != nil { headerOrder.removeAll { $0 == key } }
            }
            else {
                if pageHeaders[key] == nil {
                    if headerOrder.count >= 6000 { pageHeaders[headerOrder.removeFirst()] = nil }
                    headerOrder.append(key)
                }
                pageHeaders[key] = headers
            }
            pages.append(.init(id: pages.count, path: url))
        }
        return pages
    }
    func tags(_ plugin: HarborInstalledReadingPlugin) async throws -> JSONValue {
        guard plugin.hasTags else { return .array([]) }
        let raw = try await call(plugin, "tags", arguments: [], timeout: 15)
        return try await adapter.apply("manga-tags", raw: raw)
    }
    private func ebookSupportedTag(_ tag: String?, plugin: HarborInstalledReadingPlugin) async throws -> JSONValue {
        guard let tag, plugin.hasTags else { return .null }
        if let known = ebookTags[plugin.id] { return known.contains(tag) ? .string(tag) : .null }
        let task: Task<Set<String>, Error>
        if let pending = ebookTagLoads[plugin.id] { task = pending }
        else {
            task = Task {
                do {
                    let raw = try await self.call(plugin, "tags", arguments: [], timeout: 25)
                    return Set(raw.array.compactMap { $0["id"].string }.filter { !$0.isEmpty })
                } catch is CancellationError { throw CancellationError() }
                catch { return [] }
            }
            ebookTagLoads[plugin.id] = task
        }
        let supported = try await task.value
        try validate(); try Task.checkCancellation()
        guard document.plugins.contains(plugin) else { throw CancellationError() }
        ebookTags[plugin.id] = supported; ebookTagLoads[plugin.id] = nil
        return supported.contains(tag) ? .string(tag) : .null
    }
    func ebookBrowse(_ plugin: HarborInstalledReadingPlugin, query: String, offset: Int, tag: String? = nil) async throws -> [EBook] {
        let supported = try await ebookSupportedTag(tag, plugin: plugin)
        let args: [JSONValue] = query.isEmpty ? [.integer(Int64(max(0, offset))), supported] : [.string(query), .integer(Int64(max(0, offset))), supported]
        let raw = try await call(plugin, query.isEmpty ? "popular" : "search", arguments: args, timeout: 25)
        return try await ebookValues(raw, plugin: plugin)
    }
    func ebookDetail(_ book: EBook) async throws -> EBook {
        let plugin = try readingPlugin(book.pluginID, kind: .ebook)
        guard let item = book.itemID else { throw HarborPluginRuntimeError("plugin-item") }
        let raw = try await call(plugin, "detail", arguments: [.string(item)], timeout: 25)
        guard let detail = try await ebookValues(.array([raw]), plugin: plugin).first else { throw HarborPluginRuntimeError("plugin-item") }
        return detail
    }
    private func ebookValues(_ raw: JSONValue, plugin: HarborInstalledReadingPlugin) async throws -> [EBook] {
        let values: JSONValue
        if plugin.manualHTML { values = raw }
        else { values = try await adapter.apply("ebook-books", raw: raw, extra: ["provider": .object(["id": .string("plugin:" + plugin.entry.id), "name": .string(plugin.entry.name)])]) }
        let declared = plugin.entry.language.lowercased()
        return values.array.compactMap { value in
            guard let id = value["id"].string, let title = value["title"].string, let item = value["sourceItemId"].string else { return nil }
            return .init(id: id, title: title, authors: value["authors"].array.compactMap(\.string), description: value["description"].string ?? "",
                cover: value["cover"].string, language: ["", "all", "multi"].contains(declared) ? value["originalLanguage"].string : plugin.entry.language, source: plugin.entry.name,
                pluginID: plugin.id, itemID: item, metadata: value)
        }
    }
    func ebookPublication(_ book: EBook) async throws -> EBookPublication {
        let plugin = try readingPlugin(book.pluginID, kind: .ebook)
        guard let remote = book.itemID else { throw HarborPluginRuntimeError("plugin-item") }
        let raw = try await call(plugin, "chapters", arguments: [.string(remote)], timeout: 25)
        let values = try await adapter.apply("ebook-chapters", raw: raw)
        let chapters: [EBookChapter] = values.array.compactMap { value in
            guard let id = value["id"].string else { return nil }
            let title = value["title"].string ?? id, volume = value["volumeTitle"].string ?? value["volume"].string
            return .init(path: id, title: volume.map { $0 + " · " + title } ?? title)
        }
        guard !chapters.isEmpty else { throw HarborPluginRuntimeError("plugin-no-chapters") }
        return .init(title: book.title, authors: book.authors, language: book.language ?? plugin.entry.language, chapters: chapters)
    }
    func ebookBlocks(_ book: EBook, chapter: EBookChapter) async throws -> [EBookBlock] {
        let plugin = try readingPlugin(book.pluginID, kind: .ebook)
        let raw: JSONValue
        do { raw = try await call(plugin, "content", arguments: [.string(chapter.path)], timeout: 30) }
        catch let error as HarborPluginRuntimeError where error.code == "plugin-call" && error.detail.contains("no method: content") {
            raw = .object(["images": try await call(plugin, "pageUrls", arguments: [.string(chapter.path)], timeout: 30)])
        }
        let value = try await adapter.apply("ebook-content", raw: raw)
        let text = (value["text"].string ?? "").replacingOccurrences(of: "\r", with: "")
        var blocks = text.components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.enumerated().map { EBookBlock(id: $0.offset, text: $0.element) }
        for image in value["images"].array.compactMap(\.string) { blocks.append(.init(id: blocks.count, text: book.title, imageURL: image)) }
        return blocks
    }
    private func readingPlugin(_ id: String?, kind: HarborReadingPluginKind) throws -> HarborInstalledReadingPlugin {
        try validate()
        guard let plugin = document.plugins.first(where: { $0.id == id && $0.kind == kind && $0.enabled }) else { throw HarborPluginRepositoryError("plugin-unavailable") }
        return plugin
    }
}
