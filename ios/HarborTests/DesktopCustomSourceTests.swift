import XCTest
@testable import Harbor

final class DesktopCustomSourceTests: XCTestCase {
    private func reference() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "desktop-custom-sources-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    func testNativeImportsMatchTheOriginalDesktopParserIncludingMalformedRowsDuplicateIDsAndFutureProviders() throws {
        let fixture = try reference(), cases = fixture["original_parser_cases"].array
        XCTAssertEqual(cases.count, 12); XCTAssertEqual(fixture["actual_original_typescript_executed"], .bool(true))
        for entry in cases {
            let input = try XCTUnwrap(entry["input"].string)
            XCTAssertEqual(DesktopSourceRow.parse(input).map(\.raw), entry["accepted"].array, input)
        }
    }
    func testNativeFolderDestinationsMatchTheOriginalDesktopClickHandlerWithoutProviderRequests() throws {
        let fixture = try reference(), cases = fixture["original_folder_action_cases"].array
        XCTAssertEqual(cases.count, 8); XCTAssertEqual(fixture["provider_network_requests"], .integer(0))
        for entry in cases {
            let folder = try XCTUnwrap(DesktopSourceFolder(entry["folder"]))
            let result: JSONValue
            switch folder.destination {
            case .discover(let title, let kind, let parameters):
                result = .object(["type": .string("discover"), "title": .string(title), "kind": .string(kind), "parameters": try .encoded(parameters)])
            case .collection(let title, let id): result = .object(["type": .string("collection"), "title": .string(title), "id": .string(id)])
            case .traktList(let title, let id): result = .object(["type": .string("traktList"), "title": .string(title), "id": .string(id)])
            case .catalog(let title, let addon, let kind, let id):
                result = .object(["type": .string("catalog"), "title": .string(title), "addon": .string(addon), "kind": .string(kind), "id": .string(id)])
            case nil: result = .null
            }
            XCTAssertEqual(result, entry["expected"])
        }
    }
    func testImportReplacementAndImageEditingKeepUnknownFieldsUnrelatedFoldersAndPublicSourceIdentities() throws {
        let fixture = try reference()
        let original = try XCTUnwrap(DesktopSourceRow.parse(try XCTUnwrap(fixture["original_parser_cases"].array.first?["input"].string)).first)
        var extra = original.raw.objectValue; extra["id"] = .string("other-row")
        var changed = original.raw.objectValue; changed["title"] = .string("Reimported row")
        let replacement = try XCTUnwrap(DesktopSourceRow(.object(changed)))
        let merged = DesktopSourceRow.merging([replacement], into: [original.raw, .object(extra)])
        XCTAssertEqual(merged, [replacement.raw, .object(extra)]); XCTAssertEqual(merged[0]["future"], original.raw["future"])
        let edited = replacement.editingImages(folderID: "folder-1", cover: "https://owned.invalid/cover.jpg", focus: "https://owned.invalid/focus.gif")
        XCTAssertEqual(edited.folders.first?.cover, "https://owned.invalid/cover.jpg")
        XCTAssertEqual(edited.folders.first?.focus, "https://owned.invalid/focus.gif")
        XCTAssertEqual(edited.raw["future"], replacement.raw["future"])
        XCTAssertEqual(edited.folders.first?.raw["catalogSources"], replacement.folders.first?.raw["catalogSources"])
        XCTAssertEqual(edited.editingImages(folderID: "missing-folder", cover: "", focus: ""), edited)
        let cleared = edited.editingImages(folderID: "folder-1", cover: "", focus: "")
        XCTAssertEqual(cleared.folders.first?.raw["coverImageUrl"], .null)
        XCTAssertEqual(cleared.folders.first?.raw["focusGifUrl"], .null)
    }
}
