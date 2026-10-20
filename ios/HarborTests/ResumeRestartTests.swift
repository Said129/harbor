import XCTest
@testable import Harbor

final class ResumeRestartTests: XCTestCase {
    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("owned-restart-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("resume.json")
    }

    func testExplicitRestartSurvivesRelaunchAndOlderLegacyCloudAndLateCheckpoints() async throws {
        let file = try location(), target = ResumeTarget(id: "owned.movie")
        let store = ResumeStore(fileURL: file); try await store.load()
        let legacy = ResumeTarget(id: target.id, season: 1, episode: 1, videoId: target.id)
        try await store.save(legacy, snapshot: ResumeSnapshot(positionMs: 60_000, durationMs: 600_000, timestampMs: 1, exiting: true))
        try await store.save(target, snapshot: ResumeSnapshot(positionMs: 90_000, durationMs: 600_000, timestampMs: 2, exiting: true))
        let ignored = try await store.save(target, snapshot: ResumeSnapshot(positionMs: 0, durationMs: 600_000, timestampMs: 3, exiting: true))
        XCTAssertFalse(ignored, "An automatic initial zero must not erase a saved position")
        let old = try await store.position(target); XCTAssertEqual(old.ms, 90_000)
        let reset = try await store.restart(target, timestampMs: 4); XCTAssertTrue(reset)
        try await store.save(target, snapshot: ResumeSnapshot(positionMs: 100_000, durationMs: 600_000, timestampMs: 3, exiting: true))
        let reloaded = ResumeStore(fileURL: file); try await reloaded.load()
        var movie = Media(id: target.id, type: "movie", name: "Owned Movie")
        movie.videos = [Episode(id: target.id, season: 1, episode: 1)]
        let result = try await reloaded.position(target, cloud: ResumeEntry(ms: 120_000, t: 2), media: movie)
        XCTAssertEqual(result.ms, 0)
        let entry = try await reloaded.entry(target); XCTAssertEqual(entry, ResumeEntry(ms: 0, t: 4))
    }

    func testRestartWriteFailureAndInvalidTargetRetainTheCommittedPosition() async throws {
        let file = try location(), target = ResumeTarget(id: "owned.movie")
        let store = ResumeStore(fileURL: file); try await store.load()
        try await store.save(target, snapshot: ResumeSnapshot(positionMs: 60_000, durationMs: 600_000, timestampMs: 1, exiting: true))
        do { try await store.restart(ResumeTarget(id: ""), timestampMs: 2); XCTFail("Invalid target accepted") }
        catch { XCTAssertEqual((error as? HarborError)?.code, "invalid-resume-target") }
        let backup = file.appendingPathExtension("backup"); try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { try await store.restart(target, timestampMs: 2); XCTFail("Failed restart was published") }
        catch { XCTAssertEqual((error as? HarborError)?.code, "resume-write-failed") }
        let result = try await store.position(target); XCTAssertEqual(result.ms, 60_000)
        let disk = try JSONDecoder().decode(ResumeDocument.self, from: Data(contentsOf: backup))
        XCTAssertEqual(disk.entries[target.id], ResumeEntry(ms: 60_000, t: 1))
    }
}
