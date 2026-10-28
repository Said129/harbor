import XCTest
@testable import Harbor

final class HomeEntryLanguageSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedMovieAndMangaHeroesWithAnExpandedSeasonalEntryOnAFreshGuest() async throws {
        let (binding, _) = try ContinuePrivacyInterfaceSeedTests.prepareOwnedSharedGuest()
        guard try await CustomListDisk.shared.read(owner: binding.settingsOwner) == nil,
              try KeychainStore().read("manga-shelf-" + EBookShelf.hash(binding.personalOwner), as: [MangaRecord].self) == nil,
              try KeychainStore().read("spooktober-invitation-" + EBookShelf.hash(binding.personalOwner), as: Bool.self) == nil else {
            XCTFail("Refuse configured lists, Manga or invitation state"); throw HarborError(code: "owned-seed-safety")
        }
        XCTAssertTrue(SpooktoberSeason.available(Date()), "This ordinary seasonal interface gate runs during the actual source season")
        let book = try await OwnedHomeMangaFixture.create(owner: binding.personalOwner)
        let shelf = MangaShelf(owner: binding.personalOwner); try shelf.save(MangaRecord(book: book))
        let lists = CustomListStore(owner: binding.settingsOwner); await lists.load()
        await lists.apply(.create("Owned movie hero", "", id: "owned-hero-movie"))
        await lists.apply(.add("owned-hero-movie", .object(["id": .string("owned-entry:movie"), "type": .string("movie"),
            "name": .string("Owned hero film"), "poster": .string("http://127.0.0.1:18734/cover.png")])))
        await lists.apply(.create("Owned manga hero", "", id: "owned-hero-manga"))
        await lists.apply(.add("owned-hero-manga", CustomListItem.input(book)))
        XCTAssertNil(lists.error); XCTAssertEqual(lists.lists.count, 2)
        let page = PageCustomization(owner: binding.settingsOwner, page: "home")
        try page.addListRow("owned-hero-movie", expected: page.scope); try page.addListRow("owned-hero-manga", expected: page.scope)
        page.change { $0.heroSource = "list-owned-hero-movie"; $0.secondaryMoreInfo = false }
        XCTAssertNil(page.error); XCTAssertEqual(page.layout.heroSource, "list-owned-hero-movie")
        UserDefaults.standard.set("harbor", forKey: "homeMode")
        UserDefaults.standard.set("poster", forKey: "rowCardStyle"); UserDefaults.standard.set("off", forKey: "posterEffect")
        XCTAssertTrue(ProfileSettingsStore.shared.saveCurrent())
    }
}
