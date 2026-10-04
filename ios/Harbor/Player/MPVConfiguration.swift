import Libmpv

enum MPVConfiguration {
    // MPVKit's iOS build has no Lua/ytdl hook. URL extraction belongs to the
    // shared resolver; setting the absent ytdl option would abort mpv startup.
    static let options: [(String, String)] = [
        ("config", "no"), ("terminal", "no"), ("msg-level", "all=no"),
        ("vo", "libmpv"), ("hwdec", "auto-safe"), ("cache", "yes"),
        ("demuxer-max-bytes", "64MiB"), ("network-timeout", "60"),
        ("video-timing-offset", "0")
    ]
}
