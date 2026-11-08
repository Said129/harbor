import XCTest
@testable import Harbor

/// Desktop's "Keep the next episode visible": the next-up pick (`NextUpEpisode`) and the spoiler mask it feeds
/// through `UISettingsPolicy.spoilerMask`. Pure rules only, no network and no UI.
final class WireSpoilerTests: XCTestCase {
    private func episodes(_ numbers: [Int], season: Int = 1) -> [Episode] {
        numbers.map { Episode(id: "s\(season)e\($0)", season: season, episode: $0) }
    }

    private func nextUp(_ list: [Episode], watched: Set<String>) -> String? {
        NextUpEpisode.routingKey(in: list) { watched.contains($0.watchedKey) }
    }

    /// The mask the episode row computes: `watched` is the episode's `watchedKey` set, and next-up is decided over `list`.
    private func mask(_ episode: Episode, in list: [Episode], watched: Set<String>, hideSpoilers: Bool = true, skipNext: Bool = true) -> UISettingsPolicy.SpoilerMask {
        UISettingsPolicy.spoilerMask(hideSpoilers: hideSpoilers, blurThumbnails: true, hideTitles: true, hideDescriptions: true,
                                     skipNext: skipNext, watched: watched.contains(episode.watchedKey),
                                     isNextUp: nextUp(list, watched: watched) == episode.routingKey)
    }

    private let blurred = UISettingsPolicy.SpoilerMask(thumbnail: true, title: true, description: true)
    private let clear = UISettingsPolicy.SpoilerMask(thumbnail: false, title: false, description: false)

    // MARK: Next-up pick

    func testNothingWatchedMakesTheFirstEpisodeNextUp() {
        let list = episodes([1, 2, 3])
        XCTAssertEqual(nextUp(list, watched: []), "s1e1")
    }

    func testNextUpIsTheFirstUnwatchedEpisode() {
        let list = episodes([1, 2, 3, 4])
        XCTAssertEqual(nextUp(list, watched: ["1:1", "1:2"]), "s1e3")
        XCTAssertEqual(nextUp(list, watched: ["1:1", "1:3"]), "s1e2", "a gap earlier in the list still counts as next to watch")
    }

    func testAllWatchedHasNoNextUp() {
        let list = episodes([1, 2, 3])
        XCTAssertNil(nextUp(list, watched: ["1:1", "1:2", "1:3"]))
    }

    func testEmptyListHasNoNextUp() {
        XCTAssertNil(nextUp([], watched: []))
    }

    func testSpecialsAreScannedLikeAnyOtherEpisodeInTheListShown() {
        let specials = episodes([1, 2], season: 0)
        let regular = episodes([1], season: 1)
        XCTAssertEqual(nextUp(specials + regular, watched: []), "s0e1")
        XCTAssertEqual(nextUp(specials + regular, watched: ["0:1"]), "s0e2")
        XCTAssertNil(nextUp(specials, watched: ["0:1", "0:2"]), "a shown list that is all watched has no next-up")
        XCTAssertEqual(nextUp(regular, watched: []), "s1e1", "the season on screen is the list that is scanned")
    }

    func testOutOfOrderListUsesListOrderNotEpisodeNumber() {
        let list = episodes([3, 1, 2])
        XCTAssertEqual(nextUp(list, watched: []), "s1e3")
        XCTAssertEqual(nextUp(list, watched: ["1:3"]), "s1e1")
        XCTAssertEqual(nextUp(list, watched: ["1:3", "1:1"]), "s1e2")
    }

    // MARK: Spoiler mask, on and off

    func testSkipNextOnKeepsTheNextEpisodeClearAndBlursTheOnesAfterIt() {
        let list = episodes([1, 2, 3])
        let watched: Set<String> = ["1:1"]
        XCTAssertEqual(mask(episodes([1])[0], in: list, watched: watched), clear, "watched episodes stay clear")
        XCTAssertEqual(mask(episodes([2])[0], in: list, watched: watched), clear, "the next episode to watch stays clear")
        XCTAssertEqual(mask(episodes([3])[0], in: list, watched: watched), blurred, "later unwatched episodes stay blurred")
    }

    func testSkipNextOffBlursTheNextEpisodeToo() {
        let list = episodes([1, 2, 3])
        let watched: Set<String> = ["1:1"]
        XCTAssertEqual(mask(episodes([2])[0], in: list, watched: watched, skipNext: false), blurred)
        XCTAssertEqual(mask(episodes([3])[0], in: list, watched: watched, skipNext: false), blurred)
        XCTAssertEqual(mask(episodes([1])[0], in: list, watched: watched, skipNext: false), clear, "watched stays clear with skip off")
    }

    func testSpoilersOffClearsEveryEpisode() {
        let list = episodes([1, 2, 3])
        for episode in list {
            XCTAssertEqual(mask(episode, in: list, watched: [], hideSpoilers: false), clear)
            XCTAssertEqual(mask(episode, in: list, watched: [], hideSpoilers: false, skipNext: false), clear)
        }
    }

    func testAllWatchedShowsNothingBlurred() {
        let list = episodes([1, 2])
        let watched: Set<String> = ["1:1", "1:2"]
        for episode in list {
            XCTAssertEqual(mask(episode, in: list, watched: watched, skipNext: false), clear)
        }
    }
}
