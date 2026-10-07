import SwiftUI

@MainActor
struct CommunityAddonBrowseView: View {
    let app: AppModel
    let query: String
    let category: AddonCategory
    let allowAdult: Bool
    let refreshRevision: Int
    let fallback: [Addon]
    let open: (Addon) -> Void
    @State private var sort = CommunityAddons.Sort.stars
    @State private var entries: [CommunityAddon] = []
    @State private var nextPage: Int? = 1
    @State private var loading = true
    @State private var error: String?
    @State private var retryRevision = 0
    @State private var activeRequest: UUID?

    private var request: String { "\(sort.rawValue)-\(category.rawValue)-\(allowAdult)-\(query)-\(refreshRevision)-\(retryRevision)" }
    private var safeEntries: [CommunityAddon] { entries.filter { allowAdult || !$0.adult } }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach([CommunityAddons.Sort.stars, .trending, .createdAt]) { value in
                        HarborPill(title: value == .trending ? DesktopInterfaceText.value("Top rising") : value.title, selected: sort == value) { sort = value }
                            .accessibilityIdentifier("addon-browse-sort-\(value.rawValue)")
                    }
                }
            }.scrollIndicators(.hidden)
            ForEach(safeEntries) { item in
                CommunityAddonBrowseRow(app: app, item: item, open: open)
            }
            if loading { ProgressView().frame(maxWidth: .infinity).frame(minHeight: 60).accessibilityIdentifier("addon-browse-loading") }
            if let error {
                Text(error).font(HarborTheme.font(12)).foregroundStyle(.secondary)
                Button("Reintentar") {
                    if entries.isEmpty { retryRevision += 1 }
                    else if let token = activeRequest { Task { await loadNext(for: token) } }
                }.buttonStyle(HarborAccountButtonStyle()).disabled(loading)
                // Original Stremio directories remain usable during an index
                // outage; they carry no invented community ratings.
                if entries.isEmpty {
                    ForEach(fallback) { addon in
                        AddonStoreCard(app: app, addon: addon, installed: app.addons.contains { $0.manifest["id"].string == addon.manifest["id"].string }) { open(addon) }
                    }
                }
            } else if !loading {
                if entries.isEmpty { Text(endText).font(HarborTheme.font(13)).foregroundStyle(.secondary) }
                else if nextPage != nil {
                    Button(DesktopInterfaceText.value("View more")) {
                        if let token = activeRequest { Task { await loadNext(for: token) } }
                    }.buttonStyle(HarborAccountButtonStyle()).frame(maxWidth: .infinity).accessibilityIdentifier("addon-browse-more")
                } else {
                    Text(endText)
                        .font(HarborTheme.font(11)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
            }
        }.accessibilityIdentifier("addon-community-browse")
            .task(id: request) {
                let token = UUID()
                activeRequest = token; entries = []; nextPage = 1; error = nil; loading = true
                do {
                    if !query.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                    try Task.checkCancellation()
                    await loadNext(for: token, initial: true)
                } catch is CancellationError { return }
                catch { if activeRequest == token { self.error = safeMessage(error); loading = false } }
            }
            .onDisappear { activeRequest = nil }
    }

    private var endText: String { DesktopInterfaceText.value("You've reached the end · {n} addons").replacingOccurrences(of: "{n}", with: String(entries.count)) }

    private func loadNext(for token: UUID, initial: Bool = false) async {
        guard activeRequest == token, let page = nextPage, initial || !loading else { return }
        loading = true; error = nil
        let selectedSort = sort, selectedCategory = category, search = query, includeAdult = allowAdult
        do {
            let result = try await CommunityAddons.shared.browse(page: page, sort: selectedSort, category: selectedCategory, query: search, allowAdult: includeAdult, refresh: page == 1 && (refreshRevision > 0 || retryRevision > 0))
            try Task.checkCancellation()
            guard activeRequest == token else { return }
            var seen = Set(entries.map(\.id))
            entries.append(contentsOf: result.entries.filter { seen.insert($0.id).inserted })
            nextPage = result.nextPage; loading = false
        } catch is CancellationError { if activeRequest == token { loading = false } }
        catch { if activeRequest == token { self.error = safeMessage(error); loading = false } }
    }
}

@MainActor
private struct CommunityAddonBrowseRow: View {
    let app: AppModel
    let item: CommunityAddon
    let open: (Addon) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { open(item.addon) } label: {
                HStack(alignment: .top, spacing: 14) {
                    AddonLogo(addon: item.addon, size: 46)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.addon.name).font(HarborTheme.font(15, weight: .semibold))
                        if let description = item.addon.manifest["description"].string {
                            Text(String(description.prefix(1_000))).font(HarborTheme.font(12)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(.secondary).accessibilityHidden(true)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(item.addon.name).accessibilityIdentifier("addon-browse-details")
            HStack(spacing: 10) {
                CommunityStars(count: item.stars)
                Text(item.addon.types.prefix(3).joined(separator: " · ").uppercased()).font(HarborTheme.font(9, weight: .semibold)).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                CommunityInstallButton(app: app, item: item, open: open)
            }
        }.padding(16).background(HarborTheme.surface, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(HarborTheme.ink.opacity(0.06), lineWidth: 1) }
    }
}
