import Foundation
import Libmpv

enum HardwareDecoding: String, CaseIterable, Identifiable, Sendable {
    case auto, on, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Automática"
        case .on: "Activada"
        case .off: "Software"
        }
    }
    // The direct iOS VideoToolbox/GLES mapper cannot import every pixel format.
    // Copy-back retains hardware decoding without handing CVPixelBuffers to it.
    var mpvValue: String {
#if targetEnvironment(simulator)
        // MPVKit's iOS demo also disables VideoToolbox on simulator. Its
        // virtual decoder does not establish physical iPhone compatibility.
        "no"
#else
        self == .off ? "no" : "videotoolbox-copy"
#endif
    }
}

@MainActor
enum MPVConfiguration {
    // MPVKit's iOS build has no Lua/ytdl hook. URL extraction belongs to the
    // shared resolver; setting the absent ytdl option would abort mpv startup.
    static let options: [(String, String)] = [
        ("config", "no"), ("terminal", "no"), ("msg-level", "all=no"),
        ("vo", "libmpv"), ("gpu-hwdec-interop", "no"), ("cache", "yes"),
        ("demuxer-max-bytes", "64MiB"), ("network-timeout", "60"),
        ("video-timing-offset", "0")
    ]

    static func createHandle(startMs: Double = 0, decoding: HardwareDecoding? = nil, playback: PlaybackOptions? = nil, startPaused: Bool = false) throws -> OpaquePointer {
        guard let handle = mpv_create() else { throw HarborError(code: "player-init") }
        do {
            for (name, value) in options { try check(mpv_set_option_string(handle, name, value)) }
#if targetEnvironment(simulator)
            // A virtual GL driver may need software rendering. Permit it only
            // on simulators; physical iPhone output keeps its validated path.
            try check(mpv_set_option_string(handle, "gpu-sw", "yes"))
            // Both actual decoder formats reach yuv420p after conversion, yet
            // the Intel software GLES plane/shader path still loses pixels.
            // Upload packed RGBA on simulators; physical iPhone retains its
            // validated decoder/render/HDR path and the inputs are unchanged.
            try check(mpv_set_option_string(handle, "vf", "format=fmt=rgba"))
            try check(mpv_set_option_string(handle, "sws-allow-zimg", "no"))
#endif
            let selected = decoding ?? HardwareDecoding(rawValue: UserDefaults.standard.string(forKey: "mpvHwdec") ?? "auto") ?? .auto
            try check(mpv_set_option_string(handle, "hwdec", selected.mpvValue))
            // Desktop's HDR-to-SDR block comes first, so the mpvQuality lines below still win on the shared keys, as on Desktop.
            for (name, value) in UISettingsPolicy.hdrToSdrMpvOptions(UserDefaults.standard.bool(forKey: UISettingsPolicy.hdrToSdrKey)) {
                _ = mpv_set_option_string(handle, name, value)
            }
            // Desktop's mpvQuality lines (`mpv-tuning.ts`). An option this mpv build refuses is ignored, so it cannot stop playback.
            for (name, value) in UISettingsPolicy.mpvQualityOptions(UserDefaults.standard.string(forKey: UISettingsPolicy.mpvQualityKey)) {
                _ = mpv_set_option_string(handle, name, value)
            }
            let settings = playback ?? PlaybackPreferences.shared.options
            // Xcode copies registered fonts into the bundle resource root.
            if let fonts = Bundle.main.url(forResource: "Inter", withExtension: "ttf") {
                // The person's own subtitle fonts live in a folder of their own, beside copies of the bundled families.
                // If that folder cannot be prepared or mpv refuses it, the bundled folder is used, so a font never stops playback.
                let owner = MetadataPreferences.shared.settingsOwner ?? "guest"
                var customApplied = false
                if let custom = SubtitleFontStore.shared.playerDirectory(owner: owner) {
                    customApplied = mpv_set_option_string(handle, "sub-fonts-dir", custom.path) >= 0
                }
                if !customApplied {
                    try check(mpv_set_option_string(handle, "sub-fonts-dir", fonts.deletingLastPathComponent().path))
                }
            }
            // Desktop's `mpvBufferBoost` gives `large` when no size is chosen. Its memory is bounded by `BufferSize`'s budget.
            let boost = UserDefaults.standard.bool(forKey: BufferSize.boostKey)
            for (name, value) in BufferSize.effective(settings.bufferSize, boost: boost).mpvOptions + settings.mpvOptions {
                try check(mpv_set_option_string(handle, name, value))
            }
            if startMs.isFinite && startMs > 0 {
                try check(mpv_set_option_string(handle, "start", String(startMs / 1000)))
            }
            if startPaused { try check(mpv_set_option_string(handle, "pause", "yes")) }
            try check(mpv_initialize(handle))
            return handle
        } catch {
            destroy(handle)
            throw error
        }
    }

    static func destroy(_ handle: OpaquePointer) { mpv_terminate_destroy(handle) }

    private static func check(_ status: Int32) throws {
        guard status >= 0 else {
            Diagnostics.shared.record(.playerFailed, count: Int(status))
            throw HarborError(code: "mpv-\(status)")
        }
    }
}
