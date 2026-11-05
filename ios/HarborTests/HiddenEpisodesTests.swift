import XCTest
@testable import Harbor

/// Desktop's "Hide and skip episodes" (`lib/hidden-episodes.ts`, `use-episode-navigation.ts`).
final class HiddenEpisodesTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "owned.hidden.episodes." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testEpisodesAreHiddenAndShownPerShowSeasonAndNumber() {
        let defaults = isolatedDefaults()
        XCTAssertEqual(HiddenEpisodes.key("tt1", season: 2, episode: 5), "tt1|2|5")
        XCTAssertFalse(HiddenEpisodes.isHidden("tt1", season: 2, episode: 5, defaults: defaults))
        HiddenEpisodes.set(true, metaID: "tt1", season: 2, episode: 5, defaults: defaults)
        HiddenEpisodes.set(true, metaID: "tt1", season: 2, episode: 5, defaults: defaults)
        HiddenEpisodes.set(true, metaID: "tt1", season: 0, episode: 1, defaults: defaults)
        HiddenEpisodes.set(true, metaID: "kitsu:7", season: 1, episode: 3, defaults: defaults)
        XCTAssertTrue(HiddenEpisodes.isHidden("tt1", season: 2, episode: 5, defaults: defaults))
        XCTAssertFalse(HiddenEpisodes.isHidden("tt1", season: 2, episode: 6, defaults: defaults))
        XCTAssertFalse(HiddenEpisodes.isHidden("tt2", season: 2, episode: 5, defaults: defaults))
        XCTAssertEqual(HiddenEpisodes.coordinates(for: "tt1", defaults: defaults), ["2:5", "0:1"])
        XCTAssertEqual(HiddenEpisodes.coordinates(for: "kitsu:7", defaults: defaults), ["1:3"])
        HiddenEpisodes.set(false, metaID: "tt1", season: 2, episode: 5, defaults: defaults)
        HiddenEpisodes.set(false, metaID: "tt1", season: 9, episode: 9, defaults: defaults)
        XCTAssertEqual(HiddenEpisodes.coordinates(for: "tt1", defaults: defaults), ["0:1"])
        HiddenEpisodes.clear(metaID: "tt1", defaults: defaults)
        XCTAssertTrue(HiddenEpisodes.coordinates(for: "tt1", defaults: defaults).isEmpty)
        XCTAssertEqual(HiddenEpisodes.coordinates(for: "kitsu:7", defaults: defaults), ["1:3"], "Clearing one show leaves the others")
    }

    func testUpNextStepsOverHiddenEpisodesButNotOverTheOneBeingPlayed() {
        let videos = (1...5).map { Episode(id: "show:1:\($0)", season: 1, episode: $0) }
        let hidden: Set<String> = [HiddenEpisodes.key("show", season: 1, episode: 3), HiddenEpisodes.key("show", season: 1, episode: 4)]
        func target(_ number: Int) -> ResumeTarget { ResumeTarget(id: "show", season: 1, episode: number, videoId: "show:1:\(number)") }
        XCTAssertEqual(EpisodeSequence.adjacent(videos, current: target(2)).next?.episode, 3, "Nothing is skipped while hiding is off")
        let skipping = EpisodeSequence.adjacent(videos, current: target(2), hidden: hidden)
        XCTAssertEqual(skipping.next?.episode, 5, "Episodes 3 and 4 are skipped"); XCTAssertEqual(skipping.previous?.episode, 1)
        XCTAssertEqual(EpisodeSequence.adjacent(videos, current: target(5), hidden: hidden).previous?.episode, 2)
        let playingHidden = EpisodeSequence.adjacent(videos, current: target(3), hidden: hidden)
        XCTAssertEqual(playingHidden.previous?.episode, 2, "A hidden episode that is playing still has neighbours")
        XCTAssertEqual(playingHidden.next?.episode, 5)
        XCTAssertNil(EpisodeSequence.adjacent(videos, current: target(5), hidden: [HiddenEpisodes.key("show", season: 1, episode: 5)]).next)
        let other = Set([HiddenEpisodes.key("another", season: 1, episode: 3)])
        XCTAssertEqual(EpisodeSequence.adjacent(videos, current: target(2), hidden: other).next?.episode, 3, "Another show's hidden episodes do not count")
    }

    func testHiddenEpisodesOfAMultiSourceAnimeUseTheirOwnEntry() {
        var first = Episode(id: "kitsu:1:2", season: 1, episode: 2); first.sourceMetaID = "kitsu:1"
        var second = Episode(id: "kitsu:2:1", season: 1, episode: 1); second.sourceMetaID = "kitsu:2"
        var third = Episode(id: "kitsu:2:2", season: 1, episode: 2); third.sourceMetaID = "kitsu:2"
        let hidden: Set<String> = [HiddenEpisodes.key("kitsu:2", season: 1, episode: 1)]
        let adjacent = EpisodeSequence.adjacent([first, second, third], current: ResumeTarget(id: "kitsu:1", season: 1, episode: 2, videoId: "kitsu:1:2"), hidden: hidden)
        XCTAssertNotEqual(adjacent.next?.id, "kitsu:2:1", "The hidden episode of the second entry is skipped")
    }
}
