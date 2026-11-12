import XCTest
@testable import Harbor

/// F11 B174 and S231: subtitle-only custom fonts, copied into the folder mpv reads and selected as `custom:<id>`.
final class F11SubtitleFontTests: XCTestCase {
    private var folder = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("F11Fonts-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        SubtitleFontFamilies.shared.replace(with: [])
        try? FileManager.default.removeItem(at: folder)
    }

    private func bundledInter() throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: "Inter", withExtension: "ttf"))
    }

    private func store() -> SubtitleFontStore {
        SubtitleFontStore(root: folder.appendingPathComponent("store", isDirectory: true))
    }

    private func copyOfInter(named name: String) throws -> URL {
        let target = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: try bundledInter(), to: target)
        return target
    }

    func testSelectionParsingFollowsDesktopCustomPrefix() {
        XCTAssertEqual(SubtitleFontSelection.customID(in: "custom:0a1b2c3d"), "0a1b2c3d")
        XCTAssertNil(SubtitleFontSelection.customID(in: "inter"))
        XCTAssertNil(SubtitleFontSelection.customID(in: "custom:"))
        XCTAssertNil(SubtitleFontSelection.customID(in: "custom:0A1B2C3D"))
        XCTAssertNil(SubtitleFontSelection.customID(in: "custom:0a1b2c3"))
        XCTAssertNil(SubtitleFontSelection.customID(in: "custom:../../etc"))
        XCTAssertEqual(SubtitleFontSelection.selection(forID: "0a1b2c3d"), "custom:0a1b2c3d")
        XCTAssertTrue(SubtitleFontSelection.isValidID(SubtitleFontSelection.newID()))
    }

    func testAnUnknownCustomFontFallsBackToInterInMpvAndUIKit() {
        var options = PlaybackOptions()
        options.subtitleFont = "custom:0a1b2c3d"
        XCTAssertEqual(options.subtitleFamily, "Inter")
        XCTAssertEqual(SubtitleFontSelection.uiFontName(for: "custom:0a1b2c3d"), "Inter-Regular")
        options.subtitleFont = "rounded"
        XCTAssertEqual(options.subtitleFamily, "Fredoka")
        XCTAssertEqual(SubtitleFontSelection.uiFontName(for: "serif"), "TimesNewRomanPSMT")
    }

    func testImportKeepsTheFamilyNameAndTheDesktopDisplayName() throws {
        let source = try copyOfInter(named: "My_Subtitle-Font.ttf")
        let store = store()
        let font = try store.importFont(from: source, owner: "owner-a")
        XCTAssertTrue(SubtitleFontSelection.isValidID(font.id))
        XCTAssertEqual(font.name, "My Subtitle Font")
        XCTAssertFalse(font.family.isEmpty)
        XCTAssertEqual(font.fileExtension, "ttf")
        XCTAssertEqual(store.list(owner: "owner-a"), [font])
        XCTAssertEqual(SubtitleFontFamilies.shared.family(forID: font.id), font.family)
        var options = PlaybackOptions()
        options.subtitleFont = SubtitleFontSelection.selection(forID: font.id)
        XCTAssertEqual(options.subtitleFamily, font.family)
    }

    func testPlayerDirectoryHoldsTheImportedFontBesideTheBundledOnes() throws {
        let store = store()
        XCTAssertNil(store.playerDirectory(owner: "owner-a"), "No imported font keeps the bundled folder")
        let font = try store.importFont(from: try copyOfInter(named: "Custom.ttf"), owner: "owner-a")
        let directory = try XCTUnwrap(store.playerDirectory(owner: "owner-a"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(font.fileName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Inter.ttf").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.json").path))
    }

    func testFontsBelongToOneProfile() throws {
        let store = store()
        _ = try store.importFont(from: try copyOfInter(named: "A.ttf"), owner: "owner-a")
        XCTAssertEqual(store.list(owner: "owner-b"), [])
        XCTAssertNil(store.playerDirectory(owner: "owner-b"))
        XCTAssertEqual(store.list(owner: "owner-a").count, 1)
    }

    func testRemoveDeletesTheFileAndTheEntry() throws {
        let store = store()
        let font = try store.importFont(from: try copyOfInter(named: "Gone.ttf"), owner: "owner-a")
        let directory = try XCTUnwrap(store.playerDirectory(owner: "owner-a"))
        try store.remove(id: font.id, owner: "owner-a")
        XCTAssertEqual(store.list(owner: "owner-a"), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(font.fileName).path))
        XCTAssertNil(store.playerDirectory(owner: "owner-a"))
        XCTAssertNil(SubtitleFontFamilies.shared.family(forID: font.id))
        XCTAssertThrowsError(try store.remove(id: "../escape", owner: "owner-a"))
    }

    func testRejectsFilesThatAreNotFonts() throws {
        let store = store()
        let text = folder.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: text)
        XCTAssertThrowsError(try store.importFont(from: text, owner: "owner-a"))
        let broken = folder.appendingPathComponent("broken.ttf")
        try Data("this is not a font".utf8).write(to: broken)
        XCTAssertThrowsError(try store.importFont(from: broken, owner: "owner-a"))
        let empty = folder.appendingPathComponent("empty.otf")
        try Data().write(to: empty)
        XCTAssertThrowsError(try store.importFont(from: empty, owner: "owner-a"))
        XCTAssertEqual(store.list(owner: "owner-a"), [])
    }

    func testOwnerKeyIsStableAndDoesNotRevealTheOwner() {
        let key = SubtitleFontStore.ownerKey("owner-a")
        XCTAssertEqual(key, SubtitleFontStore.ownerKey("owner-a"))
        XCTAssertNotEqual(key, SubtitleFontStore.ownerKey("owner-b"))
        XCTAssertEqual(key.count, 16)
        XCTAssertFalse(key.contains("owner"))
    }

    func testSfntExtensionTellsCFFFromTrueType() {
        XCTAssertEqual(SubtitleFontStore.sfntExtension(Data([0x4F, 0x54, 0x54, 0x4F, 0x00])), "otf")
        XCTAssertEqual(SubtitleFontStore.sfntExtension(Data([0x00, 0x01, 0x00, 0x00])), "ttf")
    }
}
