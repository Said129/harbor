import SwiftUI
import UIKit

struct ReadingSortMenu: View {
    @Binding var selection: String
    var body: some View {
        Menu {
            Picker("Ordenar", selection: $selection) { ForEach(ReadingShelfSort.allCases) { Text($0.label).tag($0.rawValue) } }
        } label: { Label((ReadingShelfSort(rawValue: selection) ?? .title).label, systemImage: "arrow.up.arrow.down").font(.subheadline).frame(minHeight: 44) }
            .accessibilityIdentifier("reading-shelf-sort")
    }
}

struct EBookCover: View {
    let book: EBook
    let owner: String
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if let cover = book.cover, !book.id.hasPrefix("local:") { Artwork(url: cover, maxPixels: 600) }
            else {
                ZStack {
                    LinearGradient(colors: [HarborTheme.accent.opacity(0.45), HarborTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 12) { Text(book.title).font(.system(.headline, design: .serif)).lineLimit(5); Text(book.authors.joined(separator: ", ")).font(.caption).lineLimit(2) }.padding().multilineTextAlignment(.center)
                }
            }
        }.accessibilityLabel(book.title).accessibilityIdentifier("ebook-cover")
            .task(id: owner + "|" + book.id) {
                guard book.id.hasPrefix("local:") || book.cover == nil else { return }
                do { if let data = try await EBookService.shared.cover(book, owner: owner) { try Task.checkCancellation(); image = UIImage(data: data) } } catch {}
            }
    }
}
