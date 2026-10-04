import Libmpv

@MainActor
enum MPVConfiguration {
    // MPVKit's iOS build has no Lua/ytdl hook. URL extraction belongs to the
    // shared resolver; setting the absent ytdl option would abort mpv startup.
    static let options: [(String, String)] = [
        ("config", "no"), ("terminal", "no"), ("msg-level", "all=no"),
        ("vo", "libmpv"), ("hwdec", "auto-safe"), ("cache", "yes"),
        ("demuxer-max-bytes", "64MiB"), ("network-timeout", "60"),
        ("video-timing-offset", "0")
    ]

    static func createHandle(startMs: Double = 0) throws -> OpaquePointer {
        guard let handle = mpv_create() else { throw HarborError(code: "player-init") }
        do {
            for (name, value) in options { try check(mpv_set_option_string(handle, name, value)) }
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
