import XCTest
@testable import Harbor

final class HarborRosterTests: XCTestCase {
    private func row(_ id: String, primary: Bool = false, kid: Bool = false, deleted: Bool = false) -> JSONValue {
        .object(["syncId": .string(id), "name": .string(id), "isPrimary": .bool(primary), "avatar": .string("/avatars/harbor_animal_01.webp"), "color": .string("#7dd3fc"), "kid": kid ? .object(["age": .integer(7), "curfewMinutes": .integer(30)]) : .null, "deletedAt": deleted ? .integer(1_000) : .null, "lockedTabs": .array([.string("manga")]), "hideContent": .object(["adult": .bool(true)]), "futureField": .string("keep")])
    }
    private func doc(_ profiles: [JSONValue], rev: Int64 = 9) -> JSONValue {
        .object(["key": .string(HarborRoster.key), "rev": .integer(rev), "value": .object(["profiles": .array(profiles), "householdField": .string("preserve")])])
    }
    func testTargetedEditPreservesHouseholdAndUnknownFields() throws {
        let first = row("primary", primary: true), child = row("child", kid: true), tombstone = row("removed", deleted: true)
        let original = try HarborRoster.document(doc([first, child, tombstone]))
        let changed = try original.applying(["name": .string("Said"), "color": .string("#ff5500")], to: "primary")
        XCTAssertEqual(changed.rev, 9, "Only the server may assign a new revision")
        XCTAssertEqual(changed.profiles[1], child)
        XCTAssertEqual(changed.profiles[2], tombstone)
        XCTAssertEqual(changed.value["householdField"], .string("preserve"))
        XCTAssertEqual(changed.profiles[0]["futureField"], .string("keep"))
        XCTAssertEqual(changed.profiles[0]["lockedTabs"], first["lockedTabs"])
        XCTAssertEqual(changed.profiles[0]["hideContent"], first["hideContent"])
        XCTAssertEqual(changed.profiles[0]["name"], .string("Said"))
    }
    func testConflictRebaseKeepsDesktopChangesOutsideEditedFields() throws {
        var remote = row("primary", primary: true).objectValue
        remote["name"] = .string("Desktop name"); remote["futureField"] = .string("new desktop field")
        let current = try HarborRoster.document(doc([.object(remote)], rev: 10))
        let rebased = try current.applying(["color": .string("#ff5500")], to: "primary")
        XCTAssertEqual(rebased.rev, 10)
        XCTAssertEqual(rebased.profiles[0]["name"], .string("Desktop name"))
        XCTAssertEqual(rebased.profiles[0]["futureField"], .string("new desktop field"))
    }
    func testColdDeviceNeverInterpretsMalformedOrAbsentRosterAsEmpty() {
        for value: JSONValue in [.object([:]), .object(["rev": .integer(4)]), .object(["rev": .integer(4), "docs": .array([])]), .object(["rev": .integer(4), "docs": .array([doc([])])])] {
            XCTAssertThrowsError(try HarborRoster.state(value))
        }
        XCTAssertThrowsError(try HarborRoster.document(doc([row("same"), row("same")])))
    }
    func testDeletedAndChildProfilesCannotReceiveAnIdentityPatch() throws {
        let roster = try HarborRoster.document(doc([row("primary", primary: true), row("child", kid: true), row("deleted", deleted: true)]))
        XCTAssertThrowsError(try roster.applying(["name": .string("Said")], to: "deleted"))
        XCTAssertThrowsError(try roster.applying(["name": .string("Said")], to: "child"))
        XCTAssertThrowsError(try roster.applying(["passwordHash": .string("forbidden")], to: "primary"))
        XCTAssertEqual(roster.primary()?["syncId"], .string("primary"))
    }
}
