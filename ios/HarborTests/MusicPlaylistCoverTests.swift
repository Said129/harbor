import ImageIO
import UIKit
import XCTest
@testable import Harbor

@MainActor final class MusicPlaylistCoverTests: XCTestCase {
    func testFiveOriginalFormatsActuallyDecodeAndPublishAsBoundedAlphaPreservingNativeCovers() async throws {
        let owner = "owned-cover-formats-" + UUID().uuidString, playlist = UUID().uuidString
        let store = MusicPlaylistCoverStore()
        defer { try? store.clear(owner: owner, playlist: playlist, allowed: { true }) }
        for (index, ext) in ["png", "jpg", "gif", "webp", "avif"].enumerated() {
            let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-playlist-cover", withExtension: ext, subdirectory: "Fixtures"))
            try await store.save(Data(contentsOf: file), owner: owner, playlist: playlist, allowed: { true })
            let bitmap = try await store.image(owner: owner, playlist: playlist)
            let image = try XCTUnwrap(bitmap?.image.cgImage)
            XCTAssertEqual(image.width, 48, ext); XCTAssertEqual(image.height, 24, ext)
            XCTAssertEqual(store.revision(owner: owner, playlist: playlist), UInt64(index + 1))
        }
        try await store.save(Self.png(size: CGSize(width: 1800, height: 900), color: UIColor.systemTeal.withAlphaComponent(0.4)), owner: owner, playlist: playlist, allowed: { true })
        let bitmap = try await store.image(owner: owner, playlist: playlist, maxPixels: 900)
        let image = try XCTUnwrap(bitmap?.image.cgImage)
        XCTAssertEqual(image.width, 900); XCTAssertEqual(image.height, 450)
        XCTAssertFalse([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo))
    }
    func testInvalidAndOversizedImagesPreserveThePriorCoverAndOwnersNeverShareFiles() async throws {
        let owner = "owned-cover-protection-" + UUID().uuidString, other = owner + "-other", playlist = UUID().uuidString
        let store = MusicPlaylistCoverStore(), first = Self.png(size: CGSize(width: 64, height: 64), color: .systemBlue)
        defer { try? store.clear(owner: owner, playlist: playlist, allowed: { true }); try? store.clear(owner: other, playlist: playlist, allowed: { true }) }
        try await store.save(first, owner: owner, playlist: playlist, allowed: { true })
        let file = try MusicPlaylistCoverFiles.file(owner, playlist), original = try Data(contentsOf: file)
        do { try await store.save(Data("not an image".utf8), owner: owner, playlist: playlist, allowed: { true }); XCTFail("Invalid data must not replace a cover") } catch MusicPlaylistCoverError.type { }
        do { try await store.save(Data(count: 24 * 1024 * 1024 + 1), owner: owner, playlist: playlist, allowed: { true }); XCTFail("The original 24 MB limit must be preserved") } catch MusicPlaylistCoverError.size { }
        XCTAssertEqual(try Data(contentsOf: file), original); XCTAssertEqual(store.revision(owner: owner, playlist: playlist), 1)
        let missing = try await store.image(owner: other, playlist: playlist); XCTAssertNil(missing)
        try await store.save(Self.png(size: CGSize(width: 72, height: 72), color: .systemOrange), owner: other, playlist: playlist, allowed: { true })
        let separate = try await MusicPlaylistCoverStore().image(owner: other, playlist: playlist)
        XCTAssertEqual(separate?.image.cgImage?.width, 72)
        try store.clear(owner: owner, playlist: playlist, allowed: { true })
        let after = try await store.image(owner: owner, playlist: playlist), stillOther = try await store.image(owner: other, playlist: playlist)
        XCTAssertNil(after); XCTAssertNotNil(stillOther)
    }
    func testRetiredPermissionAndClearCannotBeUndoneByAnOlderStagedUpload() async throws {
        let owner = "owned-cover-retirement-" + UUID().uuidString, playlist = UUID().uuidString
        let initial = MusicPlaylistCoverStore(), image = Self.png(size: CGSize(width: 96, height: 48), color: .systemPurple)
        defer { try? initial.clear(owner: owner, playlist: playlist, allowed: { true }) }
        try await initial.save(image, owner: owner, playlist: playlist, allowed: { true })
        let path = try MusicPlaylistCoverFiles.file(owner, playlist), original = try Data(contentsOf: path)
        let gate = SharedMusicGate(), permission = CoverPermission(), io = HeldCoverIO(gate: gate)
        let store = MusicPlaylistCoverStore(io: io)
        let late = Task { try await store.save(image, owner: owner, playlist: playlist, allowed: { permission.active }) }
        try await waiting(gate); permission.active = false; await gate.release()
        do { try await late.value; XCTFail("A retired profile cannot publish a previously staged cover") } catch is CancellationError { }
        XCTAssertEqual(try Data(contentsOf: path), original); XCTAssertEqual(store.revision(owner: owner, playlist: playlist), 0)
        permission.active = true
        let second = Task { try await store.save(image, owner: owner, playlist: playlist, allowed: { permission.active }) }
        try await waiting(gate)
        try store.clear(owner: owner, playlist: playlist, allowed: { permission.active }); await gate.release()
        do { try await second.value; XCTFail("An old upload must not resurrect a cleared cover") } catch is CancellationError { }
        let missing = try await store.image(owner: owner, playlist: playlist); XCTAssertNil(missing)
        let temporary = try FileManager.default.contentsOfDirectory(at: path.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.pathExtension == "stage" }
        XCTAssertTrue(temporary.isEmpty)
    }
    func testAllOriginalCoverLabelsMatchTheSixteenPinnedLanguages() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "music-playlist-cover-labels", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)); var count = 0
        for language in fixture["languages"].array {
            let code = try XCTUnwrap(language["code"].string)
            for (key, value) in language["expected"].objectValue { XCTAssertEqual(DesktopInterfaceText.value(key, language: code), try XCTUnwrap(value.string), code + ": " + key); count += 1 }
        }
        XCTAssertEqual(count, 80)
    }
    static func png(size: CGSize, color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.setFillColor(color.cgColor); context.cgContext.fill(CGRect(origin: .zero, size: size))
        }.pngData()!
    }
    private func waiting(_ gate: SharedMusicGate) async throws {
        for _ in 0..<300 { if await gate.waiting() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("The actual staged file must reach its owned barrier"); throw HarborError(code: "owned-cover-barrier")
    }
}
@MainActor private final class CoverPermission { var active = true }
private actor HeldCoverIO: MusicPlaylistCoverIO {
    private let base = MusicPlaylistCoverFiles()
    let gate: SharedMusicGate
    init(gate: SharedMusicGate) { self.gate = gate }
    func stage(_ data: Data, owner: String, playlist: String) async throws -> MusicPlaylistCoverStage {
        let result = try await base.stage(data, owner: owner, playlist: playlist)
        await gate.hold(); return result
    }
    func image(owner: String, playlist: String, maxPixels: Int) async throws -> DecodedArtworkBitmap? { try await base.image(owner: owner, playlist: playlist, maxPixels: maxPixels) }
    func discard(_ stage: MusicPlaylistCoverStage) async { await base.discard(stage) }
}
