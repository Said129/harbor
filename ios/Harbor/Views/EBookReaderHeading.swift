import SwiftUI
import UIKit

struct EBookReaderHeading: View {
    let book: EBook
    let owner: String
    let title: String
    let firstChapter: Bool
    let titleFont: Font
    let muted: Color
    @State private var localCover: UIImage?
    private var coverBook: EBook {
        var value = book
        if let cover = book.metadata?["internalCover"].string { value.cover = cover }
        return value
    }
    private var remoteCover: Bool { !book.id.hasPrefix("local:") && coverBook.cover != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if firstChapter, localCover != nil || remoteCover {
                Group {
                    if let localCover { Image(uiImage: localCover).resizable().scaledToFit() }
                    else { EBookCover(book: coverBook, owner: owner) }
                }.frame(maxWidth: 560).frame(maxWidth: .infinity)
                    .containerRelativeFrame(.vertical) { length, _ in length * 0.70 }
                    .shadow(color: .black.opacity(0.38), radius: 22, y: 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(DesktopInterfaceText.value("{title} internal cover", variables: ["title": book.title]))
                    .accessibilityIdentifier("ebook-reader-cover")
                    .padding(.bottom, 40)
                Divider().overlay(muted.opacity(0.35)).padding(.bottom, 40)
            }
            Text(DesktopInterfaceText.value("Harbor Reader")).font(.system(size: 12, weight: .semibold)).kerning(2.5).textCase(.uppercase)
                .foregroundStyle(muted).padding(.bottom, 8)
            Text(title).font(titleFont).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("ebook-heading-title")
            Divider().overlay(muted.opacity(0.35)).padding(.top, 28)
        }.padding(.bottom, 28)
            .task(id: owner + "|" + book.id + "|" + String(firstChapter)) {
                localCover = nil
                guard firstChapter, book.id.hasPrefix("local:") else { return }
                do {
                    let data = try await EBookService.shared.cover(book, owner: owner)
                    try Task.checkCancellation(); localCover = data.flatMap { UIImage(data: $0) }
                } catch {}
            }
    }
}
