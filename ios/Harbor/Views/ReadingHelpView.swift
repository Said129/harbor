import SwiftUI

struct ReadingHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    help("eBook", "Browse Gutenberg by title, author or language. Open a book to save it to your shelf. The reader offers font, spacing, background, bookmarks and read-aloud controls.")
                    help("Apple Books", "Harbor cannot list the private Apple Books library. Import an unprotected EPUB or PDF from Files or choose Harbor when opening a compatible file in another app. A store link is not a book file; protected purchases stay in Apple Books.")
                    help("Manga", "Import CBZ, ZIP or image folders from the Manga menu. For online sources, connect your Suwayomi server, install its extensions and select a source. Keep that server reachable from your iPhone or iPad.")
                    help("Your library", "Imported books and reading progress are stored separately for each Harbor account on this device. Importing the same file again keeps its saved reading position. These files are not uploaded to Stremio.")
                }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
            }.navigationTitle(DesktopInterfaceText.value("Reading help"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
                .background(HarborTheme.background)
        }.tint(HarborTheme.accent).preferredColorScheme(.dark)
    }
    private func help(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DesktopInterfaceText.value(title)).font(.headline)
            Text(DesktopInterfaceText.value(message)).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
