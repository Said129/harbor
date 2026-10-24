import XCTest
@testable import Harbor

final class PageContinuationInterfaceSeedTests: XCTestCase {
    private struct PublicRailCache: Codable { let at: Date; let items: [Media] }
    @MainActor func testPrepareOwnedContinueHistoryAndPublicAnimeRowsOnAFreshGuest() async throws {
        guard try KeychainStore().read("account.v1", as: JSONValue.self) == nil else { XCTFail("Refuse configured account"); return }
        let context = AppProfileContext.shared; try context.prepare()
        guard context.profiles.profiles.count == 1, context.profiles.active?.credential == nil,
              context.configuration?.account == nil, let binding = context.binding else { XCTFail("Refuse configured household"); return }
        try context.save(HouseholdSourceAccount(account: nil, guestAddons: []))
        let raw: JSONValue = .object(["_id": .string("owned-anime-layout"), "type": .string("anime"), "name": .string("Owned continuation"),
            "isAnime": .bool(true), "removed": .bool(false), "temp": .bool(false), "_mtime": .string(Date().ISO8601Format()),
            "state": .object(["timeOffset": .integer(120_000), "duration": .integer(1_200_000), "season": .integer(1), "episode": .integer(5),
                "video_id": .string("owned-anime-layout:1:5")])])
        try await LibraryCache().save([raw], owner: binding.progressOwner)
        var entries: [String: PublicRailCache] = [:]
        let definitions = AnimeService.definitions().filter { $0.path != "anime:picks" } + AnimeService.homeDefinitions()
        for (index, rail) in definitions.enumerated() {
            let pages = rail.id.hasPrefix("home-anime-") ? 3 : rail.id == "anilist-top100" ? 2 : 1
            for page in 1...pages {
                let id = (rail.id.hasPrefix("anilist-") ? "anilist:" : "mal:") + String(100_000 + index * 100 + page)
                let media = Media(id: id, type: "anime", name: "Owned public catalog " + String(index) + "-" + String(page))
                entries[rail.id + ":" + String(page)] = PublicRailCache(at: Date(), items: [media])
            }
        }
        let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("harbor-public-anime-rails.json")
        try JSONEncoder().encode(entries).write(to: cache, options: .atomic)
        XCTAssertLessThanOrEqual(entries.count, 100)
        UserDefaults.standard.set("en", forKey: "uiLanguage")
        UserDefaults.standard.set(false, forKey: "interface.autoRotateBanners")
        UserDefaults.standard.set(true, forKey: "nativeGuide.initialized.v1"); UserDefaults.standard.set(true, forKey: "nativeGuide.completed.v1")
        let saved = try await LibraryCache().read(owner: binding.progressOwner)
        XCTAssertEqual(saved.count, 1)
    }
}
