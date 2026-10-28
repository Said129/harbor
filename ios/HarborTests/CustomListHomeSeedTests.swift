import XCTest
import UIKit
@testable import Harbor

@MainActor enum OwnedHomeMangaFixture {
    static func create(owner: String) async throws -> MangaBook {
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("Owned Harbor Manga.pdf")
        defer { try? FileManager.default.removeItem(at: input) }
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            for page in 0..<2 {
                context.beginPage()
                UIColor(red: 0.08, green: 0.16, blue: 0.23, alpha: 1).setFill(); context.cgContext.fill(bounds)
                UIColor(red: 0.13, green: 0.72, blue: 0.69, alpha: 1).setFill()
                context.cgContext.fill(CGRect(x: 0, y: 300, width: 400, height: 300))
                let title = page == 0 ? "HARBOR\nOWNED MANGA" : "CHAPTER ONE\nPAGE TWO"
                (title as NSString).draw(in: CGRect(x: 28, y: 75, width: 344, height: 200),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 42), .foregroundColor: UIColor.white])
                ("A LOCAL PDF\nPrivate to this profile" as NSString).draw(in: CGRect(x: 28, y: 465, width: 344, height: 100),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: UIColor.black])
            }
        }
        try data.write(to: input)
        return try await MangaLocalStore.shared.importPDF(input, owner: owner)
    }
}

final class CustomListHomeSeedTests: XCTestCase {
    @MainActor func testPrepareOwnedMovieMangaAndEmptyListsForTheRealHomeOnAFreshGuest() async throws {
        let (binding, _) = try ContinuePrivacyInterfaceSeedTests.prepareOwnedSharedGuest()
        guard try await CustomListDisk.shared.read(owner: binding.settingsOwner) == nil,
              try KeychainStore().read("manga-shelf-" + EBookShelf.hash(binding.personalOwner), as: [MangaRecord].self) == nil else {
            XCTFail("Refuse configured libraries"); throw HarborError(code: "owned-seed-safety")
        }
        let book = try await OwnedHomeMangaFixture.create(owner: binding.personalOwner)
        let shelf = MangaShelf(owner: binding.personalOwner); XCTAssertTrue(shelf.ready)
        try shelf.save(MangaRecord(book: book))
        let store = CustomListStore(owner: binding.settingsOwner); await store.load()
        await store.apply(.create("Owned movie picks", "", id: "owned-movies"))
        for index in 1...10 {
            await store.apply(.add("owned-movies", .object(["id": .string("owned-home:film-" + String(index)),
                "type": .string("movie"), "name": .string("Owned film " + String(index)), "poster": .string("http://127.0.0.1:18734/cover.png")])))
        }
        await store.apply(.create("Owned manga picks", "", id: "owned-manga"))
        await store.apply(.add("owned-manga", CustomListItem.input(book)))
        await store.apply(.create("Owned empty list", "", id: "owned-empty"))
        XCTAssertEqual(store.lists.count, 3); XCTAssertNil(store.error)
        let defaults = UserDefaults.standard
        defaults.set("harbor", forKey: "homeMode"); defaults.set("poster", forKey: "rowCardStyle")
        defaults.set(1.0, forKey: "posterScale"); defaults.set("off", forKey: "posterEffect")
        XCTAssertTrue(ProfileSettingsStore.shared.saveCurrent())
    }
}
