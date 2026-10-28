import SwiftUI

private struct CustomListMangaArtworkKey: EnvironmentKey { static let defaultValue: CustomListMangaArtworkContext? = nil }
extension EnvironmentValues {
    var customListMangaArtwork: CustomListMangaArtworkContext? {
        get { self[CustomListMangaArtworkKey.self] }
        set { self[CustomListMangaArtworkKey.self] = newValue }
    }
}

struct CustomListArtwork: View {
    let media: Media
    let url: String?
    var fallback: String? = nil
    var fallbacks: [String] = []
    var maxPixels = 500
    var onImageAvailability: ((Bool) -> Void)? = nil
    var onLoadCompletion: ((Bool) -> Void)? = nil
    @Environment(\.customListMangaArtwork) private var context
    var body: some View {
        if media.type == "manga", let context {
            CustomListMangaImage(media: media, publicURL: url, context: context, maxPixels: maxPixels,
                onImageAvailability: onImageAvailability, onLoadCompletion: onLoadCompletion).id(context.activation)
        } else {
            Artwork(url: url, fallback: fallback, fallbacks: fallbacks, maxPixels: maxPixels,
                onImageAvailability: onImageAvailability, onLoadCompletion: onLoadCompletion)
        }
    }
}

private struct CustomListMangaImage: View {
    let media: Media
    let publicURL: String?
    let context: CustomListMangaArtworkContext
    let maxPixels: Int
    let onImageAvailability: ((Bool) -> Void)?
    let onLoadCompletion: ((Bool) -> Void)?
    @State private var book: MangaBook?
    @State private var resolved = false
    var body: some View {
        GeometryReader { geometry in
            Group {
                if context.active, let book {
                    MangaImage(book: book, owner: context.owner, path: book.cover, client: context.client, maxPixels: maxPixels,
                        onImageAvailability: onImageAvailability, onLoadCompletion: onLoadCompletion)
                        .environment(\.readingPlugins, context.reading)
                } else if context.active && resolved {
                    Artwork(url: publicURL, maxPixels: maxPixels, onImageAvailability: onImageAvailability, onLoadCompletion: onLoadCompletion)
                } else { Rectangle().fill(HarborTheme.surface).overlay { ProgressView() } }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.task(id: media.identity + "|" + (media.poster ?? "")) {
            book = nil; resolved = false
            let value = await context.resolve(.init(raw: CustomListItem.input(media)))
            guard !Task.isCancelled, context.active else { return }
            book = value; resolved = true
        }
    }
}

private struct CustomListArtworkScope: ViewModifier {
    let app: AppModel
    let lists: [CustomList]
    @State private var context: CustomListMangaArtworkContext?
    @Environment(\.scenePhase) private var scenePhase
    private var signature: String {
        let items = lists.flatMap(\.items).filter { $0.type == "manga" }
        return app.accountOperationScope + "|" + EBookShelf.hash(items.map { $0.id + "|" + $0.name + "|" + ($0.poster ?? "") }.joined(separator: "\n"))
    }
    func body(content: Content) -> some View {
        content.environment(\.customListMangaArtwork, context)
            .task(id: signature + "|" + String(describing: scenePhase)) {
                context?.cancel(); context = nil
                guard scenePhase == .active else { return }
                let scope = app.accountOperationScope, owner = app.personalOwner
                let items = lists.flatMap(\.items).filter { $0.type == "manga" }
                guard !items.isEmpty else { return }
                let snapshot = await Task.detached(priority: .utility) {
                    let keychain = KeychainStore()
                    let records = (try? keychain.read("manga-shelf-" + EBookShelf.hash(owner), as: [MangaRecord].self)) ?? []
                    let server = try? keychain.read("manga-server-" + EBookShelf.hash(owner), as: MangaServer.self)
                    return (records.map(\.book), server)
                }.value
                guard !Task.isCancelled, scope == app.accountOperationScope else { return }
                let needsProviders = items.contains { item in
                    !snapshot.0.contains { $0.id == item.id && $0.server == nil && $0.pluginID == nil && CustomListMangaArtworkSelection.matches(item, $0) }
                }
                let reading: HarborReadingPluginManager?
                if needsProviders { reading = try? await app.openReadingPlugins() } else { reading = nil }
                guard !Task.isCancelled, scope == app.accountOperationScope else { return }
                context = .init(activation: scope, owner: owner, books: snapshot.0, client: snapshot.1.map { SuwayomiClient(server: $0) }, reading: reading,
                    isCurrent: { [weak app] in app?.accountOperationScope == scope })
            }.onDisappear { context?.cancel(); context = nil }
    }
}
extension View {
    func customListArtwork(app: AppModel, lists: [CustomList]) -> some View { modifier(CustomListArtworkScope(app: app, lists: lists)) }
}
