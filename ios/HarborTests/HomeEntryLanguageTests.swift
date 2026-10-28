import XCTest
@testable import Harbor

@MainActor final class HomeEntryLanguageTests: XCTestCase {
    func testAllSixteenDesktopCatalogsResolveTheHeroAndSeasonalInvitationLabels() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "home-labels-reference", withExtension: "json", subdirectory: "Fixtures"))
        let original = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(original["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(original["original_catalogs_executed"], .bool(true))
        XCTAssertEqual(original["actual_original_invitation_component_executed"], .bool(true))
        XCTAssertEqual(original["provider_network_requests"].integer, 0)
        XCTAssertEqual(original["languages"].array.count, 16); XCTAssertEqual(original["keys"].array.count, 9)
        for row in original["languages"].array {
            let code = try XCTUnwrap(row["code"].string)
            for (key, expected) in row["expected"].objectValue {
                XCTAssertEqual(DesktopInterfaceText.value(key, language: code), expected.string, code + ": " + key)
            }
        }
        let branches = original["original_branches"].array; XCTAssertEqual(branches.count, 2)
        XCTAssertEqual(branches[0]["button_count"].integer, 2); XCTAssertEqual(branches[0]["has_dismiss"], .bool(true))
        XCTAssertEqual(branches[1]["button_count"].integer, 1); XCTAssertEqual(branches[1]["has_dismiss"], .bool(false))
        XCTAssertEqual(branches[1]["invitation_marker"].string, "collapsed")
        XCTAssertEqual(branches[1]["open_calls"].integer, 1)
        XCTAssertEqual(branches[1]["invitation_title"].string, "Step inside")
    }
}
