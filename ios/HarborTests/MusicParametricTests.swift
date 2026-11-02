import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor final class MusicParametricTests: XCTestCase {
    func testOriginalAPOCorrectionExportRetainsStrengthHeadroomAndProfileRouting() async throws {
        let processor = MusicParametricEQ()
        let imported = try processor.importText("""
        # Owned correction, not a device measurement
        Preamp: -3.0 dB
        Filter 1: ON PK Fc 1000 Hz Gain 6 dB Q 1
        Filter 2: ON LSC Fc 100 Hz Gain 2 dB Q 0.7071
        Filter 3: OFF HSC Fc 8000 Hz Gain -2 dB Q 0.7071
        Filter 4: ON LP Fc 16000 Hz Q 0.7071
        Filter 5: ON HP Fc 30 Hz Q 0.7071
        Filter 6: ON NO Fc 3000 Hz Q 2
        """)
        var current = MusicAudioOptions()
        current.device = "auto"; current.sampleRate = 96000; current.volumeLimit = 1
        var settings = imported.loading(into: current)
        XCTAssertEqual(settings.peqFilters.count, 6)
        XCTAssertEqual(settings.sampleRate, 96000); XCTAssertEqual(settings.device, "auto")
        XCTAssertFalse(settings.autoHeadroom); XCTAssertEqual(settings.eqStrength, 1)
        XCTAssertEqual(settings.preampDb, -3); XCTAssertTrue(settings.eqEnabled)
        XCTAssertEqual(settings.eqMode, "parametric")
        settings.eqStrength = 0.5; settings.autoHeadroom = true
        let response = try processor.response(settings, applied: .init())
        XCTAssertEqual(response.draft.count, 361); XCTAssertEqual(response.applied.count, 361)
        XCTAssertTrue(response.draft.allSatisfy(\.isFinite))
        XCTAssertTrue(response.applied.allSatisfy { $0 == 0 })
        XCTAssertGreaterThan(response.headroom, 2)
        let exported = try processor.exportText(settings), roundTrip = try processor.importText(exported)
        XCTAssertEqual(roundTrip.filters[0].gain, 3, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.filters[1].gain, 1, accuracy: 0.0001)
        XCTAssertFalse(roundTrip.filters[2].enabled)
        XCTAssertEqual(roundTrip.preampDb, -3 - response.headroom, accuracy: 0.01)
        let plan: MusicAudioPlan = try await CoreBridge().call("musicAudioPlan", ["settings": try .encoded(settings)])
        for name in ["equalizer", "bass", "lowpass", "highpass", "bandreject"] { XCTAssertTrue(plan.filter.contains(name), name) }
        XCTAssertFalse(plan.filter.contains("treble"))
        XCTAssertEqual(plan.settings.sampleRate, 96000)
        settings.eqStrength = 0
        let bypassed = try processor.response(settings, applied: settings)
        XCTAssertTrue(bypassed.draft.allSatisfy { $0 == 0 })
        XCTAssertEqual(bypassed.headroom, 0)
        let off = try processor.importText(processor.exportText(settings))
        XCTAssertTrue(off.filters.allSatisfy { !$0.enabled })
        for bad in [
            "Preamp: 13 dB\nFilter 1: ON PK Fc 1000 Hz Gain 0 dB Q 1",
            "Filter 1: ON PK Fc 19 Hz Gain 0 dB Q 1",
            "Filter 1: ON PK Fc 1000 Hz Gain 19 dB Q 1",
            "Filter 1: ON PK Fc 1000 Hz Gain 0 dB Q 0.01",
            "Include: private-file.txt",
            String(repeating: "x", count: 32769),
            (1...25).map { "Filter \($0): ON PK Fc 1000 Hz Gain 0 dB Q 1" }.joined(separator: "\n")
        ] { XCTAssertThrowsError(try processor.importText(bad)) }
        // A rejected edit must not poison the reusable pure context.
        XCTAssertEqual(try processor.importText(exported).filters.count, 6)
    }

    func testParametricResponseAndNumericEditorRenderOnPhoneTabletAndRightToLeft() async throws {
        var options = MusicAudioOptions()
        options.eqEnabled = true; options.eqMode = "parametric"
        options.peqFilters = [.init(gain: 6), .init(type: "lowShelf", frequency: 100, gain: -3)]
        let frozen = options
        for (name, size) in [("phone", CGSize(width: 390, height: 844)), ("tablet", CGSize(width: 1024, height: 1366))] {
            try await capture(NavigationStack { Form { MusicParametricEditor(draft: .constant(frozen), applied: .init()) } }, name: "parametric-" + name, size: size)
            try await capture(NavigationStack { MusicParametricFilterEditor(filter: .constant(frozen.peqFilters[0]), index: 0) }, name: "parametric-filter-" + name, size: size)
        }
        try await capture(NavigationStack { Form { MusicParametricEditor(draft: .constant(frozen), applied: frozen) } }.environment(\.layoutDirection, .rightToLeft),
                          name: "parametric-rtl-phone", size: CGSize(width: 390, height: 844))
        for code in InterfaceLanguage.all.map(\.code) {
            for key in ["music.lab.parametric", "music.lab.importHelp", "music.lab.crossfeedHelp", "music.speed.slowedReverb"] {
                XCTAssertNotEqual(DesktopInterfaceText.value(key, language: code), key, "\(code) \(key)")
            }
        }
    }

    func testSavedSpeedCombinationsReplaceByNameKeepOtherDSPAndRemainProfileOwned() throws {
        let owner = "owned-speed-" + UUID().uuidString, other = owner + "-other"
        defer {
            for value in [owner, other] { try? KeychainStore().remove("music-speed-presets-" + EBookShelf.hash(value)) }
        }
        let preferences = MusicAudioPreferences(owner: owner)
        var settings = MusicAudioOptions()
        settings.speed = 0.8; settings.reverb = 0.6; settings.pitch = -2; settings.keepPitch = true
        try preferences.saveSpeedPreset(name: " Owned combo ", settings: settings)
        settings.speed = 0.9
        try preferences.saveSpeedPreset(name: "Owned combo", settings: settings)
        let reloaded = MusicAudioPreferences(owner: owner)
        XCTAssertEqual(reloaded.speedPresets.count, 1)
        XCTAssertTrue(MusicAudioPreferences(owner: other).speedPresets.isEmpty)
        var routing = MusicAudioOptions()
        routing.eqEnabled = true; routing.eqBands[2] = -4; routing.preampDb = -3
        routing.sampleRate = 96000; routing.balance = 0.5; routing.volumeLimit = 1.5
        let preset = try XCTUnwrap(reloaded.speedPresets.first), loaded = preset.loading(into: routing)
        XCTAssertEqual(loaded.speed, 0.9); XCTAssertEqual(loaded.reverb, 0.6)
        XCTAssertEqual(loaded.pitch, -2); XCTAssertTrue(loaded.keepPitch)
        XCTAssertEqual(loaded.eqBands, routing.eqBands); XCTAssertEqual(loaded.preampDb, -3)
        XCTAssertEqual(loaded.sampleRate, 96000); XCTAssertEqual(loaded.volumeLimit, 1.5)
        XCTAssertEqual(loaded.balance, 0.5); XCTAssertTrue(loaded.eqEnabled)
        settings.speed = .nan
        XCTAssertThrowsError(try reloaded.saveSpeedPreset(name: "Invalid", settings: settings))
        XCTAssertEqual(MusicAudioPreferences(owner: owner).speedPresets.count, 1)
        try reloaded.deleteSpeedPreset(preset.id)
        XCTAssertTrue(MusicAudioPreferences(owner: owner).speedPresets.isEmpty)
    }

    private func capture<V: View>(_ view: V, name: String, size: CGSize) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: view.preferredColorScheme(.dark))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(600))
        let image = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) }
        XCTAssertEqual(image.size, size)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
