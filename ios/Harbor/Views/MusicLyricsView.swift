import SwiftUI

@MainActor struct MusicLyricsView: View {
    @Bindable var player: MusicPlayback
    let client: MusicLyricsClient?
    @State private var lines: [MusicLyricLine] = []
    @State private var loading = false
    @State private var follow = true
    @State private var offset = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var active: Int? { MusicLyricsTiming.index(lines, at: max(0, player.position - offset)) }
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 12) {
                if loading { ProgressView() }
                else if lines.isEmpty { Text(DesktopInterfaceText.value("No lyrics for this track")).foregroundStyle(.secondary) }
                else {
                    Toggle(DesktopInterfaceText.value("music.lyrics.follow"), isOn: $follow)
                    HStack {
                        Text(DesktopInterfaceText.value("Lyric sync")); Spacer()
                        Button { adjust(-0.25) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("Lyrics earlier"))
                        Text(String(format: "%+.2fs", offset)).font(.caption.monospacedDigit()).frame(minWidth: 64)
                        Button { adjust(0.25) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("Lyrics later"))
                    }.buttonStyle(.borderless)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Button { player.seek(max(0, line.at + offset)) } label: {
                                    Text(line.text.isEmpty ? "♪" : line.text).font(.title3.weight(active == index ? .bold : .regular))
                                        .foregroundStyle(active == index ? HarborTheme.ink : .secondary).frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(minHeight: 44).contentShape(.rect)
                                }.buttonStyle(.plain).id(index)
                            }
                        }.padding(.vertical, 16)
                    }.frame(height: 320)
                }
                Link("LRCLIB", destination: URL(string: "https://lrclib.net")!).font(.caption)
            }.onChange(of: active) { _, index in
                guard follow, let index else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { proxy.scrollTo(index, anchor: .center) }
            }
        }.task(id: player.currentItem?.id) {
            lines = []; loading = true; defer { loading = false }
            guard let track = player.currentTrack, let client else { return }
            offset = MusicLyricOffsets.value(track, owner: player.owner)
            do { let value = try await client.load(track); try Task.checkCancellation(); lines = value ?? [] }
            catch { }
        }.accessibilityIdentifier("music-lyrics")
    }
    private func adjust(_ amount: Double) {
        guard let track = player.currentTrack else { return }
        offset = MusicLyricOffsets.set(offset + amount, track: track, owner: player.owner)
    }
}

enum MusicLyricOffsets {
    private struct Entry: Codable { let key: String; let value: Double }
    private static func key(_ owner: String) -> String { "harbor.music.lyric-offset.v1." + EBookShelf.hash(owner) }
    private static func identity(_ track: MusicTrack) -> String { EBookShelf.hash((track.connectorId ?? "") + ":" + (track.sourceId ?? track.id)) }
    static func value(_ track: MusicTrack, owner: String, storage: UserDefaults = .standard) -> Double {
        guard let data = storage.data(forKey: key(owner)), let values = try? JSONDecoder().decode([Entry].self, from: data) else { return 0 }
        let value = values.last { $0.key == identity(track) }?.value ?? 0
        return value.isFinite ? min(8, max(-8, value)) : 0
    }
    @discardableResult static func set(_ input: Double, track: MusicTrack, owner: String, storage: UserDefaults = .standard) -> Double {
        let value = input.isFinite ? floor(min(8, max(-8, input)) / 0.25 + 0.5) * 0.25 : 0
        var values = storage.data(forKey: key(owner)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        values.removeAll { $0.key == identity(track) }
        if value != 0 { values.append(.init(key: identity(track), value: value)) }
        if let data = try? JSONEncoder().encode(Array(values.suffix(200))) { storage.set(data, forKey: key(owner)) }
        return value
    }
}
