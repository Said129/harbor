import XCTest
import UIKit
@testable import Harbor

final class NativeDataTests: XCTestCase {
    func testMALPublicCatalogPreservesProviderRatingsFiltersAndSeasonBoundaries() throws {
        // Minimal independently observed MAL v2 node, not a substitute catalog in the app.
        let node: JSONValue = .object(["id": .integer(16498), "title": .string("Shingeki no Kyojin"), "alternative_titles": .object(["en": .string("Attack on Titan")]),
                                      "main_picture": .object(["large": .string("https://cdn.myanimelist.net/images/anime/10/47347.jpg")]),
                                      "mean": .number(8.58), "nsfw": .string("white"), "media_type": .string("tv"),
                                      "genres": .array([.object(["name": .string("Action")])]), "start_season": .object(["year": .integer(2013)])])
        var explicit = node.objectValue; explicit["id"] = .integer(2); explicit["nsfw"] = .string("black")
        var unknown = node.objectValue; unknown["id"] = .integer(3); unknown.removeValue(forKey: "nsfw")
        let response: JSONValue = .object(["data": .array([.object(["node": node]), .object(["node": node]), .object(["node": .object(explicit)]), .object(["node": .object(unknown)])])])
        let items = try MALPublicCatalog.parse(response)
        XCTAssertEqual(items.map(\.id), ["mal:16498"])
        XCTAssertEqual(items.first?.name, "Attack on Titan")
        XCTAssertEqual(items.first?.imdbRating, "8.6"); XCTAssertEqual(items.first?.ratingSource, "MAL")
        XCTAssertEqual(items.first?.releaseInfo, "2013"); XCTAssertEqual(items.first?.type, "series")
        let second = try MALPublicCatalog.request("anime-popular", page: 2)
        XCTAssertEqual(second.parameters["offset"], "25"); XCTAssertEqual(second.parameters["ranking_type"], "bypopularity")
        let december = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-31T23:59:00Z"))
        XCTAssertEqual(try MALPublicCatalog.request("anime-upcoming", page: 1, now: december).path, "/anime/season/2027/winter")
        XCTAssertThrowsError(try MALPublicCatalog.request("anime-popular", page: 0))
    }

    func testCommunityIndexRequiresRealRatingsAndIsolatesUnsafeRows() async throws {
        let manifest: JSONValue = .object(["id": .string("com.linvo.cinemeta"), "name": .string("Cinemeta"), "version": .string("3.0.0"), "types": .array([.string("movie"), .string("series")]), "resources": .array([.string("catalog"), .string("meta")]), "catalogs": .array([])])
        let valid: [String: JSONValue] = ["uuid": .string("community-test"), "slug": .string("cinemeta"), "stars": .integer(12), "manifestUrl": .string("https://v3-cinemeta.strem.io/manifest.json"), "manifest": manifest, "categories": .array([.object(["slug": .string("http+streams")]), .object(["slug": .string("torrents")])])]
        var missingRating = valid; missingRating["uuid"] = .string("missing-rating"); missingRating.removeValue(forKey: "stars")
        var credentialed = valid; credentialed["uuid"] = .string("credentialed"); credentialed["manifestUrl"] = .string("https://private@example.com/manifest.json")
        var adult = valid; adult["uuid"] = .string("adult-category"); adult["categories"] = .array([.object(["slug": .string("nsfw")])])
        let rows = try await CommunityAddons.parse(.object(["addons": .array([.object(valid), .object(missingRating), .object(credentialed), .object(valid), .object(adult)])]))
        XCTAssertEqual(rows.map(\.id), ["community-test", "adult-category"])
        XCTAssertEqual(rows.first?.stars, 12, "Unavailable ratings must not turn into fabricated zero-star cards")
        XCTAssertEqual(rows.first?.siteURL?.absoluteString, "https://stremio-addons.net/addons/cinemeta")
        XCTAssertEqual(rows.last?.adult, true, "An NSFW category must apply even when the manifest omits its adult flag")
        XCTAssertEqual(rows.first?.categories, Set(["http+streams", "torrents"]), "Community addons can belong to multiple categories")
        let path = CommunityAddons.browsePath(page: 2, sort: .createdAt, category: .streams, query: "a&b+c", allowAdult: false)
        let parts = try XCTUnwrap(URLComponents(string: path))
        XCTAssertEqual(parts.queryItems?.first { $0.name == "category" }?.value, "http+streams")
        XCTAssertTrue(path.contains("http%2Bstreams"), "The public API form decoder must not turn category '+' into a space")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "search" }?.value, "a&b+c")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "nsfw" }?.value, "exclude")
        let pagination: JSONValue = .object(["page": .integer(2), "limit": .integer(50), "total": .integer(101), "totalPages": .integer(3), "hasNextPage": .bool(true)])
        XCTAssertEqual(try CommunityAddons.nextPage(pagination, expectedPage: 2), 3)
        XCTAssertThrowsError(try CommunityAddons.nextPage(pagination, expectedPage: 3), "A stale response must not skip another page")
        XCTAssertThrowsError(try CommunityAddons.nextPage(.object(["page": .integer(2), "hasNextPage": .bool(true)]), expectedPage: 2), "Missing cursors must not silently mean the end")
        let empty = try await CommunityAddons.parse(.object(["addons": .array([])]))
        XCTAssertTrue(empty.isEmpty)
    }

    @MainActor func testDiscoveryVotesPersistPerAccountAndAffectActualRecommendations() throws {
        let owner = "discovery-test-" + UUID().uuidString
        let key = DiscoveryPreferences.key(owner)
        defer { try? KeychainStore().remove(key) }
        let now = Date(timeIntervalSince1970: 1_791_417_600)
        var science = Media(id: "tt0816692", type: "movie", name: "Interstellar")
        science.genres = ["Sci-Fi"]; science.releaseInfo = "2014"; science.imdbRating = "8.6"
        var similar = Media(id: "tt1187064", type: "movie", name: "Triangle")
        similar.genres = ["Sci-Fi"]; similar.releaseInfo = "2009"; similar.imdbRating = "8.6"
        var romance = Media(id: "tt0338013", type: "movie", name: "Eternal Sunshine")
        romance.genres = ["Romance"]; romance.releaseInfo = "2004"; romance.imdbRating = "8.6"
        let preferences = DiscoveryPreferences(owner: owner)
        XCTAssertTrue(preferences.toggle(.up, for: science, now: now))
        XCTAssertEqual(DiscoveryPreferences(owner: owner).vote(for: science), .up)
        XCTAssertNil(DiscoveryPreferences(owner: owner + "-other").vote(for: science))
        XCTAssertTrue(preferences.excludes(science, now: now))
        XCTAssertFalse(preferences.excludes(science, now: now.addingTimeInterval(7 * 86_400 + 1)))
        let candidates = [romance, similar, science].enumerated().map { FeaturedRanking.Candidate(media: $0.element, source: .seed, rank: $0.offset) }
        XCTAssertEqual(FeaturedRanking.select(candidates, preferences: preferences, excluded: [], now: now).first?.id, similar.id)
        XCTAssertTrue(preferences.toggle(.down, for: similar, now: now))
        var alternate = similar; alternate.id = "tmdb:26466"; alternate.background = "https://example.com/backdrop.jpg"
        XCTAssertTrue(preferences.excludes(alternate, now: now), "Provider aliases for the same title must remain excluded")
        XCTAssertFalse(FeaturedRanking.select(candidates, preferences: preferences, excluded: [], now: now).contains { $0.id == similar.id })
        XCTAssertTrue(preferences.toggle(.down, for: similar, now: now))
        XCTAssertNil(DiscoveryPreferences(owner: owner).vote(for: similar))
        let previous = preferences.votes[science.id]
        XCTAssertTrue(preferences.toggle(.down, for: science, now: now))
        let applied = preferences.votes[science.id]
        XCTAssertFalse(preferences.restoreVote(for: science.id, expected: previous, previous: nil), "Undo cannot overwrite a newer vote")
        XCTAssertTrue(preferences.restoreVote(for: science.id, expected: applied, previous: previous))
        XCTAssertEqual(DiscoveryPreferences(owner: owner).votes[science.id], previous)
        XCTAssertTrue(DiscoveryPreferences(owner: owner).hintDismissed)
        let damaged: JSONValue = .object(["votes": .string("invalid")])
        try KeychainStore().write(damaged, key: key)
        let preserved = DiscoveryPreferences(owner: owner)
        XCTAssertFalse(preserved.ready)
        XCTAssertFalse(preserved.toggle(.up, for: science, now: now))
        XCTAssertEqual(try KeychainStore().read(key, as: JSONValue.self), damaged)
    }
    @MainActor func testAutomaticPlaybackSkipsUnresolvedSourcesAndPreservesQualityOrder() {
        let torrent = StreamOffer(id: 0, raw: .object(["infoHash": .string(String(repeating: "a", count: 40)), "tier": .string("4K")]))
        let direct = StreamOffer(id: 1, raw: .object(["url": .string("https://example.com/first.mp4"), "tier": .string("1080p")]))
        let tied = StreamOffer(id: 2, raw: .object(["url": .string("https://example.com/second.mp4"), "tier": .string("1080p")]))
        let preferences = StreamPreferences()
        XCTAssertEqual(preferences.preferred([torrent, direct, tied])?.id, direct.id)
        XCTAssertNil(preferences.preferred([torrent]))
        XCTAssertNil(torrent.pickerStatus, "A torrent without a cache result must not claim Instant or Cached")
        let suspicious = StreamOffer(id: 20, raw: .object(["resolution": .string("4K"), "source": .string("Other"), "codec": .string("HEVC"), "tier": .string("4K"), "reasons": .array([.object(["signal": .string("fresh-fake-4k")])])]))
        XCTAssertEqual(suspicious.pickerLeadBadge, "unknown", "A suspect addon label must not display a verified 4K badge")
        let named = StreamOffer(id: 21, raw: .object(["name": .string("Real source name"), "title": .string("Actual filename.mkv\nSpanish"), "audioLanguages": .array([.string("Spanish"), .string("es"), .string("unknown")]), "addonId": .string("configured-addon"), "addonPriority": .integer(0)]))
        let otherInstance = StreamOffer(id: 22, raw: .object(["addonId": .string("configured-addon"), "addonPriority": .integer(1)]))
        XCTAssertNotEqual(named.pickerInstance, otherInstance.pickerInstance, "Configured copies of a manifest must remain separate in provider filters")
        XCTAssertEqual(named.pickerLanguages, ["es"])
        XCTAssertEqual(named.pickerTitle(media: Media(id: "tt0816692", type: "movie", name: "Interstellar"), episode: nil), "Real source name")
        XCTAssertEqual(named.pickerFilename, "Actual filename.mkv")
        let camera = StreamOffer(id: 3, raw: .object(["title": .string("Film 1080p TS")]))
        XCTAssertTrue(camera.cameraRecording)
        XCTAssertFalse(StreamOffer(id: 4, raw: .object(["title": .string("Artists 1080p WEB-DL")])).cameraRecording)
        let initialKeepSource = preferences.keepSourceNextEpisode
        defer { preferences.keepSourceNextEpisode = initialKeepSource }
        let previous = StreamOffer(id: 5, raw: .object(["addonId": .string("first-addon"), "behaviorHints": .object(["bingeGroup": .string("same-release")])]))
        let sameRelease = StreamOffer(id: 6, raw: .object(["url": .string("https://example.com/next.mp4"), "tier": .string("1080p"), "addonId": .string("second-addon"), "behaviorHints": .object(["bingeGroup": .string("same-release")])]))
        let best = StreamOffer(id: 7, raw: .object(["url": .string("https://example.com/best.mp4"), "tier": .string("4K"), "addonId": .string("first-addon"), "behaviorHints": .object(["bingeGroup": .string("another-release")])]))
        let identity = StreamSourceIdentity(previous)
        preferences.keepSourceNextEpisode = false
        XCTAssertEqual(preferences.preferredContinuation([best, sameRelease], previous: identity)?.id, best.id)
        preferences.keepSourceNextEpisode = true
        XCTAssertEqual(preferences.preferredContinuation([best, sameRelease], previous: identity)?.id, sameRelease.id)
        XCTAssertEqual(preferences.preferredContinuation([best], previous: identity)?.id, best.id, "A different release from the same addon must not count as a match")
        XCTAssertEqual(preferences.preferredContinuation([best], previous: nil)?.id, best.id)
        let hash = StreamSourceIdentity(StreamOffer(id: 8, raw: .object(["infoHash": .string(String(repeating: "A", count: 40))])))
        XCTAssertTrue(hash.matches(torrent))
        XCTAssertFalse(hash.matches(StreamOffer(id: 9, raw: .object(["infoHash": .string(String(repeating: "b", count: 40))]))))
        let source = StreamSourceIdentity(StreamOffer(id: 10, raw: .object(["addonId": .string("one"), "resolution": .string("1080p"), "source": .string("WEB-DL")])))
        XCTAssertTrue(source.matches(StreamOffer(id: 11, raw: .object(["addonId": .string("one"), "resolution": .string("1080p"), "source": .string("WEB-DL")]))))
        XCTAssertFalse(source.matches(StreamOffer(id: 12, raw: .object(["addonId": .string("one"), "resolution": .string("720p"), "source": .string("WEB-DL")]))))
    }
    func testEditorialUpdatesValidateBeforeReplacingBundledSelections() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "SpooktoberContent", withExtension: "json"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(try SpooktoberCatalog.decode(data).count, 71)
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let first = rows[0]
        XCTAssertThrowsError(try SpooktoberCatalog.decode(JSONSerialization.data(withJSONObject: [first, first]), remote: true))
        rows[0]["source"] = "javascript:alert(1)"
        XCTAssertThrowsError(try SpooktoberCatalog.decode(JSONSerialization.data(withJSONObject: rows), remote: true))
        rows[0] = first; rows[0]["poster"] = "assets/posters/../../account.json"
        XCTAssertThrowsError(try SpooktoberCatalog.decode(JSONSerialization.data(withJSONObject: rows), remote: true))
        rows[0]["poster"] = "assets/posters/new-cover.webp"
        let updated = try SpooktoberCatalog.decode(JSONSerialization.data(withJSONObject: rows), remote: true)
        XCTAssertEqual(updated[0].poster, SpooktoberCatalog.upstream + "assets/posters/new-cover.webp")
        XCTAssertEqual(try SpooktoberCatalog.load().first?.title, first["title"] as? String)
    }
    @MainActor func testFavoritesKeepWatchlistSeparateAndPersistInTheirAccount() throws {
        let owner = "favorite-test-" + UUID().uuidString
        let key = "media-favorites-" + EBookShelf.hash(owner)
        defer { try? KeychainStore().remove(key) }
        let media = Media(id: "tt0816692", type: "movie", name: "Interstellar")
        let favorites = MediaFavorites(owner: owner)
        favorites.toggle(media)
        XCTAssertTrue(favorites.contains(media))
        XCTAssertTrue(MediaFavorites(owner: owner).contains(media))
        XCTAssertFalse(MediaFavorites(owner: owner + "-other").contains(media))
        let record = try XCTUnwrap(favorites.entries.first?.record)
        XCTAssertEqual(record.media?.id, media.id)
        XCTAssertFalse(record.bookmarked, "A favorite must not silently alter the Stremio watchlist")
        favorites.toggle(media)
        XCTAssertTrue(MediaFavorites(owner: owner).entries.isEmpty)
    }
    @MainActor func testOriginalAvatarAssetsAndIsolatedProfilePersistence() throws {
        XCTAssertEqual(DesktopAvatar.catalog.count, 65)
        for avatar in DesktopAvatar.catalog { XCTAssertNotNil(UIImage(named: avatar.asset), "Missing original avatar: \(avatar.id)") }
        let owner = "profile-test-" + UUID().uuidString
        let key = "mobile-profile-" + EBookShelf.hash(owner)
        defer { try? KeychainStore().remove(key) }
        let profile = ProfilePreferences.forOwner(owner)
        XCTAssertTrue(profile.ready)
        profile.update { $0.name = "Harbor"; $0.avatar = DesktopAvatar.catalog[1].id; $0.color = "fbbf24" }
        let saved = try XCTUnwrap(KeychainStore().read(key, as: MobileProfile.self))
        XCTAssertEqual(saved.name, "Harbor")
        XCTAssertEqual(saved.avatar, DesktopAvatar.catalog[1].id)
        XCTAssertTrue(saved.valid)
        XCTAssertEqual(ProfilePreferences.forOwner(owner + "-other").value.name, "")
        let legacy = Data(#"{"filter":"saved","kind":"movie","sort":"title"}"#.utf8)
        let display = try JSONDecoder().decode(LibraryDisplay.self, from: legacy)
        XCTAssertEqual(display.filter, .saved)
        XCTAssertEqual(display.kind, .movie)
        XCTAssertEqual(display.sort, .title)
        XCTAssertTrue(display.grouped, "The old saved presentation must survive the new layout")
    }
    func testCloudResumeMatchesTheEpisodeAndRecognizesCompletedMovies() throws {
        let raw: JSONValue = .object(["_id": .string("show"), "type": .string("series"), "name": .string("Show"), "_mtime": .string("2026-10-05T18:00:00.123Z"), "state": .object(["video_id": .string("show:0:1"), "timeOffset": .integer(120_000), "duration": .integer(3_600_000)])])
        let record = LibraryRecord(raw: raw)
        let matching = record.resume(for: ResumeTarget(id: "show", season: 0, episode: 1, videoId: "show:0:1"))
        XCTAssertEqual(matching?.entry.ms, 120_000)
        XCTAssertEqual(matching?.durationMs, 3_600_000)
        XCTAssertNil(record.resume(for: ResumeTarget(id: "show", season: 1, episode: 1, videoId: "show:1:1")))
        XCTAssertNil(record.resume(for: ResumeTarget(id: "other", videoId: "show:0:1")))
        let movie = LibraryRecord(raw: .object(["_id": .string("movie"), "type": .string("movie"), "name": .string("Movie"), "_mtime": .string("2026-10-05T18:00:00Z"), "state": .object(["timeOffset": .integer(120_000), "flaggedWatched": .integer(1)])]))
        XCTAssertEqual(movie.resume(for: ResumeTarget(id: "movie"))?.entry.ms, 0)

        // Hiding a card must leave its cloud fields intact, resist stale earlier
        // episodes, and release the dismissal when actual progress moves forward.
        let hiddenAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T19:00:00Z"))
        let dismissal = ContinueDismissal(record, now: hiddenAt)
        XCTAssertTrue(dismissal.valid)
        XCTAssertTrue(dismissal.hides(record))
        XCTAssertFalse(dismissal.hasNewPlayback(ResumeSnapshot(positionMs: 120_000, durationMs: 3_600_000, timestampMs: 1, exiting: true)))
        XCTAssertTrue(dismissal.hasNewPlayback(ResumeSnapshot(positionMs: 0, durationMs: 3_600_000, timestampMs: UInt64(hiddenAt.timeIntervalSince1970 * 1_000) + 1, exiting: true)), "New local playback releases the dismissal even when cloud sync is unavailable")
        var changed = raw.objectValue
        var state = changed["state"]!.objectValue
        state["timeOffset"] = .integer(180_000); changed["state"] = .object(state)
        XCTAssertFalse(dismissal.hides(LibraryRecord(raw: .object(changed))))
        state["timeOffset"] = .integer(120_000); state["video_id"] = .string("show:1:1"); changed["state"] = .object(state)
        XCTAssertFalse(dismissal.hides(LibraryRecord(raw: .object(changed))))
        let seasonOne = ContinueDismissal(LibraryRecord(raw: .object(changed)), now: hiddenAt)
        XCTAssertTrue(seasonOne.hides(record), "Stale progress from an earlier season must stay hidden")
        changed = raw.objectValue; changed["_mtime"] = .string("2026-10-05T20:00:00Z")
        XCTAssertFalse(dismissal.hides(LibraryRecord(raw: .object(changed))))
        XCTAssertEqual(record.playbackCaption, "T0 · E1 · 58 min restantes")

        let older = LibraryRecord(raw: .object(["_id": .string("older"), "type": .string("movie"), "name": .string("Árbol"), "releaseInfo": .string("1999"), "_ctime": .string("2024-01-01T00:00:00Z")]))
        let newer = LibraryRecord(raw: .object(["_id": .string("newer"), "type": .string("movie"), "name": .string("Zeta"), "releaseInfo": .string("2025"), "_ctime": .string("2025-01-01T00:00:00Z")]))
        var display = LibraryDisplay()
        XCTAssertEqual(LibraryListing.select([older, newer, record], display: display, query: " arbol ").map(\.id), ["older"])
        display.kind = .movie; display.sort = .year
        XCTAssertEqual(LibraryListing.select([older, newer, record], display: display, query: "").map(\.id), ["newer", "older"])
        display.sort = .title
        XCTAssertEqual(LibraryListing.select([newer, older], display: display, query: "").map(\.id), ["older", "newer"])
        display.sort = .recent
        XCTAssertEqual(LibraryListing.select([older, newer], display: display, query: "").map(\.id), ["newer", "older"])

        // Rolling windows stay intact across midnight, a new month and year.
        let groupingDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-02T12:00:00Z"))
        let dates = ["2026-01-01T13:00:00Z", "2026-01-01T12:00:00Z", "2025-12-27T12:00:00Z", "2025-12-26T12:00:00Z", "2025-12-04T12:00:00Z", "2025-12-03T12:00:00Z"]
        let datedRecords = dates.enumerated().map { index, date in
            LibraryRecord(raw: .object(["_id": .string("dated-\(index)"), "type": .string("movie"), "name": .string("Movie"), "_ctime": .string(date)]))
        }
        let dateGroups = LibraryListing.groups(datedRecords, display: display, now: groupingDate)
        XCTAssertEqual(dateGroups.map(\.title), ["Hoy", "Esta semana", "Este mes", "2025"])
        XCTAssertEqual(dateGroups.map { $0.items.map(\.id) }, [["dated-0"], ["dated-1", "dated-2"], ["dated-3", "dated-4"], ["dated-5"]])
        display.grouped = false
        XCTAssertEqual(LibraryListing.groups(datedRecords, display: display, now: groupingDate).first?.items.map(\.id), datedRecords.map(\.id))

        // Switching links keeps the live position even inside the ordinary
        // completed-video window, and cannot move it to another account/episode.
        let target = ResumeTarget(id: "show", season: 0, episode: 1, videoId: "show:0:1")
        let continuation = SourceContinuation(target: target, owner: "first", snapshot: ResumeSnapshot(positionMs: 3_590_000, durationMs: 3_600_000, timestampMs: 1, exiting: true), advanceStartedAtMs: 0)
        XCTAssertEqual(continuation.position(for: target, owner: "first"), 3_590_000)
        XCTAssertTrue(EpisodeSequence.permitsAutomaticAdvance(duration: 3_600, startedAtMs: try XCTUnwrap(continuation.advanceStartedAtMs), ended: true, hasError: false), "Changing source near the end must preserve the original automatic episode eligibility")
        XCTAssertNil(continuation.position(for: target, owner: "second"))
        XCTAssertNil(continuation.position(for: ResumeTarget(id: "show", season: 1, episode: 1, videoId: "show:1:1"), owner: "first"))
        XCTAssertNil(continuation.position(for: ResumeTarget(id: "other", season: 0, episode: 1, videoId: "show:0:1"), owner: "first"))
        XCTAssertNil(SourceContinuation(target: target, owner: "first", snapshot: ResumeSnapshot(positionMs: .nan, durationMs: 0, timestampMs: 1, exiting: true)).position(for: target, owner: "first"))
    }
    func testDesktopWatchedBitfieldUsesCanonicalEpisodeOrderAndAnchor() throws {
        let episodes = [Episode(id: "show:1:3", season: 1, episode: 3), Episode(id: "show:1:1", season: 1, episode: 1), Episode(id: "show:1:2", season: 1, episode: 2)]
        // Independent RFC1950 fixture: zlib-compressed byte 0b00000101.
        let field = "show:1:3:3:eJxjBQAABgAG"
        XCTAssertEqual(try WatchedCodec.decode(field, videos: episodes), ["1:1", "1:3"])
        XCTAssertEqual(try WatchedCodec.encode(["1:1", "1:3"], videos: episodes), field)
        let expanded = episodes + [Episode(id: "show:0:1", season: 0, episode: 1)]
        XCTAssertEqual(try WatchedCodec.decode(field, videos: expanded), ["1:1", "1:3"])
        XCTAssertThrowsError(try WatchedCodec.decode("show:1:3:3:broken", videos: episodes))
    }
    func testOptionalAddonFieldsDoNotDiscardTheCatalog() throws {
        let row: JSONValue = .object(["id": .string("tt0816692"), "type": .null, "name": .string("Interstellar"), "imdbRating": .number(8.7), "genres": .null, "videos": .array([.object(["id": .string("episode:1"), "season": .null, "episode": .integer(1), "name": .null])])])
        let media = try XCTUnwrap(Media.parse(row, kind: "movie"))
        XCTAssertEqual(media.type, "movie")
        XCTAssertEqual(media.imdbRating, "8.7")
        XCTAssertEqual(media.videos?.first?.id, "episode:1")
        XCTAssertNil(Media.parse(.object(["id": .null, "name": .string("Invalid")]), kind: "movie"))

        let metadata = Data(#"{"id":"tt0816692","name":"Interstellar","writer":[" Jonathan Nolan ",null,"Christopher Nolan","Jonathan Nolan",""],"trailerStreams":[{"ytId":"LY19rHKAaAg","title":"Official trailer"},{"ytId":"https://example.invalid/video"},{"ytId":null}],"trailers":[{"source":"LY19rHKAaAg","type":"Trailer"},{"source":"R8teZZ-loaI","type":"Trailer"},{"source":"bad"}]}"#.utf8)
        let parsed = try XCTUnwrap(Media.parse(try JSONDecoder().decode(JSONValue.self, from: metadata), kind: "movie"))
        XCTAssertEqual(parsed.writer, ["Jonathan Nolan", "Christopher Nolan"])
        XCTAssertEqual(parsed.details?.trailers.map(\.id), ["LY19rHKAaAg", "R8teZZ-loaI"], "Legacy and stream-style addon trailers must coexist without duplicate cards")
        XCTAssertEqual(parsed.details?.trailers.first?.title, "Official trailer")
        XCTAssertEqual(parsed.details?.trailers.last?.url, "https://www.youtube.com/watch?v=R8teZZ-loaI")
        XCTAssertEqual(try JSONDecoder().decode(Media.self, from: JSONEncoder().encode(parsed)).writer, parsed.writer)
        let oldSaved = try JSONDecoder().decode(Media.self, from: Data(#"{"id":"saved","type":"movie","name":"Saved before writer support"}"#.utf8))
        XCTAssertNil(oldSaved.writer, "Previously saved library records must remain readable")

        var richer = MediaDetails()
        richer.status = "Released"
        richer.trailers = [try XCTUnwrap(MediaDetails.Trailer.youtube("LY19rHKAaAg", title: "Localized trailer"))]
        let combined = richer.includingTrailers(from: parsed.details)
        XCTAssertEqual(combined.status, "Released")
        XCTAssertEqual(combined.trailers.map(\.id), ["LY19rHKAaAg", "R8teZZ-loaI"], "Metadata enrichment must keep unique addon trailers")
        XCTAssertEqual(combined.trailers.first?.title, "Localized trailer")
    }
    func testPartialCatalogRefreshKeepsFailedRowsButClearsSuccessfulEmptyAndRemovedRows() {
        let addon = Addon(manifest: .object(["id": .string("test-only")]), transportUrl: "https://example.invalid/manifest.json", enabled: true)
        func plan(_ key: String) -> RequestPlan { RequestPlan(key: key, url: "https://example.invalid/catalog/\(key).json", title: key, kind: "movie", addon: addon, addonPriority: 0, timeoutMs: 8_000, catalog: nil) }
        let first = plan("first"), failed = plan("failed"), removed = plan("removed")
        let previous = [first, failed, removed].map { CatalogRow(plan: $0, metas: [Media(id: $0.key, type: "movie", name: $0.title)]) }
        let merged = HarborService.mergeCatalogs(plans: [first, failed], received: [CatalogRow(plan: first, metas: [])], previous: previous)
        XCTAssertEqual(merged.map(\.id), ["first", "failed"])
        XCTAssertTrue(merged[0].metas.isEmpty)
        XCTAssertEqual(merged[1].metas.first?.id, "failed")
        XCTAssertTrue(HarborService.mergeCatalogs(plans: [], received: [], previous: previous).isEmpty)
    }
    @MainActor func testOldSavedOptionsSurviveAddingAspectControls() throws {
        let name = "harbor-migration-\(UUID().uuidString)"
        let storage = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { storage.removePersistentDomain(forName: name) }
        storage.set(try JSONSerialization.data(withJSONObject: ["speed": 1.5, "subtitleSize": 48, "fit": "classic"]), forKey: "iphone.player-options.v1")
        let preferences = PlaybackPreferences(storage: storage)
        XCTAssertEqual(preferences.options.speed, 1.5)
        XCTAssertEqual(preferences.options.subtitleSize, 48)
        XCTAssertEqual(preferences.options.fit, .classic)
        XCTAssertEqual(preferences.options.zoom, 0)
        XCTAssertTrue(preferences.options.autoPlayNextEpisode)
        XCTAssertEqual(preferences.options.nextEpisodeLeadSeconds, -1)
        XCTAssertTrue(preferences.options.resumeAfterInterruption)
        XCTAssertFalse(preferences.options.resumeOnForeground)
    }
    func testEpisodeAdvanceCrossesSeasonsKeepsSpecialsSeparateAndExcludesUnairedEpisodes() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z"))
        let videos = [Episode(id: "show:2:1", season: 2, episode: 1), Episode(id: "show:1:2", season: 1, episode: 2), Episode(id: "show:0:1", season: 0, episode: 1), Episode(id: "show:1:1", season: 1, episode: 1), Episode(id: "duplicate:1:2", season: 1, episode: 2), Episode(id: "show:2:2", season: 2, episode: 2, released: "2026-12-01T12:00:00Z")]
        let adjacent = EpisodeSequence.adjacent(videos, current: ResumeTarget(id: "show", season: 1, episode: 2, videoId: "show:1:2"), now: now)
        XCTAssertEqual(adjacent.previous?.id, "show:1:1")
        XCTAssertEqual(adjacent.next?.id, "show:2:1")
        XCTAssertNil(EpisodeSequence.adjacent(videos, current: ResumeTarget(id: "show", season: 2, episode: 1), now: now).next)
        let special = EpisodeSequence.adjacent(videos, current: ResumeTarget(id: "show", videoId: "show:0:1"), now: now)
        XCTAssertNil(special.previous)
        XCTAssertNil(special.next)
        XCTAssertNil(EpisodeSequence.adjacent(videos, current: ResumeTarget(id: "show", videoId: "missing"), now: now).next)
        XCTAssertEqual(EpisodeSequence.leadSeconds(setting: -1, duration: 600), 24)
        XCTAssertEqual(EpisodeSequence.leadSeconds(setting: -1, duration: 3_600), 45)
        XCTAssertEqual(EpisodeSequence.leadSeconds(setting: 0, duration: 600), 0)
        XCTAssertTrue(EpisodeSequence.permitsAutomaticAdvance(duration: 1_800, startedAtMs: 0, ended: true, hasError: false))
        XCTAssertFalse(EpisodeSequence.permitsAutomaticAdvance(duration: 90, startedAtMs: 0, ended: true, hasError: false))
        XCTAssertFalse(EpisodeSequence.permitsAutomaticAdvance(duration: 1_800, startedAtMs: 1_500_000, ended: true, hasError: false))
        XCTAssertFalse(EpisodeSequence.permitsAutomaticAdvance(duration: 1_800, startedAtMs: 0, ended: false, hasError: false))
        XCTAssertFalse(EpisodeSequence.permitsAutomaticAdvance(duration: 1_800, startedAtMs: 0, ended: true, hasError: true))
    }
}
