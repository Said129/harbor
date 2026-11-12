import Foundation

/// Where Harbor reads the ASS text that `AssSizeNormalization` measures (Desktop's `use-ass-normalize.ts` `loadAssText`).
/// Desktop reads an external file from its path or URL and asks ffmpeg for an embedded track. iOS has no ffmpeg, so an embedded
/// track, or an external one that cannot be read, takes the header mpv itself holds for the selected track (`sub-ass-extradata`).
enum SubtitleAssHeaderSource: Equatable {
    case localFile(URL)
    case remoteFile(URL)
    case mpvHeader

    static func choose(for track: PlayerState.Track) -> SubtitleAssHeaderSource {
        guard track.external, !track.externalFilename.isEmpty else { return .mpvHeader }
        if let local = SubtitleSelectionWiring.localFileURL(track.externalFilename) { return .localFile(local) }
        if let remote = remoteURL(track.externalFilename) { return .remoteFile(remote) }
        return .mpvHeader
    }

    /// An http or https address with a host and no credentials, the same bar the other subtitle downloads use.
    static func remoteURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

enum SubtitleAssHeaderLoader {
    /// The largest file read for measuring. External files are bounded like the other subtitle files (8 MiB).
    static let byteLimit = 8 * 1_024 * 1_024

    /// The text of a local subtitle file as UTF-8, or nil when it is missing, empty, too large or not text.
    static func text(forFileAt url: URL) -> String? {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0, size <= byteLimit,
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// Bounded download for an addon subtitle that mpv opened from its address. No cookies, no credentials, no cache, no redirects off http(s).
    static func fetch(_ url: URL) async -> String? {
        guard SubtitleAssHeaderSource.remoteURL(url.absoluteString) != nil else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  http.expectedContentLength <= Int64(byteLimit) else { return nil }
            var data = Data()
            for try await byte in bytes {
                if data.count.isMultiple(of: 4_096) { try Task.checkCancellation() }
                guard data.count < byteLimit else { return nil }
                data.append(byte)
            }
            return decode(data)
        } catch {
            return nil
        }
    }

    /// UTF-16 and legacy code pages go through the same conversion the subtitle downloads use.
    static func decode(_ data: Data) -> String? {
        guard !data.isEmpty, data.count <= byteLimit else { return nil }
        let converted: Data = SubtitleTextEncoding.convertedUTF8(data, language: nil) ?? data
        guard let text = String(data: converted, encoding: .utf8), !text.contains("\u{0}") else { return nil }
        return text
    }
}
