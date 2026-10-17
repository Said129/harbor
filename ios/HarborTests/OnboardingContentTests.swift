import XCTest
@testable import Harbor

final class OnboardingContentTests: XCTestCase {
    func testTasteMixKeepsDiverseSourcesRealCoversAndFortyUniqueIDs() {
        func media(_ id: String, poster: Bool = true) -> Media {
            var value = Media(id: id, type: "movie", name: id)
            value.poster = poster ? "https://example.invalid/\(id).jpg" : nil; return value
        }
        let movies = (0..<60).map { media("movie-\($0)") }
        let series = (0..<30).map { media("series-\($0)") }
        let genres = [media("movie-0"), media("missing-cover", poster: false), media("genre-1")]
        let values = OnboardingContent.mix([movies, series, genres])
        XCTAssertEqual(values.count, 40); XCTAssertEqual(Set(values.map(\.id)).count, 40)
        XCTAssertEqual(Array(values.prefix(4).map(\.id)), ["movie-0", "series-0", "movie-1", "series-1"])
        XCTAssertTrue(values.contains { $0.id == "genre-1" }); XCTAssertFalse(values.contains { $0.id == "missing-cover" })
        XCTAssertTrue(OnboardingContent.mix([]).isEmpty)
    }
    func testSelectionLimitAllowsDeselectingAndNeverAccumulatesDuplicateIDs() {
        var selection = OnboardingTastePicks()
        let titles = (0..<6).map { Media(id: String($0), type: "movie", name: "Title \($0)") }
        for title in titles { selection.toggle(title) }
        XCTAssertEqual(selection.values.map(\.id), ["0", "1", "2", "3", "4"])
        selection.toggle(titles[1]); selection.toggle(titles[5])
        XCTAssertEqual(selection.values.map(\.id), ["0", "2", "3", "4", "5"])
        selection.reset(); XCTAssertTrue(selection.values.isEmpty)
    }
    func testAllTenStepsHaveSafeBoundariesAndOnlyOptionalConfigurationSkips() {
        XCTAssertEqual(OnboardingStep.allCases.map(\.rawValue), ["splash", "language", "welcome", "layout", "tmdb", "stremio", "streaming", "subtitles", "taste", "done"])
        XCTAssertEqual(OnboardingStep.splash.previous, .splash); XCTAssertEqual(OnboardingStep.done.next, .done)
        XCTAssertEqual(OnboardingStep.allCases.filter(\.canSkip), [.tmdb, .stremio, .streaming, .subtitles, .taste])
    }
    func testOriginalLanguageGreetingsAndDirectionAreAvailableForEveryChoice() {
        XCTAssertEqual(InterfaceLanguage.all.count, 16)
        XCTAssertTrue(InterfaceLanguage.all.allSatisfy { $0.label?.isEmpty == false && $0.greeting?.isEmpty == false && $0.rtl != nil })
        XCTAssertEqual(InterfaceLanguage.all.filter { $0.rtl == true }.map(\.code), ["ar"])
        XCTAssertEqual(InterfaceLanguage.all.first { $0.code == "ja" }?.greeting, "こんにちは")
    }
    @MainActor func testTasteCommitPreservesExistingUpvotesAndSkipLeavesStoreUntouched() throws {
        let owner = "onboarding-test-" + UUID().uuidString
        let key = DiscoveryPreferences.key(owner)
        defer { try? KeychainStore().remove(key) }
        let first = Media(id: "tt0000001", type: "movie", name: "First"), second = Media(id: "tt0000002", type: "series", name: "Second")
        let preferences = DiscoveryPreferences(owner: owner)
        XCTAssertTrue(preferences.ready); XCTAssertTrue(preferences.toggle(.up, for: first, now: Date(timeIntervalSince1970: 100)))
        let previous = try XCTUnwrap(preferences.votes[first.id])
        var picks = OnboardingTastePicks(); picks.toggle(second)
        XCTAssertNil(DiscoveryPreferences(owner: owner).vote(for: second), "Selecting a title alone must not persist a vote")
        XCTAssertTrue(preferences.seedTaste([first, second], now: Date(timeIntervalSince1970: 200)))
        let restored = DiscoveryPreferences(owner: owner)
        XCTAssertEqual(restored.votes[first.id], previous); XCTAssertEqual(restored.vote(for: second), .up)
    }
}
