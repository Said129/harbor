import SwiftUI

struct EBookBrowseControls: View {
    @Binding var filters: EBookBrowseFilters
    @Binding var titleLanguage: String
    let definitions: EBookCatalogDefinitions?
    let apply: () -> Void
    let reset: () -> Void
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    private var genres: [String] {
        let names = filters.group == "All" ? (definitions?.categories.values.flatMap { $0 } ?? []) : (definitions?.categories[filters.group] ?? [])
        return Array(Set(names + (definitions?.genres ?? []))).sorted()
    }
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                menu("Type", id: "type", selection: $filters.group, choices: ["All", "Fiction", "Non-fiction"])
                Menu {
                    Picker(text("Genre"), selection: $filters.genre) {
                        Text(text("All genres")).tag("")
                        ForEach(genres, id: \.self) { Text(text($0)).tag($0) }
                    }
                } label: { chip("Genre", value: filters.genre.isEmpty ? "All genres" : filters.genre) }.accessibilityIdentifier("ebook-filter-genre")
                menu("Status", id: "status", selection: $filters.status, choices: ["any", "ongoing", "completed", "hiatus"])
                menu("Language", id: "language", selection: $filters.language, choices: ["any", "chinese", "korean", "japanese"])
                menu("Sort by", id: "sort", selection: $filters.sort, choices: ["name", "popular", "chapters", "rating", "trending"])
                menu("Titles", id: "titles", selection: $titleLanguage, choices: ["auto", "en", "ar", "original"])
            }.padding(.horizontal)
        }.scrollIndicators(.hidden)
        HStack {
            Button(text("Apply"), action: apply).buttonStyle(.borderedProminent).tint(HarborTheme.accent).accessibilityIdentifier("ebook-filter-apply")
            Button(text("Reset"), action: reset).buttonStyle(.bordered).accessibilityIdentifier("ebook-filter-reset")
            Spacer()
        }.padding(.horizontal)
            .onChange(of: filters.group) { _, _ in filters.genre = "" }
    }
    private func label(_ value: String) -> String {
        switch value {
        case "any": return "Any"
        case "en": return "English"
        case "ar": return "Arabic"
        default: return value.prefix(1).uppercased() + value.dropFirst()
        }
    }
    private func menu(_ name: String, id: String, selection: Binding<String>, choices: [String]) -> some View {
        Menu {
            Picker(text(name), selection: selection) { ForEach(choices, id: \.self) { Text(text(label($0))).tag($0) } }
        } label: { chip(name, value: label(selection.wrappedValue)) }.accessibilityIdentifier("ebook-filter-" + id)
    }
    private func chip(_ name: String, value: String) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text(name)).font(.caption2).foregroundStyle(.secondary)
                Text(text(value)).font(.subheadline.weight(.medium)).lineLimit(1)
            }
            Image(systemName: "chevron.down").font(.caption2)
        }.padding(.horizontal, 12).frame(minHeight: 48).background(HarborTheme.surface, in: .rect(cornerRadius: 14))
    }
}
