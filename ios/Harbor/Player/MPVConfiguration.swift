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

    static func createHandle(startMs: Double = 0, decoding: HardwareDecoding? = nil, playback: PlaybackOptions? = nil) throws -> OpaquePointer {
        guard let handle = mpv_create() else { throw HarborError(code: "player-init") }
        do {
            for (name, value) in options { try check(mpv_set_option_string(handle, name, value)) }
#if targetEnvironment(simulator)
            // A virtual GL driver may need software rendering. Permit it only
            // on simulators; physical iPhone output keeps its validated path.
            try check(mpv_set_option_string(handle, "gpu-sw", "yes"))
            // Apple's Intel software GLES driver renders 8-bit planes, but the
            // observed 10-bit path stays black. Convert decoded simulator frames
            // before uploading; device decoding/HDR processing is unchanged.
            try check(mpv_set_option_string(handle, "vf", "format=fmt=yuv420p"))
            // Conversion now produces colors but a regular black grid on the
            // Intel simulator. Use libswscale rather than the optional zimg
            // repacker there, and retain the same actual input/pixel checks.
            try check(mpv_set_option_string(handle, "sws-allow-zimg", "no"))
#endif
            let selected = decoding ?? HardwareDecoding(rawValue: UserDefaults.standard.string(forKey: "mpvHwdec") ?? "auto") ?? .auto
            try check(mpv_set_option_string(handle, "hwdec", selected.mpvValue))
            let settings = playback ?? PlaybackPreferences.shared.options
            // Xcode copies registered fonts into the bundle resource root.
            if let fonts = Bundle.main.url(forResource: "Inter", withExtension: "ttf") {
                try check(mpv_set_option_string(handle, "sub-fonts-dir", fonts.deletingLastPathComponent().path))
            }
            for (name, value) in settings.bufferSize.mpvOptions + settings.mpvOptions {
                try check(mpv_set_option_string(handle, name, value))
            }
            if startMs.isFinite && startMs > 0 {
                try check(mpv_set_option_string(handle, "start", String(startMs / 1000)))
            }
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
