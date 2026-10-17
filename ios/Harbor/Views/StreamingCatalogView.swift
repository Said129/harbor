import SwiftUI

struct StreamingServicesView: View {
    let app: AppModel
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                ForEach(StreamingServiceDefinition.all) { service in
                    NavigationLink { StreamingCatalogView(service: service, app: app) } label: {
                        StreamingServiceLogo(service: service, height: 28).frame(maxWidth: .infinity).frame(height: 96)
                            .background(ProfilePreferences.color(String(service.tint.dropFirst())).opacity(0.2), in: .rect(cornerRadius: 18))
                            .overlay { RoundedRectangle(cornerRadius: 18).stroke(HarborTheme.ink.opacity(0.08), lineWidth: 1) }
                    }.buttonStyle(ServicePressStyle()).accessibilityLabel(service.name).accessibilityIdentifier("browse-service-" + service.key)
                }
            }.padding(20)
        }.accessibilityIdentifier("services-index").modifier(ServiceEntrance(distance: 16)).background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(DesktopInterfaceText.value("Services")).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}

struct StreamingCatalogView: View {
    let service: StreamingServiceDefinition
    let app: AppModel
    @State private var model = ServiceCatalogModel()
    @State private var category = ServiceCatalogCategory.all[0]
    @State private var nearEnd = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var signature: String {
        let configuration = MetadataPreferences.shared.configuration()
        return ServiceCatalogModel.scopeKey(service: service, category: category, configuration: configuration, owner: app.user?.id ?? "guest")
    }
    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    header.id("service-top")
                    categories
                    if MetadataPreferences.shared.tmdbKey.isEmpty {
                        ContentUnavailableView {
                            Label(DesktopInterfaceText.value("Connect TMDB"), image: "metadata-tmdb")
                        } description: {
                            Text(DesktopInterfaceText.value("Add your TMDB key in Settings to load these catalogs."))
                        } actions: {
                            NavigationLink(DesktopInterfaceText.value("Metadata providers")) { MetadataSettingsView() }
                                .buttonStyle(HarborAccountButtonStyle()).accessibilityIdentifier("service-configure-metadata")
                        }.padding(.vertical, 28).accessibilityIdentifier("service-missing-key")
                    } else {
                        titles
                        if model.loading {
                            if model.allTitles.isEmpty { ServiceCatalogSkeleton() }
                            else { HarborLoader().frame(maxWidth: .infinity).padding(24) }
                        }
                        if let error = model.error {
                            VStack(spacing: 12) {
                                Text(DesktopInterfaceText.value(error)).font(.caption).foregroundStyle(.secondary)
                                Button(DesktopInterfaceText.value("Retry")) { Task { await load(more: true) } }.buttonStyle(HarborAccountButtonStyle())
                            }.frame(maxWidth: .infinity)
                        } else if model.allTitles.isEmpty && !model.loading {
                            ContentUnavailableView {
                                Label(DesktopInterfaceText.value("No results"), systemImage: "film")
                            } description: {
                                Text(DesktopInterfaceText.value("Nothing matched this filter. Try another category or change your region in Settings."))
                            } actions: {
                                NavigationLink(DesktopInterfaceText.value("Region & language")) { MetadataSettingsView() }
                                    .buttonStyle(HarborAccountButtonStyle())
                            }
                        }
                        if model.hasMore && !model.loading && model.error == nil && !model.allTitles.isEmpty {
                            Button(DesktopInterfaceText.value("Load more")) { Task { await load(more: true) } }
                                .buttonStyle(HarborAccountButtonStyle()).frame(maxWidth: .infinity).accessibilityIdentifier("service-load-more")
                        }
                        Color.clear.frame(height: 1).onAppear { nearEnd = true }.onDisappear { nearEnd = false }
                    }
                }.padding(.bottom, 90)
            }.accessibilityIdentifier("service-catalog-scroll")
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(ServiceCatalogCategory.all) { option in
                                Button { select(option) } label: {
                                    if category.id == option.id { Label(DesktopInterfaceText.value(option.label), systemImage: "checkmark") }
                                    else { Text(DesktopInterfaceText.value(option.label)) }
                                }
                            }
                        } label: { Image(systemName: "slider.horizontal.3").frame(width: 48, height: 48) }
                            .background(HarborTheme.surface, in: .circle).accessibilityLabel(DesktopInterfaceText.value("Categories"))
                            .accessibilityIdentifier("service-category-menu")
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { scroll.scrollTo("service-top", anchor: .top) }
                        } label: { Image(systemName: "arrow.up").frame(width: 48, height: 48) }
                            .background(HarborTheme.surface, in: .circle).accessibilityLabel(DesktopInterfaceText.value("Back to top"))
                            .accessibilityIdentifier("service-back-to-top")
                    }.padding(18)
                }
        }.modifier(ServiceEntrance(distance: 14)).background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(service.name).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .task(id: signature + "|" + String(describing: scenePhase)) {
                guard scenePhase == .active else { return }
                await load(more: false)
            }
            .task(id: signature + "|\(model.revision)|\(nearEnd)|" + String(describing: scenePhase)) {
                guard scenePhase == .active, nearEnd, model.hasMore, !model.loading, model.error == nil,
                      !model.allTitles.isEmpty else { return }
                await load(more: true)
            }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(DesktopInterfaceText.value("Popular on").uppercased()).font(HarborTheme.font(12.5, weight: .medium)).tracking(2).foregroundStyle(.secondary)
            StreamingServiceLogo(service: service, height: 56, horizontalPadding: 0).frame(height: 90, alignment: .leading)
            Text(DesktopInterfaceText.value("The most-watched movies and series on {name} right now in {region}.", variables: ["name": service.name, "region": MetadataPreferences.shared.region]))
                .font(HarborTheme.font(14.5)).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RadialGradient(colors: [ProfilePreferences.color(String(service.tint.dropFirst())).opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 460)
            }
    }
    private var categories: some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ServiceCatalogCategory.all) { option in
                        HarborPill(title: DesktopInterfaceText.value(option.label), selected: category.id == option.id) { select(option) }
                            .id(option.id).accessibilityIdentifier("service-category-" + option.id)
                    }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden).accessibilityIdentifier("service-categories")
                .onChange(of: category.id) { _, id in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { scroll.scrollTo(id, anchor: .center) }
                }
        }
    }
    @ViewBuilder private var titles: some View {
        if category.id == "all" {
            section(model.movies, kind: "movie")
            section(model.series, kind: "series")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 12, alignment: .top)], spacing: 22) {
                ForEach(model.allTitles, id: \.identity) { media in NavigationLink(value: media) { Poster(media: media, width: nil) }.buttonStyle(.plain) }
            }.padding(.horizontal, 20)
        }
    }
    @ViewBuilder private func section(_ values: [Media], kind: String) -> some View {
        if !values.isEmpty {
            let ranked = values.count >= 10
            VStack(alignment: .leading, spacing: 18) {
                Text(DesktopInterfaceText.value(kind == "movie" ? (ranked ? "Top 10 Movies on {name}" : "Movies on {name}") : (ranked ? "Top 10 Series on {name}" : "Series on {name}"), variables: ["name": service.name]))
                    .font(HarborTheme.font(20, weight: .semibold)).padding(.horizontal, 20)
                if ranked { TopTenRail(metas: Array(values.prefix(10))) }
                else { posters(values) }
                if values.count > 10 {
                    Text(DesktopInterfaceText.value(kind == "movie" ? "More Movies" : "More Series")).font(HarborTheme.font(20, weight: .semibold)).padding(.horizontal, 20)
                    posters(Array(values.dropFirst(10)))
                }
            }
        }
    }
    private func posters(_ values: [Media]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(values, id: \.identity) { media in NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain) }
            }.padding(.horizontal, 20)
        }.scrollIndicators(.hidden)
    }
    private func select(_ next: ServiceCatalogCategory) {
        guard category.id != next.id else { return }
        model.reset()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { category = next }
    }
    private func load(more: Bool) async {
        await model.load(service: service, category: category, configuration: MetadataPreferences.shared.configuration(), owner: app.user?.id ?? "guest", more: more)
    }
}

private struct ServiceEntrance: ViewModifier {
    let distance: CGFloat
    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(entered || reduceMotion ? 1 : 0).offset(y: entered || reduceMotion ? 0 : distance)
            .onAppear { withAnimation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.32)) { entered = true } }
    }
}

private struct ServicePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct ServiceCatalogSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 12)], spacing: 22) {
            ForEach(0..<18) { _ in
                RoundedRectangle(cornerRadius: 12).fill(HarborTheme.ink.opacity(0.08)).aspectRatio(2.0 / 3, contentMode: .fit)
                    .phaseAnimator(reduceMotion || scenePhase != .active ? [false] : [false, true]) { content, highlighted in
                        content.opacity(highlighted ? 1 : 0.45)
                    } animation: { _ in .easeInOut(duration: 0.8) }
            }
        }.padding(.horizontal, 20).accessibilityHidden(true)
    }
}
