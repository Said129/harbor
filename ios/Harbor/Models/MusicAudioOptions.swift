import Foundation
import Observation

struct MusicPEQFilter: Codable, Equatable, Sendable, Identifiable {
    var type = "peak"
    var frequency = 1000.0
    var gain = 0.0
    var q = 0.7071
    var enabled = true
    var id: String { type + "|" + String(frequency) + "|" + String(q) }
}
struct MusicAudioOptions: Codable, Equatable, Sendable {
    var device = "auto"
    var eqEnabled = false
    var eqBands = Array(repeating: 0.0, count: 10)
    var boostEnabled = false
    var volumeLimit = 1.0
    var balance = 0.0
    var autoHeadroom = true
    var equipmentLabel = ""
    var replayGain = "off"
    var eqMode = "graphic"
    var peqFilters: [MusicPEQFilter] = []
    var eqStrength = 1.0
    var preampDb = 0.0
    var crossfeed = 0.0
    var dspBypass = false
    var exclusive = false
    var sampleRate = 0
    var speed = 1.0
    var keepPitch = false
    var reverb = 0.0
    var pitch = 0.0
    var broadcastEnabled = false
    var broadcastDevice = "auto"
    // These filters are present in the pinned MPVKit build. Keep the full
    // Desktop document so unsupported effects are never silently discarded.
    var supported: Bool {
        dspBypass || reverb == 0 && crossfeed == 0 && (eqMode != "parametric" || peqFilters.filter(\.enabled).allSatisfy { $0.type == "peak" })
    }
}
struct MusicAudioSignal: Sendable {
    let codec: String?
    let sourceRate: Double?
    let outputRate: Double?
    let sourceChannels: String?
    let outputChannels: String?
    let format: String?
    let bitrate: Double?
    let backend: String?
    let filters: String?
    let speed: Double?
    let replayGain: String?
}
struct MusicAudioEffects: Codable, Equatable, Sendable {
    var kind = "off"
    var depth = 0.5
    var beats = 0.5
    var bpm = 120.0
}
struct MusicAudioPlan: Codable, Equatable, Sendable {
    let filter: String
    let settings: MusicAudioOptions
    let effects: MusicAudioEffects
    static let defaults = MusicAudioPlan(filter: "", settings: .init(), effects: .init())
    var volumeMaximum: Double { settings.boostEnabled ? 100 * settings.volumeLimit : 100 }
}

struct MusicEQPreset: Decodable, Identifiable, Sendable {
    let id: String
    let labelKey: String
    let bands: [Double]
    let filters: [MusicPEQFilter]
}
struct MusicEQPresetCatalog: Decodable, Sendable {
    let reference: String
    let frequencies: [Double]
    let presets: [MusicEQPreset]
    static let original: MusicEQPresetCatalog? = {
        guard let url = Bundle.main.url(forResource: "MusicEQPresets", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data),
              value.reference == "0834340cec5531650bfe78cd628628702e636987", value.frequencies.count == 10,
              value.presets.allSatisfy({ $0.bands.count == 10 }) else { return nil }
        return value
    }()
    static let frequencies = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
}
struct MusicListeningProfile: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let settings: MusicAudioOptions
    func loading(into current: MusicAudioOptions) -> MusicAudioOptions {
        var value = settings
        value.device = current.device; value.exclusive = current.exclusive; value.sampleRate = current.sampleRate
        value.boostEnabled = current.boostEnabled; value.volumeLimit = current.volumeLimit
        return value
    }
}

@MainActor @Observable final class MusicAudioPreferences {
    let owner: String
    private(set) var options: MusicAudioOptions
    private(set) var error = false
    private(set) var revision = UUID()
    private(set) var profiles: [MusicListeningProfile] = []
    private(set) var profilesReady = false
    private var key: String { "music-audio-options-" + EBookShelf.hash(owner) }
    private var profileKey: String { "music-listening-profiles-" + EBookShelf.hash(owner) }
    init(owner: String) {
        self.owner = owner
        do { options = try KeychainStore().read("music-audio-options-" + EBookShelf.hash(owner), as: MusicAudioOptions.self) ?? .init() }
        catch { options = .init(); error = true }
        options.eqBands = (0..<10).map { options.eqBands.indices.contains($0) ? min(12, max(-12, options.eqBands[$0])) : 0 }
        do {
            profiles = Array((try KeychainStore().read(profileKey, as: [MusicListeningProfile].self) ?? []).prefix(20))
            profilesReady = true
        } catch { error = true }
    }
    func plan(_ supplied: MusicAudioOptions? = nil) async throws -> MusicAudioPlan {
        let value = supplied ?? options
        return try await CoreBridge().call("musicAudioPlan", ["settings": try .encoded(value)])
    }
    func save(_ plan: MusicAudioPlan) throws {
        guard plan.settings.supported, plan.effects.kind == "off" else { throw HarborError(code: "music-audio-unavailable") }
        try KeychainStore().write(plan.settings, key: key)
        options = plan.settings; error = false; revision = UUID()
    }
    func saveProfile(name: String, settings: MusicAudioOptions) throws {
        let name = String(name.filter { !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard profilesReady, profiles.count < 20, !name.isEmpty else { throw HarborError(code: "music-audio-profile") }
        let values = profiles + [MusicListeningProfile(id: UUID().uuidString, name: name, settings: settings)]
        try KeychainStore().write(values, key: profileKey); profiles = values
    }
    func deleteProfile(_ id: String) throws {
        guard profilesReady else { throw HarborError(code: "music-audio-profile") }
        let values = profiles.filter { $0.id != id }
        try KeychainStore().write(values, key: profileKey); profiles = values
    }
}
