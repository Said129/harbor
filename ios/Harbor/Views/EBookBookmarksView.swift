import SwiftUI

struct EBookBookmarksView: View {
    let items: [EBookBookmark]
    let publication: EBookPublication
    let volumes: [EBookVolume]
    let selected: (EBookBookmark, Int) -> Void
    let removed: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if items.isEmpty { Text(text("No saved passages yet.")).foregroundStyle(.secondary).accessibilityIdentifier("ebook-bookmarks-empty") }
                    ForEach(items) { bookmark in
                        let index = EBookBookmarks.chapter(bookmark, in: publication)
                        HStack(alignment: .top, spacing: 4) {
                            Button {
                                guard let index else { return }
                                selected(bookmark, index); dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    ViewThatFits(in: .horizontal) {
                                        HStack(spacing: 6) { badges(bookmark, index: index) }
                                        VStack(alignment: .leading, spacing: 6) { badges(bookmark, index: index) }
                                    }
                                    Text(bookmark.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
                            }.buttonStyle(.plain).disabled(index == nil).accessibilityIdentifier("ebook-bookmark-card-" + bookmark.id.uuidString)
                            Button { removed(bookmark.id) } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                                .buttonStyle(.plain).accessibilityLabel(text("Delete bookmark")).accessibilityIdentifier("ebook-bookmark-delete-" + bookmark.id.uuidString)
                        }.background(HarborTheme.surface, in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.2)))
                    }
                }.padding(20)
            }.background(HarborTheme.background).navigationTitle(text("Bookmarks")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(text("Close panel")) { dismiss() }.accessibilityIdentifier("ebook-bookmarks-close") } }
        }
    }
    @ViewBuilder private func badges(_ bookmark: EBookBookmark, index: Int?) -> some View {
        let chapter = index.map { publication.chapters[$0] }
        let volume = chapter.flatMap { chapter in volumes.first { $0.chapters.contains { $0["id"].string == chapter.id } } }
        badge(bookmark.volumeLabel ?? volume?.label ?? text("Chapters"))
        badge(bookmark.chapterLabel ?? chapter?.number.map { DesktopInterfaceText.value("Chapter {chapter}", variables: ["chapter": $0]) } ?? bookmark.chapterTitle ?? chapter?.title ?? text("Chapter"))
        badge(DesktopInterfaceText.value("Line {line}", variables: ["line": String((bookmark.line ?? bookmark.block) + 1)]), accent: true)
    }
    private func badge(_ title: String, accent: Bool = false) -> some View {
        Text(title).font(.caption2.weight(.semibold)).foregroundStyle(accent ? HarborTheme.accent : .primary)
            .padding(.horizontal, 9).padding(.vertical, 6).background(accent ? HarborTheme.accent.opacity(0.15) : .secondary.opacity(0.1), in: .capsule)
    }
}
