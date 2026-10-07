import SwiftUI

@MainActor
struct CommunityAddonsView: View {
    let app: AppModel
    let allowAdult: Bool
    let refreshRevision: Int
    let open: (Addon) -> Void
    @State private var sort = CommunityAddons.Sort.trending
    @State private var items: [CommunityAddon] = []
    @State private var spotlight: CommunityAddons.Spotlight?
    @State private var loading = true
    @State private var error: String?
    @State private var retryRevision = 0

    private var request: String { "\(allowAdult)-\(sort.rawValue)-\(refreshRevision)-\(retryRevision)" }
    private var uninstalled: [CommunityAddon] { items.filter { !installed($0.addon) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let spotlight, allowAdult || !spotlight.item.adult { spotlightCard(spotlight) }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Link(destination: URL(string: "https://stremio-addons.net")!) {
                        Image("community-addons-logo").resizable().scaledToFit().frame(width: 48, height: 48)
                    }.accessibilityLabel("stremio-addons.net")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Índice de la comunidad").font(HarborTheme.font(10, weight: .bold)).tracking(2).textCase(.uppercase).foregroundStyle(HarborTheme.accent)
                        Link("Desde stremio-addons.net", destination: URL(string: "https://stremio-addons.net")!)
                            .font(HarborTheme.font(21, weight: .semibold)).foregroundStyle(HarborTheme.ink)
                        Text("Clasificación de la comunidad de stremio-addons.net según su índice público.")
                            .font(HarborTheme.font(12)).foregroundStyle(.secondary)
                    }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(CommunityAddons.Sort.allCases) { value in
                            HarborPill(title: value.title, selected: sort == value) { sort = value }
                                .accessibilityIdentifier("community-sort-\(value.rawValue)")
                        }
                    }
                }.scrollIndicators(.hidden)
                if loading { ProgressView().frame(maxWidth: .infinity).frame(height: 100) }
                else if let error {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                        Button("Reintentar") { retryRevision += 1 }.buttonStyle(HarborAccountButtonStyle())
                    }
                } else if !uninstalled.isEmpty {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(uninstalled) { item in CommunityAddonCard(app: app, item: item, open: open) }
                        }.padding(.vertical, 2)
                    }.scrollIndicators(.hidden).accessibilityIdentifier("community-addon-rail")
                }
            }.accessibilityIdentifier("community-addon-section")
        }
        .task(id: request) { await load() }
    }

    private func load() async {
        loading = true; error = nil
        let refresh = refreshRevision > 0 || retryRevision > 0
        do {
            async let featured = CommunityAddons.shared.spotlight(allowAdult: allowAdult, refresh: refresh)
            async let rail = CommunityAddons.shared.list(sort, allowAdult: allowAdult, refresh: refresh)
            let (pick, entries) = try await (featured, rail)
            try Task.checkCancellation()
            spotlight = pick; items = entries; loading = false
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error); loading = false }
    }

    private func installed(_ addon: Addon) -> Bool {
        app.addons.contains { $0.manifest["id"].string == addon.manifest["id"].string }
    }

    private func spotlightCard(_ pick: CommunityAddons.Spotlight) -> some View {
        let item = pick.item
        return VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image("desktop-trending-up").resizable().scaledToFit().frame(width: 11, height: 11).foregroundStyle(HarborTheme.accent).accessibilityHidden(true)
                Text(pick.trending ? "Tendencias en stremio-addons.net" : "Mejor valorado en stremio-addons.net")
                    .font(HarborTheme.font(10, weight: .bold)).tracking(1.6).textCase(.uppercase)
            }
            Button { open(item.addon) } label: {
                HStack(spacing: 14) {
                    AddonLogo(addon: item.addon, size: 54)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.addon.name).font(HarborTheme.displayFont(28)).lineLimit(2)
                        HStack(spacing: 5) {
                            CommunityStars(count: item.stars)
                            Text("estrellas").font(HarborTheme.font(12, weight: .semibold))
                            Text(item.addon.types.prefix(4).joined(separator: " · ")).font(HarborTheme.font(12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(item.addon.name)
            if let description = item.addon.manifest["description"].string {
                Text(String(description.prefix(1_000))).font(HarborTheme.font(13)).foregroundStyle(.white.opacity(0.75)).lineLimit(3)
            }
            HStack(spacing: 10) {
                CommunityInstallButton(app: app, item: item, open: open)
                Button("Detalles") { open(item.addon) }.buttonStyle(HarborAccountButtonStyle())
                if let site = item.siteURL { Link(destination: site) { Image("desktop-arrow-up-right").resizable().scaledToFit().frame(width: 14, height: 14).frame(width: 44, height: 44) }.accessibilityLabel("stremio-addons.net") }
            }
        }.foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, minHeight: 300, alignment: .bottomLeading)
            .background {
                GeometryReader { geometry in
                    ZStack {
                        Color.black
                        if let background = item.addon.backgroundURL { Artwork(url: background, maxPixels: 1_024, failureIcon: "nav-addons").frame(width: geometry.size.width, height: geometry.size.height) }
                        LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.45), .black.opacity(0.86), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                        LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .leading, endPoint: .trailing)
                    }
                }
            }.clipShape(.rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.06), lineWidth: 1) }
            .accessibilityIdentifier("addon-community-spotlight")
    }
}

private struct CommunityStars: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            Image("community-star").resizable().scaledToFit().frame(width: 12, height: 12).accessibilityHidden(true)
            Text(count.formatted()).font(HarborTheme.font(11, weight: .bold)).monospacedDigit()
        }.foregroundStyle(HarborTheme.accent)
    }
}

@MainActor
private struct CommunityAddonCard: View {
    let app: AppModel
    let item: CommunityAddon
    let open: (Addon) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { open(item.addon) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        if let background = item.addon.backgroundURL { Artwork(url: background, maxPixels: 550, failureIcon: "nav-addons").frame(width: 256, height: 96) }
                        LinearGradient(colors: [.clear, HarborTheme.surface], startPoint: .top, endPoint: .bottom)
                        AddonLogo(addon: item.addon, size: 40).padding(10)
                    }.frame(width: 256, height: 96).overlay(alignment: .topTrailing) {
                        CommunityStars(count: item.stars).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(HarborTheme.background.opacity(0.7), in: .capsule).padding(10)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.addon.name).font(HarborTheme.font(14, weight: .semibold)).lineLimit(1)
                        if let description = item.addon.manifest["description"].string { Text(String(description.prefix(1_000))).font(HarborTheme.font(12)).foregroundStyle(.secondary).lineLimit(2) }
                    }.frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading).padding(.horizontal, 14).padding(.top, 10)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Detalles de " + item.addon.name).accessibilityIdentifier("community-addon-details")
            HStack(spacing: 6) {
                Text(item.addon.types.prefix(3).joined(separator: " · ").uppercased()).font(HarborTheme.font(9, weight: .semibold)).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                CommunityInstallButton(app: app, item: item, open: open)
            }.padding(14)
        }.frame(width: 256).background(HarborTheme.surface, in: .rect(cornerRadius: 16))
            .clipShape(.rect(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.06), lineWidth: 1) }
    }
}

@MainActor
private struct CommunityInstallButton: View {
    let app: AppModel
    let item: CommunityAddon
    let open: (Addon) -> Void
    @State private var busy = false
    @State private var error: String?
    private var installed: Bool { app.addons.contains { $0.manifest["id"].string == item.addon.manifest["id"].string } }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard !installed, !busy else { return }
                if item.addon.configurable { open(item.addon); return }
                let owner = app.user?.id ?? "guest"
                busy = true; error = nil
                Task {
                    defer { busy = false }
                    do { try await app.install(item.addon.transportUrl, expectedManifestID: item.addon.manifest["id"].string) }
                    catch { if owner == (app.user?.id ?? "guest") { self.error = safeMessage(error) } }
                }
            } label: {
                HStack(spacing: 6) {
                    if busy { ProgressView().controlSize(.small) }
                    else { Image(installed ? "music-check" : "desktop-plus").resizable().scaledToFit().frame(width: 15, height: 15).accessibilityHidden(true) }
                    Text(installed ? "Instalado" : "Instalar").font(HarborTheme.font(12, weight: .semibold))
                }.padding(.horizontal, 14).frame(minHeight: 44)
                    .foregroundStyle(installed ? HarborTheme.accent : HarborTheme.background)
                    .background(installed ? HarborTheme.accent.opacity(0.15) : HarborTheme.ink, in: .capsule)
            }.buttonStyle(.plain).disabled(installed || busy || app.accountBusy || !app.storageReady)
                .accessibilityIdentifier("community-addon-install")
            if let error { Text(error).font(HarborTheme.font(11)).foregroundStyle(.orange) }
        }
    }
}
