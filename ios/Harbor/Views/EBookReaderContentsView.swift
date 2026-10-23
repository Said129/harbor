import SwiftUI

struct EBookReaderContentsView: View {
    let publication: EBookPublication
    let volumes: [EBookVolume]
    let currentChapter: Int
    @Binding var selectedVolume: String?
    let selected: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    private var activeID: String? { publication.chapters.indices.contains(currentChapter) ? publication.chapters[currentChapter].id : nil }
    private var volume: EBookVolume? { volumes.first { $0.volume == selectedVolume } ?? volumes.first { $0.chapters.contains { $0["id"].string == activeID } } ?? volumes.first }
    private var chapters: [EBookChapter] {
        let known = Dictionary(publication.chapters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return volume?.chapters.compactMap { $0["id"].string.flatMap { known[$0] } } ?? []
    }
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if volumes.isEmpty { Text(text("This source returned no chapters for this title.")).foregroundStyle(.secondary) }
                    else {
                        if volumes.count > 1 {
                            Menu {
                                ForEach(volumes) { item in
                                    Button { selectedVolume = item.volume } label: {
                                        if item.volume == volume?.volume { Label(volumeLabel(item), systemImage: "checkmark") }
                                        else { Text(volumeLabel(item)) }
                                    }.accessibilityIdentifier("ebook-reader-volume-choice-" + item.volume)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "book")
                                    VStack(alignment: .leading, spacing: 5) { Text(volume.map(volumeLabel) ?? text("Chapters")).fontWeight(.semibold); Text(chapterCount(chapters.count)).font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Image(systemName: "chevron.down")
                                }.frame(minHeight: 44).padding(12).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
                            }.accessibilityIdentifier("ebook-reader-volume")
                        }
                        HStack {
                            Text(chapterCount(chapters.count))
                            Spacer()
                            if let index = chapters.firstIndex(where: { $0.id == activeID }) { Text("\(index + 1) / \(chapters.count)") }
                            else { Text(text("Select a chapter")) }
                        }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 8).accessibilityIdentifier("ebook-reader-chapter-position")
                        LazyVStack(spacing: 8) {
                            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                                Button {
                                    guard chapter.id != activeID, let target = publication.chapters.firstIndex(where: { $0.id == chapter.id }) else { return }
                                    selected(target); dismiss()
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(String(index + 1)).font(.caption.monospacedDigit()).frame(width: 28, height: 28)
                                            .background(chapter.id == activeID ? HarborTheme.accent : HarborTheme.surface, in: .circle)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(chapterTitle(chapter, index: index)).font(.subheadline.weight(.semibold)).lineLimit(2)
                                            Text(chapter.number.map { DesktopInterfaceText.value("Chapter {chapter}", variables: ["chapter": $0]) } ?? DesktopInterfaceText.value("Position {position}", variables: ["position": String(index + 1)])).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
                                        .background(chapter.id == activeID ? HarborTheme.accent.opacity(0.1) : .clear, in: .rect(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(chapter.id == activeID ? HarborTheme.accent.opacity(0.5) : .clear))
                                }.buttonStyle(.plain).accessibilityAddTraits(chapter.id == activeID ? [.isSelected] : [])
                                    .accessibilityIdentifier("ebook-reader-chapter-" + chapter.id).id(chapter.id)
                            }
                        }
                    }
                }.padding(20)
            }.background(HarborTheme.background).navigationTitle(volume.map(volumeLabel) ?? text("Chapters")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(text("Close chapters")) { dismiss() }.accessibilityIdentifier("ebook-reader-contents-close") } }
                .task {
                    await Task.yield()
                    guard !Task.isCancelled, let activeID, chapters.contains(where: { $0.id == activeID }) else { return }
                    proxy.scrollTo(activeID, anchor: .center)
                }
            }
        }
    }
    private func chapterCount(_ count: Int) -> String { DesktopInterfaceText.value(count == 1 ? "{count} chapter" : "{count} chapters", variables: ["count": String(count)]) }
    private func chapterTitle(_ chapter: EBookChapter, index: Int) -> String {
        let title = chapter.sourceTitle ?? chapter.title
        return title.isEmpty ? DesktopInterfaceText.value("Chapter {chapter}", variables: ["chapter": chapter.number ?? String(index + 1)]) : title
    }
    private func volumeLabel(_ volume: EBookVolume) -> String {
        if volume.volume.isEmpty { return text("Chapters") }
        if let number = volume.number {
            let value = number.formatted(.number.grouping(.never))
            if volume.label == "Volume " + value { return DesktopInterfaceText.value("Volume {number}", variables: ["number": value]) }
        }
        return volume.label
    }
}
