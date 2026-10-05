import Foundation
import Observation
import CryptoKit

enum DownloadStatus: String, Codable, Sendable {
    case downloading, paused, complete, failed
    var title: String {
        switch self {
        case .downloading: "Descargando"
        case .paused: "En pausa"
        case .complete: "Guardado"
        case .failed: "Interrumpido"
        }
    }
}

struct DownloadItem: Identifiable, Codable, Sendable {
    let id: UUID
    let owner: String
    let media: Media
    let target: ResumeTarget
    let title: String
    let fileExtension: String
    let started: Date
    var status: DownloadStatus
    var received: Int64 = 0
    var expected: Int64 = 0
    var message: String?
    var fraction: Double? { expected > 0 ? min(1, max(0, Double(received) / Double(expected))) : nil }
}

@MainActor @Observable
final class DownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    nonisolated static let sessionIdentifier = "site.harbor.iphone.downloads"
    private(set) var items: [DownloadItem] = []
    var error: String?
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var tasks: [UUID: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private var foregroundSession: URLSession!
    @ObservationIgnored private var lastWrite: [UUID: Date] = [:]
    @ObservationIgnored private var completion: (() -> Void)?

    override private init() {
        super.init()
        do {
            let file = try Self.root().appendingPathComponent("index.json")
            if FileManager.default.fileExists(atPath: file.path) {
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8 * 1024 * 1024 else { throw HarborError(code: "download-index") }
                let data = try Data(contentsOf: file)
                guard data.count <= 8 * 1024 * 1024 else { throw HarborError(code: "download-index") }
                items = try JSONDecoder().decode([DownloadItem].self, from: data)
            }
            ready = true
        } catch { self.error = "No se pudo leer la lista de descargas. Los archivos se conservan." }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 3
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        // Background sessions follow redirects without calling the redirect
        // delegate. Credentialed requests use an ephemeral foreground session
        // so private addon headers cannot be forwarded to a different host.
        let foreground = URLSessionConfiguration.ephemeral
        foreground.httpShouldSetCookies = false; foreground.httpCookieStorage = nil
        foregroundSession = URLSession(configuration: foreground, delegate: self, delegateQueue: queue)
        session.getAllTasks { [weak self] active in
            Task { @MainActor in
                guard let self, self.ready else { return }
                for task in active {
                    guard let task = task as? URLSessionDownloadTask, let raw = task.taskDescription, let id = UUID(uuidString: raw), self.items.contains(where: { $0.id == id }) else { continue }
                    self.tasks[id] = task
                }
                for item in self.items where item.status == .downloading || item.status == .paused {
                    if let final = try? self.file(item), FileManager.default.fileExists(atPath: final.path) { self.update(item.id) { $0.status = .complete } }
                    else if let staging = try? Self.staging(item.id), FileManager.default.fileExists(atPath: staging.path) { self.finished(item.id) }
                    else if self.tasks[item.id] == nil { self.update(item.id) { $0.status = .failed; $0.message = "La descarga se interrumpió. Vuelve a elegir una fuente." } }
                }
            }
        }
    }

    func list(owner: String) -> [DownloadItem] { items.filter { $0.owner == Self.ownerHash(owner) }.sorted { $0.started > $1.started } }

    func start(source: PlaybackSource, media: Media, episode: Episode?, owner: String, cellular: Bool) throws {
        guard ready else { throw HarborError(code: "download-index") }
        guard let url = URL(string: source.url), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !["m3u8", "mpd"].contains(url.pathExtension.lowercased()) else { throw HarborError(code: "download-source") }
        let extensions = ["mp4", "mkv", "m4v", "mov", "webm", "mp3", "m4a", "flac", "aac", "ogg", "wav"]
        let suffix = extensions.contains(url.pathExtension.lowercased()) ? url.pathExtension.lowercased() : "media"
        let target = ResumeTarget(id: media.id, season: episode?.season, episode: episode?.episode, videoId: episode?.id)
        guard !items.contains(where: { $0.owner == Self.ownerHash(owner) && $0.media.id == media.id && $0.target.videoId == target.videoId && ($0.status == .downloading || $0.status == .paused) }) else { throw HarborError(code: "download-active") }
        let title = episode.map { "\(media.name) · T\($0.season ?? 0) E\($0.episode ?? 0)" } ?? media.name
        let item = DownloadItem(id: UUID(), owner: Self.ownerHash(owner), media: media, target: target, title: title, fileExtension: suffix, started: Date(), status: .downloading)
        var request = URLRequest(url: url); request.allHTTPHeaderFields = source.headers
        request.allowsCellularAccess = cellular
        try commit(items + [item])
        let transport = source.headers?.isEmpty == false ? foregroundSession : session
        let task = transport!.downloadTask(with: request)
        task.taskDescription = item.id.uuidString; tasks[item.id] = task; task.resume()
    }

    func toggle(_ item: DownloadItem) {
        guard let task = tasks[item.id] else { return }
        if item.status == .paused { task.resume(); update(item.id) { $0.status = .downloading } }
        else if item.status == .downloading { task.suspend(); update(item.id) { $0.status = .paused } }
    }

    func remove(_ item: DownloadItem) {
        guard ready else { return }
        do {
            try commit(items.filter { $0.id != item.id })
            tasks.removeValue(forKey: item.id)?.cancel()
            let candidates = [try file(item), try Self.staging(item.id)]
            for file in candidates where FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        } catch { self.error = "No se pudo eliminar el archivo descargado." }
    }

    func file(_ item: DownloadItem) throws -> URL {
        let allowed = ["mp4", "mkv", "m4v", "mov", "webm", "mp3", "m4a", "flac", "aac", "ogg", "wav", "media"]
        guard allowed.contains(item.fileExtension) else { throw HarborError(code: "download-index") }
        let path = try Self.root().appendingPathComponent(item.id.uuidString + "." + item.fileExtension)
        guard path.standardizedFileURL == path.resolvingSymlinksInPath().standardizedFileURL else { throw HarborError(code: "download-index") }
        return path
    }

    func handleBackgroundEvents(_ handler: @escaping () -> Void) { completion = handler }

    private func commit(_ next: [DownloadItem]) throws {
        let data = try JSONEncoder().encode(next)
        guard data.count <= 8 * 1024 * 1024 else { throw HarborError(code: "download-index") }
        let directory = try Self.root()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try data.write(to: directory.appendingPathComponent("index.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        items = next; error = nil
    }
    private func update(_ id: UUID, persist: Bool = true, change: (inout DownloadItem) -> Void) {
        guard ready, let index = items.firstIndex(where: { $0.id == id }) else { return }
        var next = items; change(&next[index])
        do { if persist { try commit(next) } else { items = next } }
        catch { self.error = "No se pudo guardar el estado de las descargas." }
    }
    private func finished(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else {
            if let staging = try? Self.staging(id) { try? FileManager.default.removeItem(at: staging) }
            return
        }
        do {
            let source = try Self.staging(id), destination = try file(item)
            try FileManager.default.moveItem(at: source, to: destination)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            let size = (try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? item.received
            update(id) { $0.status = .complete; $0.received = size; $0.expected = size; $0.message = nil }
            tasks[id] = nil
        } catch { update(id) { $0.status = .failed; $0.message = "No se pudo guardar el archivo descargado." } }
    }
    nonisolated private static func root() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).resolvingSymlinksInPath().standardizedFileURL
        let directory = support.appendingPathComponent("Harbor/Downloads", isDirectory: true)
        guard directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL else { throw HarborError(code: "download-index") }
        return directory
    }
    nonisolated private static func staging(_ id: UUID) throws -> URL { try root().appendingPathComponent(id.uuidString + ".part") }
    nonisolated private static func ownerHash(_ owner: String) -> String { SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined() }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let raw = downloadTask.taskDescription, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in
            let now = Date(), persist = now.timeIntervalSince(self.lastWrite[id] ?? .distantPast) >= 5
            self.update(id, persist: persist) { $0.received = totalBytesWritten; $0.expected = totalBytesExpectedToWrite }
            if persist { self.lastWrite[id] = now }
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let raw = downloadTask.taskDescription, let id = UUID(uuidString: raw) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw HarborError(code: "download-source") }
            let mime = response.mimeType?.lowercased() ?? ""
            guard !mime.contains("mpegurl"), !mime.contains("dash+xml"), !["text/html", "application/json"].contains(mime) else { throw HarborError(code: "download-source") }
            let staging = try Self.staging(id)
            try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The delegate's temporary URL disappears on return. Move it before
            // dispatching the short index/status update to the main actor.
            try FileManager.default.moveItem(at: location, to: staging)
            Task { @MainActor in self.finished(id) }
        } catch { Task { @MainActor in self.update(id) { $0.status = .failed; $0.message = "La fuente no se pudo guardar como un archivo de vídeo o audio." } } }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil, let raw = task.taskDescription, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in self.update(id) { $0.status = .failed; $0.message = "La descarga falló. Vuelve a elegir una fuente." }; self.tasks[id] = nil }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in let handler = self.completion; self.completion = nil; handler?() }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var next = request
        if task.originalRequest?.url?.host?.lowercased() != next.url?.host?.lowercased() || task.originalRequest?.url?.port != next.url?.port || (task.originalRequest?.url?.scheme == "https" && next.url?.scheme != "https") {
            for name in task.originalRequest?.allHTTPHeaderFields?.keys ?? Dictionary<String, String>().keys { next.setValue(nil, forHTTPHeaderField: name) }
        }
        completionHandler(next)
    }
}
