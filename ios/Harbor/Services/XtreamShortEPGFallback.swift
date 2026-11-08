import Foundation

/// Desktop's Xtream short-EPG fallback: `hydrateShortEpg` (`src/lib/iptv/xtream-short-epg.ts`) and the
/// `useXtreamEpgFallback` gate (`src/views/live/hooks/use-xtream-epg-fallback.ts`).
/// Only the first 120 channels are looked at, a guide that already has programmes is left alone, and a
/// request that fails or returns nothing leaves that channel without programmes instead of stopping the rest.
enum XtreamShortEPGFallback {
    static let maximumChannels = 120
    /// The attribute `XtreamClient.live` sets on every Xtream channel: its stream id.
    static let streamIDAttribute = "xtream-stream-id"

    static func hydrate(_ channels: [LiveChannel], base: [String: [LiveProgram]], fetch: (LiveChannel) async throws -> [LiveProgram]) async -> [String: [LiveProgram]] {
        guard base.isEmpty else { return base }
        var output = base
        for channel in channels.prefix(maximumChannels) {
            guard channel.attributes[streamIDAttribute] != nil else { continue }
            let key: String
            if let tvgID = channel.tvgID, !tvgID.isEmpty { key = tvgID } else { key = channel.id }
            if output[key]?.isEmpty == false { continue }
            let rows = (try? await fetch(channel)) ?? []
            guard !rows.isEmpty else { continue }
            output[key] = rows.sorted { $0.start < $1.start }
        }
        return output
    }
}
