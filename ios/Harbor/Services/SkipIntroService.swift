import Foundation

struct SkipSegment: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case intro, outro, recap, ad }
    let kind: Kind
    let start: Double
    let end: Double
    let source: String
    var id: String { "\(source):\(kind.rawValue):\(start):\(end)" }
    var label: String {
        switch kind {
        case .intro: DesktopInterfaceText.value("Skip Intro")
        case .outro: DesktopInterfaceText.value("Skip Credits")
        case .recap: DesktopInterfaceText.value("Skip Recap")
        case .ad: DesktopInterfaceText.value("Skip injected ad?")
        }
    }
    func active(at position: Double) -> Bool { position.isFinite && position >= start && position < end - 0.75 }
    /// The segment Desktop would skip by itself at this moment (`skip-pill-container.tsx`): the active one,
    /// when its kind is switched on, once per segment so seeking back into an intro replays it.
    static func autoSkipCandidate(at position: Double, in segments: [Self], options: PlaybackOptions, skipped: Set<String>) -> Self? {
        guard position > 0, let segment = segments.first(where: { $0.active(at: position) }), options.autoSkips(segment.kind), !skipped.contains(segment.id) else { return nil }
        return segment
    }
    static func merge(_ sources: [[Self]], duration: Double) -> [Self] {
        guard duration.isFinite, duration > 0 else { return [] }
        var result: [Self] = []
        for source in sources {
            for item in source where item.start.isFinite && item.end.isFinite && item.start >= 0 && item.start < duration {
                let segment = Self(kind: item.kind, start: item.start, end: min(item.end, duration), source: item.source)
                guard (2...360).contains(segment.end - segment.start), segment.kind != .outro || segment.start >= duration * 0.5,
                      !result.contains(where: { segment.start < $0.end && segment.end > $0.start }) else { continue }
                result.append(segment)
            }
        }
        return result.sorted { $0.start < $1.start }
    }
    static func chapters(_ chapters: [PlayerState.Chapter], duration: Double) -> [Self] {
        let ordered = chapters.filter { $0.time.isFinite && $0.time >= 0 }.sorted { $0.time < $1.time }
        return ordered.enumerated().compactMap { index, chapter in
            let name = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let kind: Kind
            if name.range(of: #"\b(opening|op|intro|theme song|introducción)\b"#, options: .regularExpression) != nil { kind = .intro }
            else if name.range(of: #"\b(ending|ed|outro|credits|créditos)\b"#, options: .regularExpression) != nil { kind = .outro }
            else if name.range(of: #"\b(recap|previously|resumen|anteriormente)\b"#, options: .regularExpression) != nil { kind = .recap }
            else { return nil }
            return Self(kind: kind, start: chapter.time, end: index + 1 < ordered.count ? ordered[index + 1].time : duration, source: "chapters")
        }
    }
}

extension PlaybackOptions {
    /// `autoSkipAd` is Desktop's setting, kept in the UserDefaults store `StreamPreferences` writes.
    func autoSkips(_ kind: SkipSegment.Kind, autoSkipAd: Bool = UserDefaults.standard.bool(forKey: "autoSkipAd")) -> Bool {
        switch kind {
        case .intro: autoSkipIntro
        case .recap: autoSkipRecap
        case .outro: autoSkipOutro
        case .ad: autoSkipAd
        }
    }
    var autoSkipsAnySegment: Bool { autoSkipIntro || autoSkipRecap || autoSkipOutro || UserDefaults.standard.bool(forKey: "autoSkipAd") }
}

actor SkipIntroService {
    static let shared = SkipIntroService()
    private var cache: [String: (Date, [SkipSegment])] = [:]
    private var pending: [String: Task<[SkipSegment], Never>] = [:]
    /// `stream` is the chosen release for the ad corpus. Without it, or with ad skip off, no ad segments are asked for.
    func segments(target: ResumeTarget, media: Media?, duration: Double, stream: AdSkipStream? = nil) async throws -> [SkipSegment] {
        guard duration.isFinite, duration > 0, duration < 86400 else { return [] }
        let selected = media?.videos?.first { $0.id == target.videoId }
        let external = media?.imdbID ?? selected?.imdbID ?? target.id
        let season = selected?.imdbSeason ?? target.season, episode = selected?.imdbEpisode ?? target.episode
        let apiKey = await Self.theIntroDBKey()
        // Desktop's `useAdSegments`: only while ad skip is on, for the content and the exact release that plays.
        let ad = await Self.adFingerprint(metaID: media?.id ?? target.id, imdbID: media?.imdbID, stream: stream)
        let adKey = ad.map { "\($0.content)|\($0.source)" } ?? "ad-off"
        // A new TheIntroDB key must not reuse an answer given for the old one, as Desktop clears its cache on a key change.
        // Another release of the same episode must not reuse this one's ad ranges either.
        let key = [target.id, external, String(season ?? -1), String(episode ?? -1), String(target.episode ?? -1), String(Int(duration.rounded())), String(apiKey.hashValue), adKey].joined(separator: "|")
        if let hit = cache[key], hit.0 > Date() { return hit.1 }
        if let task = pending[key] { return try checked(await task.value) }
        let task = Task {
            async let ads = Self.ads(ad)
            async let anime = Self.anime(id: target.id, episode: target.episode, duration: duration)
            async let television = Self.television(id: external, season: season, episode: episode, duration: duration, apiKey: apiKey)
            // Ad segments come first, as Desktop merges them first, so they win an overlap.
            return await SkipSegment.merge([ads, anime, television], duration: duration)
        }
        pending[key] = task
        let result = await task.value
        pending[key] = nil
        if cache.count >= 32, let oldest = cache.min(by: { $0.value.0 < $1.value.0 })?.key { cache.removeValue(forKey: oldest) }
        cache[key] = (Date().addingTimeInterval(result.isEmpty ? 60 : 300), result)
        return try checked(result)
    }
    private func checked(_ result: [SkipSegment]) throws -> [SkipSegment] { try Task.checkCancellation(); return result }
    private static func anime(id: String, episode: Int?, duration: Double) async -> [SkipSegment] {
        guard let episode, episode > 0 else { return [] }
        do {
            let parts = id.split(separator: ":")
            guard parts.count >= 2, let identifier = Int(parts[1]), identifier > 0 else { return [] }
            let mal: Int?
            switch parts[0] {
            case "mal", "myanimelist": mal = identifier
            case "kitsu":
                let response = try await HTTPClient().json("https://kitsu.io/api/edge/anime/\(identifier)/mappings", accept: "application/vnd.api+json")
                mal = response["data"].array.first { $0["attributes"]["externalSite"].string == "myanimelist/anime" }?["attributes"]["externalId"].string.flatMap(Int.init)
            case "anilist":
                let response = try await HTTPClient().anilist(query: "query($id:Int!){Media(id:$id,type:ANIME){idMal}}", variables: .object(["id": .integer(Int64(identifier))]))
                mal = response["Media"]["idMal"].integer
            default: return []
            }
            guard let mal, mal > 0 else { return [] }
            let response = try await HTTPClient().json("https://api.aniskip.com/v2/skip-times/\(mal)/\(episode)?types=op&types=ed&types=mixed-op&types=mixed-ed&types=recap&episodeLength=\(Int(duration.rounded()))")
            return parseAniSkip(response)
        } catch { return [] }
    }
    private static func television(id: String, season: Int?, episode: Int?, duration: Double, apiKey: String) async -> [SkipSegment] {
        await TheIntroDBClient.shared.segments(metaID: id, season: season, episode: episode, duration: duration, apiKey: apiKey)
    }
    /// The fingerprint of the chosen release while ad skip is on, else nil.
    @MainActor private static func adFingerprint(metaID: String, imdbID: String?, stream: AdSkipStream?) -> AdSkipFingerprint.Key? {
        guard StreamPreferences.shared.adSkipEnabled, let stream else { return nil }
        return AdSkipFingerprint.fingerprint(metaID: metaID, imdbID: imdbID, infoHash: stream.infoHash, fileIdx: stream.fileIdx,
                                             releaseGroup: stream.releaseGroup, size: stream.size, parsedTitle: stream.parsedTitle, url: stream.url)
    }
    private static func ads(_ key: AdSkipFingerprint.Key?) async -> [SkipSegment] {
        guard let key else { return [] }
        return await AdCorpus.shared.segments(content: key.content, source: key.source, fresh: true)
    }
    /// The TheIntroDB key of the profile whose settings are bound, kept in its Keychain store. Empty when none is bound.
    @MainActor private static func theIntroDBKey() -> String {
        guard let owner = MetadataPreferences.shared.settingsOwner else { return "" }
        let store = ProviderKeyStore.forOwner(owner)
        if !store.ready { try? store.load() }
        return store.key(.theIntroDb)
    }
    nonisolated static func parseAniSkip(_ response: JSONValue) -> [SkipSegment] {
        guard response["found"] == .bool(true) else { return [] }
        return response["results"].array.compactMap {
            guard let start = number($0["interval"]["startTime"]), let end = number($0["interval"]["endTime"]), let type = $0["skipType"].string, ["op", "ed", "mixed-op", "mixed-ed", "recap"].contains(type) else { return nil }
            return SkipSegment(kind: type == "recap" ? .recap : ["ed", "mixed-ed"].contains(type) ? .outro : .intro, start: start, end: end, source: "aniskip")
        }
    }
    nonisolated static func parseIntroDB(_ response: JSONValue, duration: Double) -> [SkipSegment] {
        [("intro", SkipSegment.Kind.intro), ("recap", .recap), ("credits", .outro), ("preview", .outro)].flatMap { key, kind in
            response[key].array.map { SkipSegment(kind: kind, start: (number($0["start_ms"]) ?? 0) / 1000, end: (number($0["end_ms"]) ?? duration * 1000) / 1000, source: "introdb") }
        }
    }
    nonisolated private static func number(_ value: JSONValue) -> Double? {
        switch value { case .number(let number): number; case .integer(let number): Double(number); case .unsigned(let number): Double(number); default: nil }
    }
}
