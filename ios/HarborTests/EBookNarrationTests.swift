import AVFoundation
import XCTest
@testable import Harbor

private actor NarrationTransportProbe: EBookNarrationTransport {
    let audio: Data
    let delay: UInt64
    private(set) var calls = 0
    private(set) var cancelled = false
    init(audio: Data = Data([1, 2, 3]), delay: UInt64 = 0) { self.audio = audio; self.delay = delay }
    func voices() async throws -> [EBookNarrationVoice] { try EBookNarrationCatalog.load().voices }
    func synthesize(_ text: String, voice: String, locale: String, rate: Int) async throws -> EBookNarrationAudio {
        calls += 1
        do { if delay > 0 { try await Task.sleep(nanoseconds: delay) }; try Task.checkCancellation() }
        catch { cancelled = true; throw error }
        return .init(audio: audio, boundaries: [.init(offsetMs: 0, durationMs: 500, text: "Owned"), .init(offsetMs: 500, durationMs: 500, text: "sample")])
    }
}

final class EBookNarrationTests: XCTestCase {
    func testOriginalVoiceSamplesGECMessagesAndMetadataUseThePinnedEdgeWireFormat() throws {
        let catalog = try EBookNarrationCatalog.load(); XCTAssertEqual(catalog.voices.count, 20); XCTAssertEqual(catalog.voices.first?.id, "en-US-AvaNeural")
        XCTAssertTrue(catalog.sample(locale: "es-ES", fallback: "fallback").contains("Bienvenido")); XCTAssertNotEqual(catalog.sample(locale: "ar-SA", fallback: ""), catalog.sample(locale: "ar-EG", fallback: ""))
        let date = Date(timeIntervalSince1970: 1_761_264_000)
        XCTAssertEqual(EBookEdgeProtocol.gec(at: date), "8390DB4DB9AB21AD7DBED19352440CD1FF198A725085DE2EF40E7D872A3EF9F6")
        XCTAssertTrue(EBookEdgeProtocol.configuration(date: date).contains("\"wordBoundaryEnabled\":\"true\""))
        let header = Data("Content-Type:audio/mpeg\r\nPath:audio\r\n".utf8)
        var packet = Data([UInt8(header.count >> 8), UInt8(header.count & 255)]); packet.append(header); packet.append(contentsOf: [1, 2, 3])
        XCTAssertEqual(EBookEdgeProtocol.binaryAudio(packet), Data([1, 2, 3])); XCTAssertNil(EBookEdgeProtocol.binaryAudio(Data([255, 255, 0])))
        let message = EBookEdgeProtocol.textMessage("Path:audio.metadata\r\n\r\n{\"Metadata\":[{\"Type\":\"WordBoundary\",\"Data\":{\"Offset\":5000000,\"Duration\":2000000,\"text\":{\"Text\":\"Owned\"}}}]}")
        XCTAssertEqual(message.path, "audio.metadata"); XCTAssertEqual(EBookEdgeProtocol.boundaries(message.body), [.init(offsetMs: 500, durationMs: 200, text: "Owned")])
        XCTAssertTrue(EBookEdgeProtocol.boundaries("invalid").isEmpty)
    }
    func testOriginalUnicodeChunkLimitsSSMLValidationAndGrowingParagraphWindows() throws {
        let text = String(repeating: "مرحبا بالعالم. 😀 Café ", count: 450) + String(repeating: "hello world ", count: 300)
        let chunks = try EBookEdgeProtocol.chunks(text); XCTAssertGreaterThan(chunks.count, 1); XCTAssertTrue(chunks.allSatisfy { $0.utf8.count <= 3600 })
        XCTAssertEqual(chunks.joined(separator: " ").split(whereSeparator: \.isWhitespace), text.split(whereSeparator: \.isWhitespace))
        XCTAssertThrowsError(try EBookEdgeProtocol.chunks(String(repeating: "x", count: 500001)))
        XCTAssertThrowsError(try EBookEdgeProtocol.ssml("Owned", voice: "../voice", locale: "en-US", rate: 0))
        let ssml = try EBookEdgeProtocol.ssml("<&'\"\u{1}", voice: "en-US-AvaNeural", locale: "en-US", rate: 500)
        XCTAssertTrue(ssml.contains("&lt;&amp;&apos;&quot; ")); XCTAssertTrue(ssml.contains("rate='+100%'"))
        let paragraphs = (0..<20).map { EBookSearchParagraph(block: $0 * 3, text: String(repeating: "Owned sample ", count: 25)) }
        let first = try XCTUnwrap(EBookNarrationWindow.make(paragraphs, start: 0, step: 0, locale: "en-US"))
        let next = try XCTUnwrap(EBookNarrationWindow.make(paragraphs, start: first.end, step: 1, locale: "en-US"))
        XCTAssertEqual(first.end, 2); XCTAssertEqual(next.end - next.start, 4)
        XCTAssertEqual(first.paragraph(position: 75, duration: 100, boundaries: []), 1)
    }
    func testDurableProfileCacheCombinesChunkTimelinesAndClearsOnlyItsOwnOwner() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let network = NarrationTransportProbe(), client = try EBookNarrationClient(owner: "one", directory: directory, transport: network)
        let text = String(repeating: "Owned sample ", count: 400), voice = "en-US-AvaNeural"
        let first = try await client.synthesize(text, voice: voice, locale: "en-US")
        let before = await network.calls; XCTAssertGreaterThan(before, 1); XCTAssertEqual(first.audio.count, before * 3)
        XCTAssertEqual(first.boundaries.last?.offsetMs, Double(before - 1) * 1000 + 500)
        let reopened = try EBookNarrationClient(owner: "one", directory: directory, transport: network)
        let cached = try await reopened.synthesize(text, voice: voice, locale: "en-US"); XCTAssertEqual(cached.audio, first.audio)
        let after = await network.calls; XCTAssertEqual(after, before)
        let other = try EBookNarrationClient(owner: "two", directory: directory, transport: network)
        _ = try await other.synthesize(text, voice: voice, locale: "en-US"); try await client.clearCache()
        let otherBefore = await network.calls; _ = try await other.synthesize(text, voice: voice, locale: "en-US"); let otherAfter = await network.calls; XCTAssertEqual(otherAfter, otherBefore)
        _ = try await reopened.synthesize(text, voice: voice, locale: "en-US"); let regenerated = await network.calls; XCTAssertGreaterThan(regenerated, otherAfter)
    }
    @MainActor func testActualNativeMP3PlaybackPausesSeeksChangesRateResumesAndStops() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "narration-owned-silence", withExtension: "mp3", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url), narrator = EBookNarrator(transport: NarrationTransportProbe(audio: data))
        narrator.prepare(owner: "narration-playback-" + UUID().uuidString); defer { narrator.stop() }
        narrator.start(blocks: [.init(id: 42, text: "Owned sample")], block: 42, voice: "en-US-AvaNeural", device: false, speed: 1)
        for _ in 0..<150 { if narrator.duration > 0 || narrator.notice != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNil(narrator.notice); XCTAssertGreaterThan(narrator.duration, 7); XCTAssertTrue(narrator.speaking); XCTAssertEqual(narrator.currentBlock, 42)
        narrator.togglePause(); XCTAssertTrue(narrator.paused); narrator.seek(3); XCTAssertEqual(narrator.position, 3, accuracy: 0.1)
        narrator.setSpeed(1.25); narrator.togglePause(); XCTAssertFalse(narrator.paused)
        narrator.stop(); XCTAssertFalse(narrator.speaking); XCTAssertEqual(narrator.duration, 0); XCTAssertNil(narrator.currentBlock)
    }
    @MainActor func testStoppingTheActualNarratorCancelsPendingTransportAndRejectsLatePlayback() async throws {
        let network = NarrationTransportProbe(delay: 10_000_000_000), narrator = EBookNarrator(transport: network)
        narrator.prepare(owner: "narration-cancel-" + UUID().uuidString)
        narrator.start(blocks: [.init(id: 8, text: "Owned cancellation sample")], block: 8, voice: "en-US-AvaNeural", device: false, speed: 1)
        for _ in 0..<100 { if await network.calls > 0 { break }; try await Task.sleep(for: .milliseconds(20)) }
        let calls = await network.calls; XCTAssertEqual(calls, 1); narrator.stop()
        for _ in 0..<100 { if await network.cancelled { break }; try await Task.sleep(for: .milliseconds(20)) }
        let cancelled = await network.cancelled; XCTAssertTrue(cancelled); XCTAssertFalse(narrator.speaking); XCTAssertFalse(narrator.loading); XCTAssertEqual(narrator.duration, 0); XCTAssertNil(narrator.notice)
    }
    func testLiveEdgeCatalogAndGeneratedMP3UseTheActualNativeWebSocket() async throws {
        let transport = EBookEdgeTransport(), voices = try await transport.voices()
        XCTAssertGreaterThan(voices.count, 100); XCTAssertTrue(voices.contains { $0.locale.hasPrefix("es-") })
        let audio = try await transport.synthesize("Harbor owned narration test.", voice: "en-US-AvaNeural", locale: "en-US", rate: 0)
        XCTAssertFalse(audio.audio.isEmpty); XCTAssertFalse(audio.boundaries.isEmpty)
        let decoded = try AVAudioPlayer(data: audio.audio, fileTypeHint: AVFileType.mp3.rawValue); XCTAssertGreaterThan(decoded.duration, 0)
    }
}
