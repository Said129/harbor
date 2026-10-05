import Foundation
import CryptoKit
import XCTest
@testable import Harbor

final class ResumeStoreTests: XCTestCase {
    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("resume-v1.json")
    }

    private func snapshot(_ position: Double, t: UInt64) -> ResumeSnapshot {
        ResumeSnapshot(positionMs: position, durationMs: 3_600_000, timestampMs: t, exiting: false)
    }

    func testRestartRoundTripEpisodeIsolationAndLateCheckpoint() async throws {
        let file = try location()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let one = ResumeTarget(id: "tt123", season: 1, episode: 1)
        let two = ResumeTarget(id: "tt123", season: 1, episode: 2)
        let store = ResumeStore(fileURL: file)
        try await store.load()
        try await store.save(one, snapshot: snapshot(60_000, t: 2))
        try await store.save(two, snapshot: snapshot(120_000, t: 3))
        try await store.save(one, snapshot: snapshot(90_000, t: 1))
        try await store.save(one, snapshot: snapshot(100_000, t: 2))
        let restarted = ResumeStore(fileURL: file)
        try await restarted.load()
        let first = try await restarted.position(one)
        let second = try await restarted.position(two, prompt: true)
        XCTAssertEqual(first.ms, 60_000)
        XCTAssertFalse(first.prompt)
        XCTAssertEqual(second.ms, 120_000)
        XCTAssertTrue(second.prompt)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(text.contains("http"))
        XCTAssertFalse(text.contains("token"))
    }

    func testCorruptAndUnsupportedStorePreservedAfterSaveAttempt() async throws {
        let file = try location()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        for text in ["broken-json", #"{"version":2,"entries":{}}"#] {
            let original = Data(text.utf8)
            try original.write(to: file)
            let store = ResumeStore(fileURL: file)
            do { try await store.load(); XCTFail("A bad store must fail") }
            catch { XCTAssertTrue(error is HarborError) }
            do { try await store.save(ResumeTarget(id: "tt123"), snapshot: snapshot(60_000, t: 1)); XCTFail("Save must remain disabled") }
            catch { XCTAssertEqual((error as? HarborError)?.code, "resume-store-unavailable") }
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }

    func testFailedWriteDoesNotCommitMemory() async throws {
        let file = try location()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ResumeStore(fileURL: file)
        let target = ResumeTarget(id: "tt123")
        try await store.load()
        try await store.save(target, snapshot: snapshot(60_000, t: 1))
        let backup = file.appendingPathExtension("backup")
        try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { try await store.save(target, snapshot: snapshot(120_000, t: 2)); XCTFail("Writing over a directory must fail") }
        catch { XCTAssertEqual((error as? HarborError)?.code, "resume-write-failed") }
        let current = try await store.position(target)
        XCTAssertEqual(current.ms, 60_000)
        let saved = try JSONDecoder().decode(ResumeDocument.self, from: Data(contentsOf: backup))
        XCTAssertEqual(saved.entries["tt123"]?.ms, 60_000)
    }

    func testCloudOrderingAndProductionAccountIsolation() async throws {
        let owners = ["resume-test-\(UUID().uuidString)", "resume-test-\(UUID().uuidString)"]
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("Harbor")
        defer {
            for owner in owners {
                let hash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("resume-\(hash).json"))
            }
        }
        let first = ResumeStore(owner: owners[0]), second = ResumeStore(owner: owners[1])
        try await first.load(); try await second.load()
        let target = ResumeTarget(id: "show", season: 0, episode: 1, videoId: "show:0:1")
        try await first.save(target, snapshot: snapshot(60_000, t: 20))
        let isolated = try await second.position(target)
        XCTAssertEqual(isolated.ms, 0)
        let older = try await first.position(target, cloud: ResumeEntry(ms: 120_000, t: 10))
        let newer = try await first.position(target, prompt: true, cloud: ResumeEntry(ms: 120_000, t: 30))
        let cleared = try await first.position(target, cloud: ResumeEntry(ms: 0, t: 30))
        XCTAssertEqual(older.ms, 60_000)
        XCTAssertEqual(newer.ms, 120_000); XCTAssertTrue(newer.prompt)
        XCTAssertEqual(cleared.ms, 0)
        // A cloud read does not mutate or erase the last local checkpoint.
        let preserved = try await first.position(target)
        XCTAssertEqual(preserved.ms, 60_000)
    }
}
