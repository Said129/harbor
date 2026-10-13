import XCTest
import GLKit
import UIKit
@testable import Harbor

final class SubtitleAutoSyncTests: XCTestCase {
    private func cues() -> [(Double, Double)] {
        let gaps = [4.3, 6.1, 3.2, 7.4, 5.0, 3.9, 8.2, 4.7, 6.6, 3.5, 5.8, 7.1]
        var time = 5.0
        return (0..<26).map { index in
            let start = time, duration = 1 + Double(index % 4) * 0.3
            time += duration + gaps[index % gaps.count]
            return (start, start + duration)
        }
    }
    func testRecoversOffsetAndFPSDriftAndDeclinesUnstructuredAudio() throws {
        let pairs = cues()
        let windows = [SubtitleAutoSync.Window(start: 0, length: 340)]
        let offset = try XCTUnwrap(SubtitleAutoSync.solve(audio: pairs.map { ($0.0 + 7.3, $0.1 + 7.3) }, cues: pairs, duration: 340, windows: windows))
        XCTAssertEqual(offset.offset, 7.3, accuracy: 0.15); XCTAssertEqual(offset.ratio, 1, accuracy: 0.001)
        let drift = try XCTUnwrap(SubtitleAutoSync.solve(audio: pairs.map { ($0.0 * 1.25, $0.1 * 1.25) }, cues: pairs, duration: 340, windows: windows))
        XCTAssertEqual(drift.ratio, 1.25, accuracy: 0.001)
        XCTAssertNil(try SubtitleAutoSync.solve(audio: [(0, 340)], cues: pairs, duration: 340, windows: windows))
        XCTAssertNil(try SubtitleAutoSync.solve(audio: [], cues: pairs, duration: .infinity, windows: windows))
    }
    func testTimingRewritePreservesTextAndVTTSettings() throws {
        let text = "WEBVTT\n\n00:01.000 --> 00:02.000 align:start\nOne\n\n00:03.000 --> 00:04.000\nTwo\n\n00:05.000 --> 00:06.000\nThree\n\n00:07.000 --> 00:08.000\nFour\n"
        let document = try SubtitleDocument(text)
        let output = document.applying(.init(offset: 2, ratio: 1.25, confidence: 0.9))
        XCTAssertTrue(output.contains("00:03.250 --> 00:04.500 align:start\nOne"))
        XCTAssertTrue(output.contains("00:10.750 --> 00:12.000\nFour"))
        let bom = try SubtitleDocument("\u{FEFF}" + text.replacingOccurrences(of: "\n", with: "\r\n"))
        XCTAssertTrue(bom.vtt)
        XCTAssertTrue(bom.applying(.init(offset: 2, ratio: 1.25, confidence: 0.9)).contains("00:03.250 --> 00:04.500 align:start\r\nOne"))
        XCTAssertEqual(try SubtitleAutoSync.decode(Data("Español · 日本語".utf8)), "Español · 日本語")
        let utf16 = Data([0xff, 0xfe]) + (try XCTUnwrap(text.data(using: .utf16LittleEndian)))
        XCTAssertTrue(try SubtitleAutoSync.decode(utf16).contains("WEBVTT"))
        XCTAssertThrowsError(try SubtitleAutoSync.decode(Data([0xff, 0x20, 0x41, 0x20])), "Unknown encodings must not silently corrupt the original text")
        XCTAssertThrowsError(try SubtitleDocument("No timing data"))
        XCTAssertTrue(SubtitleAutoSync.windows(900).allSatisfy { $0.start + $0.length <= 900 })
    }
    @available(iOS, deprecated: 12.0)
    @MainActor func testActualBundledMPVExtractsSpeechWithoutPlayingAudio() async throws {
        let pairs = cues()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("structured-speech.wav")
        let rate = 8_000, duration = 230
        var samples = Data(capacity: rate * duration * 2)
        var cue = 0
        for index in 0..<(rate * duration) {
            let time = Double(index) / Double(rate)
            while cue < pairs.count && pairs[cue].1 < time { cue += 1 }
            let active = cue < pairs.count && time >= pairs[cue].0 && time < pairs[cue].1
            var value = Int16(active ? sin(time * 2 * .pi * 600) * 12_000 : 0).littleEndian
            withUnsafeBytes(of: &value) { samples.append(contentsOf: $0) }
        }
        var wav = Data("RIFF".utf8)
        func integer<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) } }
        integer(UInt32(samples.count + 36)); wav.append(Data("WAVEfmt ".utf8)); integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1))
        integer(UInt32(rate)); integer(UInt32(rate * 2)); integer(UInt16(2)); integer(UInt16(16)); wav.append(Data("data".utf8)); integer(UInt32(samples.count)); wav.append(samples)
        try wav.write(to: url)
        let source = PlaybackSource(url: url.absoluteString, headers: nil, subtitles: nil, via: "test-fixture")
        let extracted: [(Double, Double)]
        do { extracted = try await Task.detached { try SubtitleAutoSync.speech(source, window: .init(start: 2, length: 225), audioID: nil) }.value }
        catch let error as HarborError { XCTFail("Native PCM extraction failed: " + error.code); return }
        XCTAssertEqual(extracted.count, pairs.count)
        XCTAssertEqual(try XCTUnwrap(extracted.first).0, pairs[0].0, accuracy: 0.15)
        let result = try XCTUnwrap(SubtitleAutoSync.solve(audio: extracted, cues: pairs.map { ($0.0 - 4, $0.1 - 4) }, duration: 230, windows: [.init(start: 2, length: 225)]))
        XCTAssertEqual(result.offset, 4, accuracy: 0.2)
        print("Native auto-sync: actual libmpv extracted \(extracted.count) intervals; recovered offset=\(result.offset), ratio=\(result.ratio), confidence=\(result.confidence)")

        func stamp(_ seconds: Double) -> String {
            let ms = Int((seconds * 1_000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1_000) % 60, ms % 1_000)
        }
        let input = directory.appendingPathComponent("offset-original.srt")
        let originalText = pairs.enumerated().map { "\($0.offset + 1)\n\(stamp($0.element.0 - 4)) --> \(stamp($0.element.1 - 4))\nKnown speech \($0.offset + 1)\n" }.joined(separator: "\n")
        try originalText.write(to: input, atomically: true, encoding: .utf8)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let state = PlayerState()
        let playback = PlaybackSource(url: url.absoluteString, headers: nil, subtitles: [.init(url: input.absoluteString, lang: "eng", id: "original")], via: "test-fixture")
        let controller = MPVController(source: playback, state: state, startPaused: true)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.loadViewIfNeeded()
        defer { controller.close(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let surface = try XCTUnwrap(controller.view as? GLKView)
        func wait(_ condition: () -> Bool) async throws {
            let end = Date().addingTimeInterval(30)
            while Date() < end && !condition() { surface.display(); try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertTrue(condition(), state.subtitleSyncMessage ?? state.subtitleIssue ?? state.error ?? "No native synchronization result")
        }
        try await wait { state.loaded && state.duration > 200 && state.tracks.contains { $0.type == "sub" } }
        let original = try XCTUnwrap(state.tracks.first { $0.type == "sub" })
        controller.selectSubtitle(String(original.id))
        try await wait { !state.subtitleChanging && state.primarySubtitle?.id == original.id }
        controller.synchronizeSubtitle()
        try await wait { !state.subtitleSyncing && !state.subtitleChanging && state.subtitleSyncOriginal == original.id }
        let synchronized = try XCTUnwrap(state.primarySubtitle)
        XCTAssertNotEqual(synchronized.id, original.id)
        XCTAssertEqual(try String(contentsOf: input, encoding: .utf8), originalText, "Automatic synchronization must not edit the source subtitle")
        let saved = synchronized.externalFilename.hasPrefix("file:") ? try XCTUnwrap(URL(string: synchronized.externalFilename)) : URL(fileURLWithPath: synchronized.externalFilename)
        let adjusted = try SubtitleDocument(String(contentsOf: saved, encoding: .utf8))
        XCTAssertEqual(try XCTUnwrap(adjusted.cues.first).start, pairs[0].0, accuracy: 0.2)
        controller.restoreSubtitleBeforeSync()
        try await wait { !state.subtitleChanging && state.primarySubtitle?.id == original.id && state.subtitleSyncOriginal == nil }
        XCTAssertTrue(state.loaded); XCTAssertNil(state.error); XCTAssertNil(state.subtitleIssue)
        print("Native auto-sync: applied acknowledged synchronized track, preserved original file and restored original track")
    }
}
