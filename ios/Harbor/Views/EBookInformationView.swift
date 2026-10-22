import SwiftUI

struct EBookInformationView: View {
    let book: EBook
    @AppStorage("uiLanguage") private var language = "en"
    @State private var rows: [EBookInformationRow] = []
    @State private var program = EBookDetailProgram()
    private struct Request: Hashable { let book: EBook; let language: String }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(DesktopInterfaceText.value("Information")).font(.title3.weight(.semibold))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(row.value).multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.label).foregroundStyle(.secondary)
                        Text(row.value)
                    }
                }.font(.subheadline).textSelection(.enabled)
                if row.label != rows.last?.label { Divider().overlay(HarborTheme.surface) }
            }
        }.accessibilityIdentifier("ebook-information")
            .task(id: Request(book: book, language: language)) {
                let keys = ["Author", "Not available", "First aired", "Status", "Genres", "Rating", "Length", "{n} pages", "Editions", "{n} published", "Readers", "{n} ratings", "Want to read", "{n} readers", "Characters", "Setting", "Period", "Translations", "{n} languages"]
                let translations = Dictionary(uniqueKeysWithValues: keys.map { ($0, DesktopInterfaceText.value($0)) })
                do {
                    var values = try await program.information(book, translations: translations)
                    let raw = book.metadata ?? .null
                    for (key, label) in [("originalLanguage", "Original language"), ("chapters", "Chapters"), ("volumes", "Volumes"), ("archiveCopies", "Archive copies"), ("isbn", "ISBN")] {
                        let value: String?
                        switch raw[key] {
                        case .string(let text) where !text.isEmpty: value = text
                        case .integer(let number): value = String(number)
                        case .number(let number): value = number.formatted()
                        default: value = nil
                        }
                        if let value { values.append(.init(label: DesktopInterfaceText.value(label), value: value)) }
                    }
                    try Task.checkCancellation(); rows = values
                } catch {}
            }
    }
}
