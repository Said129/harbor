import SwiftUI

/// Desktop's "Live TV" row in search (`src/components/search/live-tv-row.tsx`, placed before people in
/// `search-overlay.tsx`): channels from the person's Live TV lists whose name or group matches the query.
/// Channels come from the existing Live TV lists and play through the same path as the Live TV screen.
struct SearchLiveTVSection: View {
    let app: AppModel
    let query: String
    @State private var channels: [LiveChannel] = []
    @State private var playback: PlaybackSession?
    @State private var playing: LiveChannel?
    @State private var message: String?

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searchable: Bool { trimmed.utf16.count >= 2 }
    private var hits: [LiveChannel] { LiveTVSearch.channels(matching: trimmed, in: channels) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !hits.isEmpty {
                Text(DesktopInterfaceText.value("Live TV"))
                    .font(HarborTheme.font(12, weight: .medium)).tracking(2.5).textCase(.uppercase)
                    .foregroundStyle(.secondary)
                ForEach(hits) { channel in
                    hitRow(channel)
                }
            }
            if let message {
                Text(message).font(HarborTheme.font(13)).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .task(id: searchable) { if searchable { await loadChannels() } }
        .fullScreenCover(item: $playback) { session in
            PlayerView(session: session, resume: app.resume, title: playing?.name ?? DesktopInterfaceText.value("Live TV"), media: playing?.media)
        }
    }

    private func hitRow(_ channel: LiveChannel) -> some View {
        Button { Task { await play(channel) } } label: {
            HStack(spacing: 12) {
                if let logo = channel.logo {
                    Artwork(url: logo, fit: .fit, maxPixels: 180).frame(width: 44, height: 40)
                } else {
                    Image("nav-livetv").resizable().scaledToFit().frame(width: 28, height: 28).frame(width: 44, height: 40)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name).font(HarborTheme.font(15, weight: .semibold)).lineLimit(1)
                    if let group = channel.group {
                        Text(group).font(HarborTheme.font(12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HarborTheme.ink.opacity(0.06), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(HarborTheme.ink)
        .accessibilityIdentifier("search-live-tv-channel")
    }

    /// Reads the cached or freshly downloaded lists through `LivePlaylistService`, as the Live TV screen does.
    private func loadChannels() async {
        guard searchable else { return }
        let preferences = LiveTVPreferences(owner: app.settingsOwner)
        guard preferences.ready else { return }
        var loaded: [LiveChannel] = []
        for source in preferences.sources {
            do {
                let entries = try await LivePlaylistService.shared.load(source, owner: preferences.owner, refresh: false)
                loaded += entries.filter { VODTitles.kind($0) == "live" }
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
        channels = loaded
    }

    /// Same playback path as `LiveTVView.play`: resolve the channel as an addon stream, then open the player.
    private func play(_ channel: LiveChannel) async {
        let owner = app.accountOperationScope
        do {
            guard !channel.drm else { throw HarborError(code: "iptv-drm") }
            let headers = JSONValue.object(channel.headers.mapValues(JSONValue.string))
            let stream: JSONValue = .object(["addonId": .string("iptv:" + channel.source), "addonName": .string(DesktopInterfaceText.value("Live TV")), "url": .string(channel.url), "behaviorHints": .object(["proxyHeaders": .object(["request": headers])])])
            let resolved = try await app.service.resolve(StreamOffer(id: 0, raw: stream))
            guard owner == app.accountOperationScope else { return }
            playing = channel
            playback = PlaybackSession(source: resolved, target: ResumeTarget(id: "iptv:" + channel.id), startMs: 0, storageWarning: nil, progressEnabled: false, owner: owner)
        } catch is CancellationError {
            return
        } catch {
            message = safeMessage(error)
        }
    }
}
