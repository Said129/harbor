import SwiftUI

struct CustomListDetailContent: View {
    let app: AppModel
    let list: CustomList
    let onBack: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var dropTarget: String?
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var store: CustomListStore { app.customLists }
    private var dragPrefix: String { "harbor-list-item:" + EBookShelf.hash(app.accountOperationScope) + ":" + list.id + ":" }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key, language: locale.identifier) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Button(action: onBack) { Label(text("Back to lists"), systemImage: "arrow.left").font(HarborTheme.font(13, weight: .semibold)).frame(minHeight: 44) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityIdentifier("custom-list-back")
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(list.name).font(HarborTheme.displayFont(34)).accessibilityAddTraits(.isHeader).accessibilityIdentifier("custom-list-title")
                    if !list.description.isEmpty { Text(list.description).font(HarborTheme.font(14)).foregroundStyle(.secondary) }
                    Text(CustomListPresentation.count(list, locale: locale, limit: true)).font(HarborTheme.font(12.5)).foregroundStyle(.secondary).accessibilityIdentifier("custom-list-item-count")
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button(text("Rename list"), action: onEdit)
                    Button(text("Delete list"), role: .destructive, action: onDelete)
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel(text("List settings")).accessibilityIdentifier("custom-list-settings").disabled(store.busy)
            }
            CustomListAddTitleSearch(app: app, list: list)
            if list.items.isEmpty {
                VStack(spacing: 12) {
                    Image("desktop-layers").resizable().scaledToFit().frame(width: 26, height: 26).accessibilityHidden(true)
                    Text(text("Nothing here yet")).font(HarborTheme.font(15, weight: .semibold))
                    Text(text("Add titles with the search above, or hit \"Add to list\" on any movie or show's page.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 32).padding(.vertical, 64)
                    .background(HarborTheme.background.opacity(0.3), in: .rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                    .accessibilityIdentifier("custom-list-empty")
            } else {
                PosterGrid {
                    ForEach(list.items) { item in itemCard(item) }
                }.animation(reduceMotion ? nil : .easeInOut(duration: 0.19), value: list.items.map(\.id))
            }
        }
    }
    private func itemCard(_ item: CustomListItem) -> some View {
        NavigationLink {
            if item.type == "manga" { CustomListMangaDestination(app: app, item: item, listID: list.id) }
            else { DetailView(media: item.media, app: app) }
        } label: { Poster(media: item.media, width: nil) }
            .buttonStyle(.plain).accessibilityLabel(item.name).accessibilityIdentifier("custom-list-item")
            .overlay(alignment: .topTrailing) {
                Button { let target = store; Task { await target.apply(.remove(list.id, item.id)) } } label: {
                    Image("desktop-x").resizable().scaledToFit().frame(width: 14, height: 14)
                        .padding(8).background(HarborTheme.background.opacity(0.9), in: .circle).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(text("Remove from list") + ": " + item.name)
                    .accessibilityIdentifier("custom-list-item-remove").disabled(store.busy)
            }
            .contextMenu {
                Button(text("Move up")) { move(item.id, by: -1) }.disabled(list.items.first?.id == item.id || store.busy)
                Button(text("Move down")) { move(item.id, by: 1) }.disabled(list.items.last?.id == item.id || store.busy)
                Button(text("Remove from list"), role: .destructive) { let target = store; Task { await target.apply(.remove(list.id, item.id)) } }
            }
            .draggable(dragPrefix + item.id)
            .dropDestination(for: String.self) { values, _ in
                let prefix = dragPrefix
                guard !store.busy, let value = values.first, value.hasPrefix(prefix) else { return false }
                let id = String(value.dropFirst(prefix.count))
                guard id != item.id, list.items.contains(where: { $0.id == id }) else { return false }
                var ids = list.items.map(\.id).filter { $0 != id }; guard let index = ids.firstIndex(of: item.id) else { return false }
                ids.insert(id, at: index); let target = store; Task { await target.apply(.reorderItems(list.id, ids)) }; return true
            } isTargeted: { active in dropTarget = active ? item.id : nil }
            .overlay { if dropTarget == item.id { RoundedRectangle(cornerRadius: 12).stroke(HarborTheme.accent, lineWidth: 2).allowsHitTesting(false) } }
    }
    private func move(_ id: String, by offset: Int) {
        var ids = list.items.map(\.id); guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset); let target = store; Task { await target.apply(.reorderItems(list.id, ids)) }
    }
}

struct CustomListAddTitleSearch: View {
    let app: AppModel
    let list: CustomList
    @State private var query = ""
    @State private var hits: [Media] = []
    @State private var loading = false
    @State private var failure: String?
    @State private var notice: String?
    @State private var retry = 0
    @Environment(\.locale) private var locale
    private var store: CustomListStore { app.customLists }
    private var preferences: MetadataPreferences { .shared }
    private struct Request: Equatable {
        let query: String, scope: String, key: String, language: String
        let translate: Bool, retry: Int
    }
    private var request: Request { .init(query: query.trimmingCharacters(in: .whitespacesAndNewlines), scope: app.accountOperationScope,
        key: preferences.tmdbKey, language: preferences.language, translate: preferences.translateTitles, retry: retry) }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key, language: locale.identifier) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HarborSearchField(prompt: text("Add a movie or show to this list..."), text: $query, dismissOnSubmit: true)
            if let notice { Text(notice).font(.caption).foregroundStyle(HarborTheme.accent).accessibilityIdentifier("custom-list-search-notice") }
            if !request.query.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    if loading && hits.isEmpty { ProgressView(text("Searching...")) }
                    else if request.key.isEmpty { Text(text("Add a TMDB API key in Metadata settings to search for titles.")) }
                    else if let failure {
                        Text(failure)
                        Button(text("Retry")) { retry += 1 }.frame(minHeight: 44)
                    } else if hits.isEmpty { Text(text("No matches. Try another title.")) }
                    else {
                        ScrollView {
                            LazyVStack(spacing: 0) { ForEach(hits) { media in result(media) } }
                        }.frame(maxHeight: 360)
                    }
                }.font(HarborTheme.font(13)).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(HarborTheme.surface, in: .rect(cornerRadius: 16))
            }
        }.task(id: request) { await search(request) }
            .onChange(of: app.accountOperationScope) { _, _ in query = ""; hits = []; notice = nil; failure = nil }
    }
    private func result(_ media: Media) -> some View {
        let member = store.contains(media.id, list: list.id)
        return Button {
            guard !member else { return }
            if list.items.count >= CustomListsDocument.maximumItems {
                notice = DesktopInterfaceText.value("This list is full ({max} items)", variables: ["max": String(CustomListsDocument.maximumItems)], language: locale.identifier); return
            }
            let target = store, scope = app.accountOperationScope
            Task {
                let result = await target.apply(.add(list.id, CustomListItem.input(media)))
                guard scope == app.accountOperationScope, result?.changed == true else { return }
                notice = DesktopInterfaceText.value("Added to \"{name}\"", variables: ["name": list.name], language: locale.identifier)
            }
        } label: {
            HStack(spacing: 12) {
                Artwork(url: media.poster, maxPixels: 120).frame(width: 36, height: 54).clipped().clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(media.name).font(HarborTheme.font(13.5, weight: .medium)).foregroundStyle(HarborTheme.ink).lineLimit(1)
                    Text([text(media.type == "movie" ? "Movie" : "Series"), media.releaseInfo].compactMap { $0 }.joined(separator: " · ")).font(HarborTheme.font(11.5))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: member ? "checkmark" : "plus").frame(width: 32, height: 32).foregroundStyle(member ? HarborTheme.accent : HarborTheme.ink)
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(member || store.busy || !store.ready).accessibilityIdentifier("custom-list-search-result")
            .accessibilityLabel(media.name).accessibilityValue(member ? text("Added") : text("Add to list"))
    }
    private func search(_ request: Request) async {
        hits = []; failure = nil; notice = nil; loading = !request.query.isEmpty && !request.key.isEmpty
        guard loading else { return }
        do {
            try await Task.sleep(for: .milliseconds(260))
            let configuration = MetadataConfiguration(tmdbKey: request.key, region: preferences.region, language: request.language, translateTitles: request.translate)
            let results = try await TMDBService().searchWatchables(request.query, configuration: configuration)
            try Task.checkCancellation(); guard request == self.request else { return }; hits = results; loading = false
        } catch is CancellationError {}
        catch { guard !Task.isCancelled, request == self.request else { return }; failure = safeMessage(error); loading = false }
    }
}
