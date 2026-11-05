import SwiftUI

/// Desktop's URL and magnet cards in Search (`url-card.tsx`, `magnet-card.tsx`): a pasted link gets a
/// card with a Play button instead of a catalog search. Torrent links play through the profile's
/// debrid services, since the iPhone has no torrent engine.
struct SearchLinkCard: View {
    let app: AppModel
    let input: SearchInput
    @State private var playback: PlaybackSession?
    @State private var busy = false
    @State private var message: String?
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    private var magnet: ParsedMagnet? { if case .magnet(let raw) = input { TorrentLink.parseMagnet(raw) } else { nil } }
    private var title: String {
        switch input {
        case .directURL(let url): TorrentLink.fileTitle(url, fallback: text("Direct stream"))
        case .magnet: magnet?.name ?? text("Magnet stream")
        case .query: ""
        }
    }

    var body: some View {
        Group {
            if case .magnet = input, magnet == nil {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 22)).foregroundStyle(.secondary)
                    Text(text("That does not look like a valid magnet link or infohash.")).font(HarborTheme.font(14)).foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("search-link-invalid")
            } else {
                HStack(spacing: 14) {
                    Image(systemName: isMagnet ? "magnet" : "link").font(.system(size: 20, weight: .semibold)).foregroundStyle(HarborTheme.accent)
                        .frame(width: 44, height: 44).background(HarborTheme.accent.opacity(0.18), in: .circle).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(text(isMagnet ? "Torrent link" : "Direct link")).font(HarborTheme.font(11, weight: .semibold)).tracking(2).textCase(.uppercase)
                            .foregroundStyle(HarborTheme.accent)
                        Text(title).font(HarborTheme.font(15, weight: .semibold)).lineLimit(2)
                        Text(subtitle).font(HarborTheme.font(12.5)).foregroundStyle(message == nil ? ThemePreferences.shared.color("ink-subtle") : Color.orange)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { Task { await play() } } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().controlSize(.small) } else { Image("ui-play-filled").resizable().scaledToFit().frame(width: 16, height: 16) }
                            Text(text(busy ? "Starting" : "Play")).font(HarborTheme.font(15, weight: .semibold))
                        }.padding(.horizontal, 18).frame(minHeight: 48).foregroundStyle(HarborTheme.background).background(HarborTheme.ink, in: .capsule)
                    }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("search-link-play")
                }.padding(16).background(HarborTheme.accent.opacity(0.08), in: .rect(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(HarborTheme.accent.opacity(0.4), lineWidth: 1) }
                    .accessibilityIdentifier("search-link-card")
            }
        }
        .fullScreenCover(item: $playback) { session in PlayerView(session: session, resume: app.resume, title: title, media: nil) }
    }

    private var isMagnet: Bool { if case .magnet = input { true } else { false } }
    private var subtitle: String {
        if let message { return message }
        if case .directURL(let url) = input { return url }
        return text("Torrent links play through a debrid service. Add one in Settings › Streaming sources.")
    }

    private func play() async {
        guard !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        let owner = app.accountOperationScope
        do {
            let source: PlaybackSource, id: String
            switch input {
            case .directURL(let url):
                let stream: JSONValue = .object(["addonId": .string("link"), "addonName": .string(text("Direct link")), "url": .string(url)])
                source = try await app.service.resolve(StreamOffer(id: 0, raw: stream))
                id = "url:" + url
            case .magnet:
                guard let magnet else { throw HarborError(code: "no-source") }
                let stream: JSONValue = .object(["addonId": .string("magnet"), "addonName": .string(text("Torrent link")), "infoHash": .string(magnet.infoHash), "title": .string(magnet.name ?? "")])
                source = try await app.service.resolve(StreamOffer(id: 0, raw: stream), debrid: app.debridClient())
                id = "magnet:" + magnet.infoHash
            case .query:
                return
            }
            try Task.checkCancellation()
            guard owner == app.accountOperationScope else { return }
            playback = PlaybackSession(source: source, target: ResumeTarget(id: id), startMs: 0, storageWarning: nil, progressEnabled: false, owner: owner)
        } catch is CancellationError {
            return
        } catch {
            message = safeMessage(error)
        }
    }
}
