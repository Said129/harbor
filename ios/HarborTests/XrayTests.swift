import XCTest
@testable import Harbor

/// Desktop's X-Ray cast rail (`components/player/xray/*`, `lib/xray/use-xray-cast.ts`) without the live face scan: the cast rules and the setting.
final class XrayTests: XCTestCase {
    private func credit(_ id: Int, _ name: String, _ role: String = "", photo: String? = nil) -> MediaDetails.Credit {
        MediaDetails.Credit(id: id, name: name, role: role, photo: photo)
    }

    func testSettingIsOffByDefaultAndSavesTheChoice() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "harbor.xray.tests.\(UUID().uuidString)"))
        XCTAssertFalse(XrayRules.enabled(suite))
        suite.set(true, forKey: XrayRules.enabledKey)
        XCTAssertTrue(XrayRules.enabled(suite))
    }

    func testSettingKeyIsTheDesktopNameAndFollowsTheProfile() {
        XCTAssertEqual(XrayRules.enabledKey, "xrayEnabled")
        XCTAssertTrue(ProfileSettingsStore.keys.contains(XrayRules.enabledKey))
        XCTAssertFalse(ProfileSettingsStore.keys.contains("xrayLiveScan"), "the live scan is not ported, so its setting is not stored")
    }

    func testPeopleKeepTMDBOrderAndDropDuplicatesAndNamelessEntries() {
        let people = XrayRules.people(from: [
            credit(7, "  Ana Actor ", "Mae", photo: "https://img/a.jpg"),
            credit(8, "   ", "Ghost"),
            credit(9, "Bo Second", "Son"),
            credit(7, "Ana Actor again", "Other role"),
            credit(10, "Cy Third", ""),
        ])
        XCTAssertEqual(people.map(\.id), [7, 9, 10])
        XCTAssertEqual(people[0], XrayPerson(id: 7, name: "Ana Actor", character: "Mae", photo: "https://img/a.jpg"))
        XCTAssertEqual(people[2].character, "")
        XCTAssertNil(people[1].photo)
    }

    func testPeopleAreCappedAtTheLimit() {
        let credits = (1...70).map { credit($0, "Person \($0)") }
        XCTAssertEqual(XrayRules.people(from: credits).count, XrayRules.castLimit)
        XCTAssertEqual(XrayRules.castLimit, 60)
        XCTAssertEqual(XrayRules.people(from: credits, limit: 3).map(\.id), [1, 2, 3])
        XCTAssertEqual(XrayRules.people(from: []), [])
    }

    func testRailStateChoosesCastOrTheKeyOrEmpty() {
        let people = XrayRules.people(from: [credit(1, "Ana")])
        XCTAssertEqual(XrayRules.railState(people: people, hasTMDBKey: false), .cast, "a cast is shown even without a key")
        XCTAssertEqual(XrayRules.railState(people: people, hasTMDBKey: true), .cast)
        XCTAssertEqual(XrayRules.railState(people: [], hasTMDBKey: false), .needsTMDBKey)
        XCTAssertEqual(XrayRules.railState(people: [], hasTMDBKey: true), .empty)
    }

    func testInitialsUseTheFirstAndLastWord() {
        XCTAssertEqual(XrayRules.initials("Ana Maria Lopez"), "AL")
        XCTAssertEqual(XrayRules.initials("cher"), "C")
        XCTAssertEqual(XrayRules.initials("  ana   lopez "), "AL")
        XCTAssertEqual(XrayRules.initials("   "), "?")
        XCTAssertEqual(XrayRules.initials(""), "?")
    }
}
