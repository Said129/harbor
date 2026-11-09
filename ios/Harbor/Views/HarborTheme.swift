import SwiftUI

@MainActor enum HarborTheme {
    /// With a custom background image, screens go transparent so ThemeBackdrop (drawn at the app root) shows through.
    static var background: Color { ThemePreferences.shared.hasBackgroundImage ? Color.clear : ThemePreferences.shared.color("canvas") }
    static var accent: Color { ThemePreferences.shared.color("accent") }
    static var surface: Color { ThemePreferences.shared.color("surface") }
    static var ink: Color { ThemePreferences.shared.color("ink") }
    static func displayFont(_ size: CGFloat) -> Font { .custom("Fraunces-9ptBlack", size: size).weight(.medium) }
    static func font(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        switch ThemePreferences.shared.font {
        case "inter": .custom("Inter-Regular", size: size).weight(weight)
        case "system": .system(size: size, weight: weight)
        default: .custom("SwitzerVariable-Regular", size: size).weight(weight)
        }
    }
}

struct Poster: View {
    let media: Media
    var width: CGFloat? = 116
    var artworkFallbacks: [String] = []
    var honorsRowStyle = true
    var showsTopTenRibbon = true
    var onExpansionWidthChange: ((CGFloat?) -> Void)? = nil
    var body: some View {
        ProfilePoster(media: media, width: width, artworkFallbacks: artworkFallbacks, honorsRowStyle: honorsRowStyle,
                      showsTopTenRibbon: showsTopTenRibbon, onExpansionWidthChange: onExpansionWidthChange)
    }
}

struct CatalogRails: View {
    let rows: [CatalogRow]
    var app: AppModel? = nil
    var titleOverrides: [String: String] = [:]
    var browseCatalogs = true
    var onSelect: (() -> Void)? = nil
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title(row)).font(HarborTheme.font(17, weight: .medium)).accessibilityIdentifier("catalog-title")
                            Text(["movie": "Películas", "series": "Series", "anime": "Anime", "tv": "TV", "channel": "TV"][row.plan.kind] ?? row.plan.kind).font(HarborTheme.font(12)).foregroundStyle(HarborTheme.ink.opacity(0.45))
                        }
                        Spacer()
                        if browseCatalogs, let app { NavigationLink { CatalogBrowserView(app: app, initial: row) } label: { HStack(spacing: 4) { Text("Ver todo"); Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 14, height: 14) }.font(.caption).foregroundStyle(.secondary).frame(minHeight: 44) }.accessibilityIdentifier("catalog-browser-link") }
                    }.padding(.horizontal)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(row.metas, id: \.identity) { media in
                                Group {
                                    if let app {
                                        NavigationLink { DetailView(media: media, app: app) } label: { Poster(media: media) }
                                            .buttonStyle(.plain).accessibilityLabel(media.name)
                                            .accessibilityIdentifier(media.type == "movie" ? "catalog-movie" : "catalog-media")
                                            .simultaneousGesture(TapGesture().onEnded { onSelect?() })
                                    } else {
                                        NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain).accessibilityLabel(media.name)
                                    }
                                }
                                .onAppear {
                                    // Desktop's row `onEndReached`: reaching the last title asks the page model for the next catalog page.
                                    guard browseCatalogs, let app, media.identity == row.metas.last?.identity else { return }
                                    Task { await app.pageModel(row.plan.kind).loadMoreRow(id: row.id, app: app) }
                                }
                            }
                        }.padding(.horizontal)
                    }.scrollIndicators(.hidden).posterRowBehavior()
                }
            }
        }
    }
    private func title(_ row: CatalogRow) -> String {
        titleOverrides[row.id] ?? row.plan.title
    }
}
