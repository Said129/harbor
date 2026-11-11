import XCTest
@testable import Harbor

/// Desktop 0.9.132 Home Continue Watching: one card per anime franchise root, most recently watched copy first.
final class F1ContinueWatchingTests: XCTestCase {
    private struct Card {
        let id: String
        let root: String?
        let watched: Double
    }

    func testOnlyTheMostRecentCardOfEachFranchiseRemains() {
        let cards = [
            Card(id: "a", root: "kitsu:1", watched: 10),
            Card(id: "b", root: "kitsu:1", watched: 30),
            Card(id: "c", root: nil, watched: 20),
            Card(id: "d", root: "kitsu:2", watched: 5)
        ]
        let result = HomeContinueWatchingRules.onePerFranchise(cards, root: { $0.root }, watched: { $0.watched })
        XCTAssertEqual(result.map(\.id), ["b", "c", "d"])
    }

    func testCardsWithoutAFranchiseRootAreNeverRemoved() {
        let cards = [Card(id: "x", root: nil, watched: 1), Card(id: "y", root: nil, watched: 2)]
        let result = HomeContinueWatchingRules.onePerFranchise(cards, root: { $0.root }, watched: { $0.watched })
        XCTAssertEqual(result.map(\.id), ["x", "y"])
    }

    func testATieKeepsTheEarlierCardInContinueWatchingOrder() {
        let cards = [Card(id: "first", root: "kitsu:9", watched: 10), Card(id: "second", root: "kitsu:9", watched: 10)]
        let result = HomeContinueWatchingRules.onePerFranchise(cards, root: { $0.root }, watched: { $0.watched })
        XCTAssertEqual(result.map(\.id), ["first"])
    }
}
