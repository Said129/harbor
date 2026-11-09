import XCTest
@testable import Harbor

/// The poster ribbon follows Home's Top 10 membership, with Desktop's id-first/name-fallback lookup.
final class TopTenRibbonIndexTests: XCTestCase {
    @MainActor
    func testHomeTopTenExcludesHeroCapsAndResetsOnProfileActivation() {
        let index = TopTenRibbonIndexStore.shared
        let firstProfile = UUID()
        let secondProfile = UUID()
        var ranked = (1...21).map { Media(id: "tt\($0)", type: "movie", name: "Title \($0)") }
        ranked[2].name = "Amélie & the Wolf"
        let heroSlides = Array(ranked.prefix(2))
        let topTen = HomeHeroSlides.topTen(firstRow: ranked, heroSlides: heroSlides)

        XCTAssertEqual(topTen.map(\.id), (3...12).map { "tt\($0)" }, "Take the first ten after excluding hero slides from the first twenty")
        index.replaceHomeTopTen(topTen, profileActivationID: firstProfile)

        XCTAssertFalse(index.contains(ranked[0], profileActivationID: firstProfile), "Featured slides are not in Home's Top 10 set")
        XCTAssertTrue(index.contains(ranked[2], profileActivationID: firstProfile))
        XCTAssertFalse(index.contains(ranked[12], profileActivationID: firstProfile), "Titles after rank ten do not qualify")
        XCTAssertFalse(index.contains(ranked[20], profileActivationID: firstProfile), "Only the first twenty row metas are considered")
        XCTAssertTrue(index.contains(Media(id: "catalog:alternate", type: "movie", name: "AMÉLIE the wolf"),
                                      profileActivationID: firstProfile), "Names use Desktop's lowercase ASCII alphanumeric fallback")
        XCTAssertFalse(index.contains(ranked[0], profileActivationID: secondProfile), "A different activation cannot read the old profile's rows")

        XCTAssertEqual(CardTagPolicy.bookmarkPlacement(.topStart, tagCount: 2, ribbonAtStart: true)?.topInset, 90)
        XCTAssertEqual(CardTagPolicy.bookmarkPlacement(.topEnd, tagCount: 0, ribbonAtEnd: true)?.topInset, 34)

        let nextProfileTitle = Media(id: "tt9999999", type: "movie", name: "New Profile Title")
        index.replaceHomeTopTen([nextProfileTitle], profileActivationID: secondProfile)
        XCTAssertFalse(index.contains(ranked[2], profileActivationID: secondProfile), "Switching activation retires the previous profile's Home set")
        XCTAssertFalse(index.contains(Media(id: "series:alternate", type: "series", name: "Amélie & the Wolf"),
                                       profileActivationID: secondProfile))
        XCTAssertTrue(index.contains(nextProfileTitle, profileActivationID: secondProfile))
    }
}
