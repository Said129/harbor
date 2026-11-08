import XCTest
@testable import Harbor

/// Desktop's episode row progress (`src/lib/episode-progress.ts`, `series-episode-row.tsx`), the Trakt related
/// fallback (`src/lib/providers/trakt-related.ts`, `views/detail.tsx`) and the shared-crew rules
/// (`views/detail/shared-crew-line.tsx`, `use-graph-reasons.ts`). No network and no UI.
final class R24DetailTests: XCTestCase {
    /// Replaces each `{name}` placeholder, as the English text of Desktop's `t()` would read.
    private func english(_ template: String, _ variables: [String: String]) -> String {
        variables.reduce(template) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    // MARK: Episode progress

    func testRelativeWatchedUsesDesktopWords() {
        let nowMs = 1_700_000_000_000.0
        func ago(_ seconds: Double) -> UInt64 { UInt64(nowMs - seconds * 1000) }
        func text(_ startedAt: UInt64) -> String {
            EpisodeRowProgress.relativeWatched(startedAt, nowMs: nowMs, text: english)
        }
        XCTAssertEqual(text(ago(30)), "just now")
        XCTAssertEqual(text(ago(5 * 60)), "5m ago")
        XCTAssertEqual(text(ago(3 * 3_600)), "3h ago")
        XCTAssertEqual(text(ago(86_400)), "yesterday")
        XCTAssertEqual(text(ago(3 * 86_400)), "3 days ago")
        XCTAssertEqual(text(ago(10 * 86_400)), "last week")
        XCTAssertEqual(text(ago(20 * 86_400)), "2 weeks ago")
        XCTAssertEqual(text(ago(45 * 86_400)), "last month")
        XCTAssertEqual(text(ago(90 * 86_400)), "3 months ago")
        XCTAssertEqual(text(ago(400 * 86_400)), "last year")
        XCTAssertEqual(text(ago(800 * 86_400)), "2 years ago")
        XCTAssertEqual(text(0), "", "no time, no text")
        XCTAssertEqual(EpisodeRowProgress.relativeWatched(ago(-500), nowMs: nowMs, text: english), "just now", "a time after now is just now")
    }

    func testProgressUsesSavedPercentOfTheRuntime() {
        let forty = 40.0
        let half = EpisodeRowProgress.progress(entry: ResumeEntry(ms: 0, t: 1_000, pct: 0.5), runtimeMinutes: forty, done: false)
        XCTAssertEqual(half, EpisodeRowProgress.Value(ratio: 0.5, watched: false, startedAt: 1_000))

        let almost = EpisodeRowProgress.progress(entry: ResumeEntry(ms: 0, t: 1_000, pct: 0.9), runtimeMinutes: forty, done: false)
        XCTAssertEqual(almost.watched, true, "at least 85 percent counts as watched")

        let fromMs = EpisodeRowProgress.progress(entry: ResumeEntry(ms: 1_200_000, t: 5), runtimeMinutes: forty, done: false)
        XCTAssertEqual(fromMs.ratio, 0.5, accuracy: 1e-9, "without a percentage the position in milliseconds is used")

        let clamped = EpisodeRowProgress.progress(entry: ResumeEntry(ms: 0, t: 5, pct: 1.5), runtimeMinutes: forty, done: false)
        XCTAssertEqual(clamped.ratio, 1)

        let noRuntime = EpisodeRowProgress.progress(entry: ResumeEntry(ms: 0, t: 5, pct: 0.5), runtimeMinutes: nil, done: false)
        XCTAssertEqual(noRuntime.ratio, 0, "a percentage needs a runtime")
        XCTAssertEqual(noRuntime.startedAt, 5)
    }

    func testProgressIsFullWhenDone() {
        XCTAssertEqual(EpisodeRowProgress.progress(entry: nil, runtimeMinutes: nil, done: true),
                       EpisodeRowProgress.Value(ratio: 1, watched: true, startedAt: 0))
        XCTAssertEqual(EpisodeRowProgress.progress(entry: nil, runtimeMinutes: 40, done: false),
                       EpisodeRowProgress.Value(ratio: 0, watched: false, startedAt: 0))
    }

    func testStatusLineAndBarFraction() {
        let watched = EpisodeRowProgress.Value(ratio: 1, watched: true, startedAt: 1)
        XCTAssertEqual(EpisodeRowProgress.statusText(watched, ago: "5m ago", text: english), "Watched 5m ago")

        let started = EpisodeRowProgress.Value(ratio: 0.4, watched: false, startedAt: 1)
        XCTAssertEqual(EpisodeRowProgress.statusText(started, ago: "2h ago", text: english), "40% watched · 2h ago")

        let barelyStarted = EpisodeRowProgress.Value(ratio: 0.005, watched: false, startedAt: 1)
        XCTAssertNil(EpisodeRowProgress.statusText(barelyStarted, ago: "2h ago", text: english), "under 1 percent shows no line")
        XCTAssertNil(EpisodeRowProgress.statusText(started, ago: "", text: english), "no time, no line")

        XCTAssertEqual(EpisodeRowProgress.barFraction(0.005), 0.02, accuracy: 1e-9, "the bar keeps a 2 percent sliver")
        XCTAssertEqual(EpisodeRowProgress.barFraction(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(EpisodeRowProgress.barFraction(2), 1)
    }

    // MARK: Trakt related titles

    func testTraktRelatedPathAndRequest() throws {
        let movie = TraktRelatedTarget(imdbId: "tt0111161", show: false)
        XCTAssertEqual(movie.path, "/movies/tt0111161/related?extended=full&limit=20")
        XCTAssertEqual(TraktRelatedTarget(imdbId: "tt0111161", show: true).path, "/shows/tt0111161/related?extended=full&limit=20")
        XCTAssertTrue(movie.valid)
        XCTAssertFalse(TraktRelatedTarget(imdbId: "12345", show: false).valid)

        let request = try TraktEndpoint.related(movie).request()
        XCTAssertEqual(request.url?.absoluteString, "https://api.trakt.tv/movies/tt0111161/related?extended=full&limit=20")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "Desktop reads related titles without an account")
        XCTAssertThrowsError(try TraktEndpoint.related(TraktRelatedTarget(imdbId: "nope", show: false)).request())
    }

    func testTraktRowsBecomeTitlesWithoutDuplicatesOrSeed() throws {
        let rows = try json("""
        [
          {"title":" Alpha ","year":1999,"overview":"o","rating":7.46,"genres":["Drama"],"ids":{"imdb":"tt0000001","tmdb":1},
           "images":{"poster":["walter.example/p.jpg"],"fanart":["https://img.example/f.jpg"]}},
          {"title":"Seed","ids":{"imdb":"tt0111161"}},
          {"title":"No id","ids":{"tmdb":3}},
          {"title":"Alpha again","ids":{"imdb":"tt0000001"}},
          {"title":"Beta","ids":{"imdb":"tt0000002"}}
        ]
        """)
        let metas = TraktRelatedTitles.metas(rows, show: false, excluding: "tt0111161")
        XCTAssertEqual(metas.map(\.id), ["tt0000001", "tt0000002"])
        let alpha = metas[0]
        XCTAssertEqual(alpha.name, "Alpha")
        XCTAssertEqual(alpha.type, "movie")
        XCTAssertEqual(alpha.releaseInfo, "1999")
        XCTAssertEqual(alpha.imdbRating, "7.5")
        XCTAssertEqual(alpha.poster, "https://walter.example/p.jpg")
        XCTAssertEqual(alpha.background, "https://img.example/f.jpg")
        XCTAssertEqual(alpha.genres, ["Drama"])
        XCTAssertEqual(TraktRelatedTitles.metas(rows, show: true, excluding: "tt0111161").first?.type, "series")
    }

    func testMergeUsesTheFallbackOnlyWithoutPrimaryTitles() {
        let a = Media(id: "tt0000001", type: "movie", name: "A")
        let b = Media(id: "tt0000002", type: "movie", name: "B")
        XCTAssertEqual(TraktRelatedTitles.merge(primary: [], fallback: [a, b], taken: ["tt0000002"]).map(\.id), ["tt0000001"])
        XCTAssertEqual(TraktRelatedTitles.merge(primary: [b], fallback: [a], taken: []).map(\.id), ["tt0000002"], "the primary list wins")
        XCTAssertEqual(TraktRelatedTitles.merge(primary: [], fallback: [], taken: []), [])
    }

    // MARK: Shared crew

    func testSharedCrewKeepsThreeOrMoreAndWordsTheLine() {
        let films = [
            SharedCrewFilm(metaId: "tt0000001", name: "Two", shared: 2, who: ["A", "B"]),
            SharedCrewFilm(metaId: "tt0000002", name: "Three", shared: 3, who: ["A", "B", "C"]),
        ]
        XCTAssertEqual(SharedCrewRules.films(films).map(\.metaId), ["tt0000002"])
        XCTAssertNil(SharedCrewRules.line(count: 0, text: english))
        XCTAssertEqual(SharedCrewRules.line(count: 1, text: english), "Shares crew with 1 other film")
        XCTAssertEqual(SharedCrewRules.line(count: 4, text: english), "Shares crew with 4 other films")
        XCTAssertEqual(SharedCrewRules.reasonLabel(shared: 3, text: english), "Shares 3 crew")
        XCTAssertEqual(SharedCrewRules.rank(shared: 3), 103)
    }

    func testOrderingByReasonIsStableForEqualRanks() {
        let ids = ["a", "b", "c", "d"]
        XCTAssertEqual(SharedCrewRules.ordered(ids, id: { $0 }, ranks: ["b": 5, "d": 5, "c": 9]), ["c", "b", "d", "a"])
        XCTAssertEqual(SharedCrewRules.ordered(ids, id: { $0 }, ranks: [:]), ids, "no reasons keeps the order")
        XCTAssertEqual(SharedCrewRules.ordered(["a"], id: { $0 }, ranks: ["a": 1]), ["a"])
    }
}
