import Foundation

/// Desktop's tier-0 exact-file lookup of its auto-sync (`lib/subtitles/autosync/opensubtitles.ts`): the movie hash of the video is looked up
/// with the person's OpenSubtitles key, and a trusted match is offered as a replacement for the selected subtitle. Desktop's own
/// calibration is provisional, so this is only ever an offer, as on Desktop. The key goes to api.opensubtitles.com alone and never to the download host.
enum OpenSubtitlesHashSwapRules {
    static let apiBase = "https://api.opensubtitles.com/api/v1"
    static let userAgent = "Harbor autosync"
    /// Desktop's `MIN_TRUSTED_DOWNLOADS`.
    static let minimumTrustedDownloads = 50
    /// Desktop's `MIN_SWAP_CUES`.
    static let minimumSwapCues = 4

    struct Entry: Equatable, Sendable {
        let id: String
        let language: String
        let hashMatch: Bool
        let downloadCount: Int
        let fromTrusted: Bool
        let hearingImpaired: Bool
        let aiTranslated: Bool
        let machineTranslated: Bool
        let imdbID: String?
        let fileID: Int
        let fileName: String
    }

    /// Sixteen hexadecimal characters, the shape of an OpenSubtitles movie hash.
    static func isMovieHash(_ text: String) -> Bool {
        text.utf8.count == 16 && text.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) || ($0 >= 65 && $0 <= 70) }
    }

    /// Desktop's `subLanguages` keeps the track's language first and then the preferred ones. iOS asks only for the track's own language
    /// when it is known, so a swap never changes the language the person chose.
    static func languages(trackLanguage: String, preferred: [String]) -> [String] {
        let track = SubtitleLanguages.normalize(trackLanguage)
        let source = track.isEmpty ? preferred : [track]
        var result: [String] = []
        for language in source {
            let code = SubtitleLanguages.normalize(language)
            if !code.isEmpty && !result.contains(code) { result.append(code) }
        }
        return result
    }

    /// Desktop's `searchByHash` address: `GET /subtitles?moviehash=<hash>&languages=<codes>`.
    static func searchURL(hash: String, languages: [String]) -> URL? {
        guard isMovieHash(hash) else { return nil }
        var items = [URLQueryItem(name: "moviehash", value: hash)]
        let codes = languages.map { SubtitleLanguages.normalize($0) }.filter { !$0.isEmpty }
        if !codes.isEmpty { items.append(URLQueryItem(name: "languages", value: codes.joined(separator: ","))) }
        return SubtitleProviderURL.url(apiBase + "/subtitles", items)
    }

    static func searchHeaders(key: String) -> [String: String] {
        ["Api-Key": key, "User-Agent": userAgent, "Accept": "application/json"]
    }

    /// Desktop's `parseSub` for each row of `data`: a row without a usable file id is dropped.
    static func parse(_ data: Data) -> [Entry] {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        return root["data"].array.compactMap { entry(from: $0) }
    }

    private static func entry(from item: JSONValue) -> Entry? {
        let attributes = item["attributes"]
        var file: (id: Int, name: String)?
        for row in attributes["files"].array {
            if let identifier = SubtitleProviderJSON.int(row["file_id"]), identifier > 0 {
                file = (id: identifier, name: SubtitleProviderJSON.text(row["file_name"]) ?? "")
                break
            }
        }
        guard let file else { return nil }
        let identifier = SubtitleProviderJSON.text(item["id"]) ?? SubtitleProviderJSON.text(attributes["subtitle_id"]) ?? ""
        let language = (SubtitleProviderJSON.text(attributes["language"]) ?? "").lowercased()
        return Entry(
            id: identifier,
            language: language,
            hashMatch: SubtitleProviderJSON.flag(attributes["moviehash_match"]) == true,
            downloadCount: SubtitleProviderJSON.int(attributes["download_count"]) ?? 0,
            fromTrusted: SubtitleProviderJSON.flag(attributes["from_trusted"]) == true,
            hearingImpaired: SubtitleProviderJSON.flag(attributes["hearing_impaired"]) == true,
            aiTranslated: SubtitleProviderJSON.flag(attributes["ai_translated"]) == true,
            machineTranslated: SubtitleProviderJSON.flag(attributes["machine_translated"]) == true,
            imdbID: SubtitleProviderIDs.imdb(SubtitleProviderJSON.text(attributes["feature_details"]["imdb_id"])),
            fileID: file.id,
            fileName: file.name)
    }

    /// Desktop's `scoreSub`.
    static func score(_ entry: Entry) -> Int {
        var value = entry.downloadCount
        if entry.fromTrusted { value += 100_000 }
        if entry.aiTranslated || entry.machineTranslated { value -= 50_000 }
        if entry.hearingImpaired { value -= 5 }
        return value
    }

    /// Desktop's `gate`: hash-matched rows in a wanted language and for the same title, best first, and the top one only when it is trusted.
    static func gate(_ entries: [Entry], languages: [String], imdbID: String?) -> (exact: Entry?, candidates: [Entry]) {
        let wanted = Set(languages.map { SubtitleLanguages.normalize($0) }.filter { !$0.isEmpty })
        let wantedTitle = SubtitleProviderIDs.imdb(imdbID)
        let passing = entries.enumerated().filter { _, entry in
            let languageOK = wanted.isEmpty || wanted.contains(SubtitleLanguages.normalize(entry.language))
            let titleOK = wantedTitle == nil || entry.imdbID == nil || entry.imdbID == wantedTitle
            return entry.hashMatch && languageOK && titleOK
        }
        let ordered = passing.sorted { left, right in
            let leftScore = score(left.element), rightScore = score(right.element)
            return leftScore == rightScore ? left.offset < right.offset : leftScore > rightScore
        }.map { $0.element }
        guard let top = ordered.first else { return (exact: nil, candidates: []) }
        let trusted = (top.fromTrusted || top.downloadCount >= minimumTrustedDownloads) && !top.machineTranslated && !top.aiTranslated
        return (exact: trusted ? top : nil, candidates: ordered)
    }

    /// Desktop's `requestDownloadLink`: `POST /download` with the file id.
    static func downloadRequest(fileID: Int, key: String) -> URLRequest? {
        guard fileID > 0, !key.isEmpty, key.rangeOfCharacter(from: .newlines) == nil,
              let url = URL(string: apiBase + "/download") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Api-Key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data("{\"file_id\":\(fileID)}".utf8)
        return request
    }

    /// The download link of a `/download` answer. Only an https address without credentials is used.
    static func downloadLink(_ data: Data) -> URL? {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data),
              let text = SubtitleProviderJSON.text(root["link"]), let safe = SubtitleProviderURL.safe(text),
              let url = URL(string: safe), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    /// The link is fetched with none of the account headers.
    static func fileRequest(_ link: URL) -> URLRequest {
        var request = URLRequest(url: link, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        return request
    }

    /// Whether two subtitle timelines are the same file in practice: the same number of lines, and nearly all starts within `tolerance` seconds.
    /// A swap that changes nothing is not worth offering (Desktop's `requireImprovement`).
    static func timelinesMatch(_ current: [Double], _ replacement: [Double], tolerance: Double = 0.25) -> Bool {
        guard !current.isEmpty, current.count == replacement.count else { return false }
        let left = current.sorted(), right = replacement.sorted()
        var close = 0
        for index in left.indices where abs(left[index] - right[index]) <= tolerance { close += 1 }
        return Double(close) / Double(left.count) >= 0.95
    }
}

/// What this launch has already learned: videos with no trusted match, and the text of the subtitles downloaded (at most eight).
final class OpenSubtitlesHashSwapMemo: @unchecked Sendable {
    static let shared = OpenSubtitlesHashSwapMemo()
    private let lock = NSLock()
    private var misses = Set<String>()
    private var texts: [Int: String] = [:]

    func isMiss(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return misses.contains(key)
    }

    func remember(miss key: String) {
        lock.lock(); defer { lock.unlock() }
        if misses.count >= 64 { misses.removeAll() }
        misses.insert(key)
    }

    func text(forFile id: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        return texts[id]
    }

    func remember(text: String, forFile id: Int) {
        lock.lock(); defer { lock.unlock() }
        if texts.count >= 8 { texts.removeAll() }
        texts[id] = text
    }
}

/// What the auto-sync needs from the profile before it may ask OpenSubtitles anything.
struct OpenSubtitlesHashSwapContext: Sendable {
    let apiKey: String
    let languages: [String]
    let imdbID: String?
}

enum OpenSubtitlesHashSwap {
    /// Nil unless the OpenSubtitles source is on and the profile saved a key (Desktop's `defaultOsConfig`).
    @MainActor static func context(request: SubtitleRequest?, trackLanguage: String, owner: String) -> OpenSubtitlesHashSwapContext? {
        guard SubtitleProviderPreferences.isEnabled(.opensubtitles) else { return nil }
        let store = SubtitleProviderKeyStore.forOwner(owner)
        if !store.ready { try? store.load() }
        let key = store.key(.opensubtitles)
        guard !key.isEmpty else { return nil }
        let preferred = SubtitleLanguages.preferredCodes(PlaybackPreferences.shared.options.subtitleLanguage)
        let languages = OpenSubtitlesHashSwapRules.languages(trackLanguage: trackLanguage, preferred: preferred)
        var imdb: String?
        if let request { imdb = OptionalSubtitleProviders.query(request, languages: []).imdbID }
        return OpenSubtitlesHashSwapContext(apiKey: key, languages: languages, imdbID: imdb)
    }

    /// The hash-matched subtitle as an offer, or nil for any miss: no hash, no trusted match, a failed download, or the same timeline.
    static func resolve(source: PlaybackSource, document: SubtitleDocument, context: OpenSubtitlesHashSwapContext,
                        transport: any SubtitleProviderTransport = SubtitleProviderURLTransport()) async -> SubtitleAutoSync.Correction? {
        guard let movie = await SubtitleMovieHashService.automatic(source),
              let searchURL = OpenSubtitlesHashSwapRules.searchURL(hash: movie.hash, languages: context.languages) else { return nil }
        // An answer is remembered for this launch, so running the auto-sync again does not spend the person's download quota again.
        let memo = OpenSubtitlesHashSwapMemo.shared
        let memoKey = movie.hash + "|" + context.languages.joined(separator: ",")
        if memo.isMiss(memoKey) { return nil }
        do {
            try Task.checkCancellation()
            let found = try await SubtitleProviderFetch.fetchData(searchURL, headers: OpenSubtitlesHashSwapRules.searchHeaders(key: context.apiKey), transport: transport)
            let gated = OpenSubtitlesHashSwapRules.gate(OpenSubtitlesHashSwapRules.parse(found), languages: context.languages, imdbID: context.imdbID)
            guard let exact = gated.exact else {
                memo.remember(miss: memoKey)
                return nil
            }
            var text = memo.text(forFile: exact.fileID)
            if text == nil {
                guard let download = OpenSubtitlesHashSwapRules.downloadRequest(fileID: exact.fileID, key: context.apiKey) else { return nil }
                try Task.checkCancellation()
                let reply = try await transport.send(download)
                guard (200..<300).contains(reply.status), let link = OpenSubtitlesHashSwapRules.downloadLink(reply.data) else { return nil }
                try Task.checkCancellation()
                let file = try await transport.send(OpenSubtitlesHashSwapRules.fileRequest(link))
                guard (200..<300).contains(file.status), !file.data.isEmpty else { return nil }
                let converted: Data = SubtitleTextEncoding.convertedUTF8(file.data, language: nil) ?? file.data
                guard let decoded = String(data: converted, encoding: .utf8) else { return nil }
                memo.remember(text: decoded, forFile: exact.fileID)
                text = decoded
            }
            guard let subtitleText = text else { return nil }
            let replacement = try SubtitleDocument(subtitleText)
            guard replacement.cues.count >= OpenSubtitlesHashSwapRules.minimumSwapCues,
                  !OpenSubtitlesHashSwapRules.timelinesMatch(document.cues.map { $0.start }, replacement.cues.map { $0.start }) else { return nil }
            let identity = SubtitleSyncResult(offset: 0, ratio: 1, confidence: 1)
            return SubtitleAutoSync.Correction(document: replacement, timing: identity, origin: .hashExact, reportsTiming: false)
        } catch {
            return nil
        }
    }
}
