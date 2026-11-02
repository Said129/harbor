import Foundation

struct SubtitleMovieHash: Codable, Sendable {
    let hash: String
    let size: UInt64
}

/// Desktop's 64 KiB + 64 KiB movie hash; no video download or player seek.
enum SubtitleMovieHashService {
    private static let chunk = 65_536
    static func automatic(_ source: PlaybackSource) async -> SubtitleMovieHash? {
        guard let url = URL(string: source.url), !["127.0.0.1", "localhost", "::1", "[::1]"].contains(url.host?.lowercased() ?? "") else { return nil }
        return try? await compute(source)
    }
    static func compute(_ source: PlaybackSource) async throws -> SubtitleMovieHash {
        try Task.checkCancellation()
        guard let url = URL(string: source.url) else { throw HarborError(code: "subtitle-hash-url") }
        let size: UInt64, head: Data, tail: Data
        if url.isFileURL {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard info.isRegularFile == true, let length = info.fileSize, length >= chunk * 2 else { throw HarborError(code: "subtitle-hash-size") }
            size = UInt64(length)
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            head = try handle.read(upToCount: chunk) ?? Data()
            try handle.seek(toOffset: size - UInt64(chunk))
            tail = try handle.read(upToCount: chunk) ?? Data()
        } else {
            guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
                  url.user == nil, url.password == nil else { throw HarborError(code: "subtitle-hash-url") }
            let deadline = Date().addingTimeInterval(1.8)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
            configuration.timeoutIntervalForResource = 1.8
            let session = URLSession(configuration: configuration, delegate: SubtitleHashRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let first = try await range(url, from: 0, to: UInt64(chunk - 1), source: source, session: session, deadline: deadline)
            size = first.size; head = first.data
            guard size >= UInt64(chunk * 2) else { throw HarborError(code: "subtitle-hash-size") }
            let last = try await range(url, from: size - UInt64(chunk), to: size - 1, source: source, session: session, deadline: deadline)
            guard last.size == size else { throw HarborError(code: "subtitle-hash-range") }
            tail = last.data
        }
        try Task.checkCancellation()
        guard head.count == chunk, tail.count == chunk else { throw HarborError(code: "subtitle-hash-size") }
        return try await CoreBridge().call("subtitleMovieHash", ["size": try .encoded(size), "head": .string(head.base64EncodedString()), "tail": .string(tail.base64EncodedString())])
    }
    private static func range(_ url: URL, from: UInt64, to: UInt64, source: PlaybackSource, session: URLSession, deadline: Date) async throws -> (size: UInt64, data: Data) {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw HarborError(code: "subtitle-hash-timeout") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: remaining)
        for (name, value) in source.headers ?? [:] {
            guard !name.isEmpty, name.rangeOfCharacter(from: .controlCharacters) == nil, value.rangeOfCharacter(from: .controlCharacters) == nil else { throw HarborError(code: "subtitle-hash-headers") }
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("bytes=\(from)-\(to)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 206,
              response.expectedContentLength < 0 || response.expectedContentLength == Int64(chunk),
              let header = response.value(forHTTPHeaderField: "Content-Range"), header.lowercased().hasPrefix("bytes ") else { throw HarborError(code: "subtitle-hash-range") }
        let parts = header.dropFirst(6).split(separator: "/"), range = parts.first?.split(separator: "-") ?? []
        guard parts.count == 2, range.count == 2, UInt64(range[0]) == from, UInt64(range[1]) == to,
              let size = UInt64(parts[1]), size > to else { throw HarborError(code: "subtitle-hash-range") }
        var data = Data(); data.reserveCapacity(chunk)
        for try await byte in bytes {
            if data.count.isMultiple(of: 4096) { try Task.checkCancellation(); guard Date() < deadline else { throw HarborError(code: "subtitle-hash-timeout") } }
            guard data.count < chunk else { throw HarborError(code: "subtitle-hash-range") }
            data.append(byte)
        }
        guard data.count == chunk else { throw HarborError(code: "subtitle-hash-size") }
        return (size, data)
    }
}

private final class SubtitleHashRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int: Int] = [:]
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); let count = (counts[task.taskIdentifier] ?? 0) + 1; counts[task.taskIdentifier] = count; lock.unlock()
        let allowed = count <= 3
        guard allowed, let target = request.url, ["https", "http"].contains(target.scheme?.lowercased() ?? ""), target.user == nil, target.password == nil,
              !(response.url?.scheme == "https" && target.scheme != "https") else { completionHandler(nil); return }
        var next = request
        let origin = response.url
        if origin?.scheme != target.scheme || origin?.host != target.host || origin?.port != target.port {
            next.allHTTPHeaderFields = [:]
            next.setValue(task.originalRequest?.value(forHTTPHeaderField: "Range"), forHTTPHeaderField: "Range")
            next.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        }
        completionHandler(next)
    }
}
