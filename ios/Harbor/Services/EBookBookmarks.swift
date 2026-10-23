import Foundation

/// Desktop stores the newest passage first and identifies chapters by source ID.
enum EBookBookmarks {
    static func chapter(_ bookmark: EBookBookmark, in publication: EBookPublication) -> Int? {
        if let id = bookmark.chapterID { return publication.chapters.firstIndex { $0.id == id } }
        return publication.chapters.indices.contains(bookmark.chapter) ? bookmark.chapter : nil
    }

    static func upgrading(_ items: [EBookBookmark], in publication: EBookPublication, volumes: [EBookVolume]) -> [EBookBookmark] {
        // Earlier iOS builds appended positional bookmarks, oldest first.
        let ordered = items.allSatisfy { $0.chapterID == nil && $0.createdAt == nil } ? Array(items.reversed()) : items
        return ordered.map { item in
            guard item.chapterID == nil, let index = chapter(item, in: publication) else { return item }
            var upgraded = item
            let saved = publication.chapters[index]
            upgraded.chapterID = saved.id; upgraded.chapterTitle = saved.title
            upgraded.chapterLabel = label(saved)
            upgraded.volumeLabel = volumes.first { $0.chapters.contains { $0["id"].string == saved.id } }?.label
            return upgraded
        }
    }

    static func adding(_ bookmark: EBookBookmark, to items: [EBookBookmark], in publication: EBookPublication) -> [EBookBookmark] {
        let selected = chapter(bookmark, in: publication)
        return Array(([bookmark] + items.filter { saved in
            if let selected, chapter(saved, in: publication) == selected { return saved.block != bookmark.block }
            return saved.chapterID != bookmark.chapterID || saved.chapter != bookmark.chapter || saved.block != bookmark.block
        }).prefix(300))
    }

    static func make(chapter index: Int, block: Int, paragraphs: [EBookSearchParagraph], publication: EBookPublication, volumes: [EBookVolume]) -> EBookBookmark? {
        guard publication.chapters.indices.contains(index), let line = paragraphs.firstIndex(where: { $0.block == block }) else { return nil }
        let chapter = publication.chapters[index], text = paragraphs[line].text as NSString
        return EBookBookmark(id: UUID(), chapter: index, block: block,
            preview: text.substring(to: min(140, text.length)), chapterID: chapter.id,
            chapterTitle: chapter.title, chapterLabel: label(chapter),
            volumeLabel: volumes.first { $0.chapters.contains { $0["id"].string == chapter.id } }?.label,
            line: line, createdAt: Date())
    }

    private static func label(_ chapter: EBookChapter) -> String {
        chapter.number.map { DesktopInterfaceText.value("Chapter {chapter}", variables: ["chapter": $0]) } ?? chapter.title
    }
}
