import SwiftUI
import CoreText

enum HarborSection: String, CaseIterable, Identifiable {
    case home, discover, catalogs, movies, shows, anime, live, library, search, addons, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .discover: "Discover"
        case .catalogs: "Catálogos"
        case .movies: "Películas"
        case .shows: "Series"
        case .anime: "Anime"
        case .live: "Live TV"
        case .library: "Mi biblioteca"
        case .search: "Buscar"
        case .addons: "Addons"
        case .settings: "Ajustes"
        }
    }
    var icon: String {
        switch self {
        case .home: "home"
        case .discover: "explore"
        case .catalogs: "catalogs"
        case .movies: "movies"
        case .shows: "tv"
        case .anime: "anime"
        case .live: "livetv"
        case .library: "library"
        case .search: "search"
        case .addons: "addons"
        case .settings: "settings"
        }
    }
}

struct HarborBrand: View {
    var size: CGFloat = 30
    var body: some View {
        HStack(spacing: 1) {
            Image("harbor-mark").resizable().scaledToFit().frame(width: size * 0.9, height: size)
            Text("Harbor").font(wordmarkFont).tracking(-1)
        }.foregroundStyle(.white).accessibilityElement(children: .ignore).accessibilityLabel("Harbor")
    }
    private var wordmarkFont: Font {
        let variation = [NSNumber(value: 0x77676874): NSNumber(value: 500), NSNumber(value: 0x6f70737a): NSNumber(value: Double(size))]
        let attributes: [CFString: Any] = [kCTFontNameAttribute: "Fraunces-9ptBlack", kCTFontVariationAttribute: variation]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}

struct HarborShell: View {
    let app: AppModel
    @State private var section = HarborSection.home
    @State private var path = NavigationPath()
    @State private var menu = false
    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack(path: $path) {
                destination
                    .navigationDestination(for: Media.self) { DetailView(media: $0, app: app) }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { withAnimation(.easeOut(duration: 0.18)) { menu = true } } label: { Image(systemName: "line.3.horizontal").frame(width: 36, height: 36) }.accessibilityLabel("Abrir navegación").accessibilityIdentifier("main-menu")
                        }
                        ToolbarItem(placement: .principal) { if section == .home { HarborBrand(size: 28) } }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { app.showAccount = true } label: { Image(systemName: "person.crop.circle").frame(width: 36, height: 36) }.accessibilityLabel("Cuenta")
                        }
                    }
            }
            if menu {
                Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { closeMenu() }
                VStack(alignment: .leading, spacing: 18) {
                    HStack { HarborBrand(size: 36); Spacer(); Button { closeMenu() } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }.accessibilityLabel("Cerrar navegación") }.padding(.horizontal, 18)
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(HarborSection.allCases) { item in
                                Button {
                                    path = NavigationPath(); section = item; closeMenu()
                                } label: {
                                    HStack(spacing: 16) {
                                        Image("nav-\(item.icon)").resizable().scaledToFit().frame(width: 23, height: 23)
                                        Text(item.title).font(.system(size: 15, weight: item == section ? .semibold : .regular))
                                        Spacer()
                                    }.foregroundStyle(item == section ? .white : .white.opacity(0.65)).padding(.horizontal, 18).frame(minHeight: 52)
                                        .background(item == section ? Color.white.opacity(0.09) : .clear, in: .rect(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityIdentifier("nav-\(item.rawValue)")
                            }
                        }.padding(.horizontal, 12)
                    }.accessibilityIdentifier("navigation-scroll")
                    if let user = app.user { Text(user.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 20) }
                }.padding(.top, 12).padding(.bottom, 16).frame(width: 282).frame(maxHeight: .infinity).background(HarborTheme.background)
                    .transition(.move(edge: .leading)).accessibilityIdentifier("navigation-drawer")
            }
        }
    }
    @ViewBuilder private var destination: some View {
        switch section {
        case .home: HomeView(model: app)
        case .catalogs: CatalogsView(app: app)
        case .movies: ContentPageView(app: app, kind: "movie", title: section.title)
        case .shows: ContentPageView(app: app, kind: "series", title: section.title)
        case .anime: ContentPageView(app: app, kind: "anime", title: section.title)
        case .live: ContentPageView(app: app, kind: "tv", title: section.title)
        case .library: LibraryView(app: app)
        case .discover: DiscoverView(app: app)
        case .search: SearchView(app: app)
        case .addons: AddonsView(app: app)
        case .settings: SettingsView(app: app)
        }
    }
    private func closeMenu() { withAnimation(.easeOut(duration: 0.18)) { menu = false } }
}

struct DiscoverView: View {
    let app: AppModel
    @State private var selected = ""
    private var catalogs: [CatalogRow] { app.rows.filter { !$0.metas.isEmpty } }
    var body: some View {
        VStack(spacing: 12) {
            Picker("Catálogo", selection: $selected) {
                ForEach(catalogs) { Text("\($0.plan.addon.name) · \($0.plan.title)").tag($0.id) }
            }.padding(.horizontal)
            if let row = catalogs.first(where: { $0.id == selected }) ?? catalogs.first {
                CatalogBrowserView(app: app, initial: row).id(row.id)
            } else if app.loading { ProgressView() }
            else { ContentUnavailableView("Sin catálogos", image: "nav-catalogs", description: Text("Instala un addon o recupera los de tu cuenta.")) }
        }.background(HarborTheme.background).navigationTitle("Discover").navigationBarTitleDisplayMode(.inline)
    }
}
