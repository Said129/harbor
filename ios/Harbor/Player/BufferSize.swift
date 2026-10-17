import Foundation

enum BufferSize: String, CaseIterable, Codable, Identifiable {
    case auto, small, medium, large, max
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Automático"
        case .small: "Pequeño · 1 minuto"
        case .medium: "Mediano · 5 minutos"
        case .large: "Grande · 10 minutos"
        case .max: "Máximo · 30 minutos"
        }
    }

    var mpvOptions: [(String, String)] {
        guard self != .auto else { return [] }
        let profile: (seconds: Int, readahead: Int, forward: UInt64, back: UInt64, wait: Int)
        let mib: UInt64 = 1024 * 1024
        switch self {
        case .small: profile = (60, 20, 150 * mib, 32 * mib, 0)
        case .medium: profile = (300, 120, 512 * mib, 64 * mib, 4)
        case .large: profile = (600, 600, 1024 * mib, 128 * mib, 10)
        case .max: profile = (1800, 1800, 2048 * mib, 256 * mib, 20)
        case .auto: return []
        }
        // Retain Desktop's durations while bounding total cache memory for an
        // iPhone process. Allocating its 2 GiB maximum risks an OS termination.
        let budget = Swift.max(96 * mib, Swift.min(512 * mib, ProcessInfo.processInfo.physicalMemory / 12))
        let back = Swift.min(profile.back, budget / 5)
        let forward = Swift.min(profile.forward, budget - back)
        return [("cache", "yes"), ("cache-secs", String(profile.seconds)),
                ("demuxer-readahead-secs", String(profile.readahead)),
                ("demuxer-max-bytes", String(forward)), ("demuxer-max-back-bytes", String(back)),
                ("cache-pause-initial", profile.wait > 0 ? "yes" : "no"),
                ("cache-pause-wait", String(profile.wait))]
    }
}
