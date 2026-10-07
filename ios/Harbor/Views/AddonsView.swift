import SwiftUI

struct AddonsView: View {
    let app: AppModel
    @State private var tab = AddonStoreTab.discover
    @State private var query = ""
    @State private var category = AddonCategory.all
    @State private var allowAdult = false
    @State private var directory: [Addon] = []
    @State private var loading = false
    @State private var loaded = false
    @State private var failedSources = 0
    @State private var url = ""
    @State private var error: String?
    @State private var installing = false
    @State private var selectedAddon: Addon?
    @State private var reorder = false
    @FocusState private var editingURL: Bool
    private var visible: [Addon] {
        let source = tab == .installed ? app.addons : directory
        return source.filter { addon in
            (tab == .installed || allowAdult || !addon.adult) && (category == .all || addon.category == category) &&
            (query.isEmpty || (addon.name + " " + (addon.manifest["description"].string ?? "")).localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(AddonStoreTab.allCases) { value in
                            HarborPill(title: value == .installed ? "Instalados  \(app.addons.count)" : value.title, selected: tab == value) { tab = value }
                                .accessibilityIdentifier("addon-tab-\(value.rawValue)")
                        }
                    }
                }.scrollIndicators(.hidden)
                HarborSearchField(prompt: "Buscar addons", text: $query).accessibilityIdentifier("addon-search")
                installation
                if loading { ProgressView("Cargando addons…") }
                if failedSources > 0 && tab != .installed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(directory.isEmpty ? "No se pudieron cargar los directorios. Tus addons instalados se conservan." : "Parte del directorio no está disponible. Se conservan los resultados disponibles.").font(.caption).foregroundStyle(.secondary)
                        Button("Reintentar directorios") { Task { await loadDirectory(refresh: true) } }.buttonStyle(HarborAccountButtonStyle())
                    }
                }
                if tab == .discover, query.isEmpty, category == .all, let featured = visible.first {
                    featuredCard(featured)
                    HarborPageHeading(title: "Explora por categoría", subtitle: "Encuentra fuentes, catálogos y subtítulos para tus addons.")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(AddonCategory.allCases.filter { $0 != .all && ($0 != .adult || allowAdult) }) { value in
                            Button { category = value; tab = .browse } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(value.icon).resizable().scaledToFit().frame(width: 36, height: 36).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(value.title).font(HarborTheme.font(14, weight: .semibold))
                                }.frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).padding(14).background(HarborTheme.surface, in: .rect(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Text(tab == .installed ? "Tus addons" : "Directorio de Stremio").font(.headline)
                    Spacer()
                    if tab == .installed { Button("Ordenar") { reorder = true }.font(.caption).disabled(app.accountBusy || !app.storageReady).accessibilityIdentifier("addon-reorder") }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(AddonCategory.allCases.filter { $0 != .adult || allowAdult || tab == .installed }) { value in
                            HarborPill(title: value.title, selected: category == value) { category = value }
                        }
                        if tab != .installed { HarborPill(title: "Mostrar adultos", selected: allowAdult) { allowAdult.toggle(); if !allowAdult && category == .adult { category = .all } }.accessibilityIdentifier("addon-adult-filter") }
                    }
                }.scrollIndicators(.hidden)
                ForEach(visible) { addon in AddonStoreCard(app: app, addon: resolved(addon), installed: installed(addon)) { selectedAddon = resolved(addon) } }
                if !loading && visible.isEmpty { Text(query.isEmpty ? "No hay addons en esta categoría." : "No hay addons que coincidan con la búsqueda.").font(.subheadline).foregroundStyle(.secondary) }
                if tab != .installed { Text("Los datos proceden de los directorios públicos de Stremio. La instalación consulta el manifest actual del addon.").font(.caption).foregroundStyle(.secondary) }
            }.padding()
        }.scrollDismissesKeyboard(.interactively).background(HarborTheme.background).navigationTitle("").toolbar(.hidden, for: .navigationBar)
            .task { if !loaded { await loadDirectory() } }
            .refreshable { await loadDirectory(refresh: true) }
            .sheet(item: $selectedAddon) { addon in NavigationStack { AddonDetailView(app: app, addon: addon) }.font(HarborTheme.font()).tint(HarborTheme.accent) }
            .sheet(isPresented: $reorder) { AddonOrderView(app: app) }
            .onChange(of: app.user?.id) { _, _ in url = ""; error = nil; query = ""; selectedAddon = nil; reorder = false }
    }
    private var installation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image("nav-addons").resizable().scaledToFit().frame(width: 18, height: 18).foregroundStyle(.secondary)
                SecureField("Manifest URL o enlace stremio://", text: $url).font(HarborTheme.font(13)).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).focused($editingURL).accessibilityIdentifier("addon-manifest-url")
            }.padding(.horizontal, 14).frame(minHeight: 44).background(HarborTheme.surface, in: .capsule)
            HStack {
                Button("Instalar addon") { install() }.buttonStyle(HarborAccountButtonStyle(primary: true))
                    .disabled(installing || app.accountBusy || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !app.storageReady).accessibilityIdentifier("addon-install")
                if installing { ProgressView().accessibilityIdentifier("addon-install-progress") }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            if app.user != nil { Text("Instalación, eliminación y orden se sincronizan con Stremio. La activación se aplica en este iPhone.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func featuredCard(_ addon: Addon) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("DESCUBRE EN STREMIO").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(HarborTheme.accent)
            HStack(spacing: 14) { AddonLogo(addon: addon, size: 54); Text(addon.name).font(.custom("Fraunces-9ptBlack", size: 28)) }
            if let description = addon.manifest["description"].string { Text(String(description.prefix(1_000))).font(.subheadline).foregroundStyle(.secondary).lineLimit(4) }
            Button("Detalles") { selectedAddon = resolved(addon) }.buttonStyle(HarborAccountButtonStyle(primary: true))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background {
                ZStack {
                    HarborTheme.surface
                    if let background = addon.backgroundURL {
                        GeometryReader { geometry in
                            Artwork(url: background, maxPixels: 900, failureIcon: "nav-addons").frame(width: geometry.size.width, height: geometry.size.height)
                                .overlay { LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.7)], startPoint: .leading, endPoint: .trailing) }
                        }
                    }
                }
            }.clipShape(.rect(cornerRadius: 22))
    }
    private func installed(_ addon: Addon) -> Bool { app.addons.contains { $0.id == addon.id || $0.manifest["id"].string == addon.manifest["id"].string } }
    private func resolved(_ addon: Addon) -> Addon { app.addons.first { $0.id == addon.id } ?? app.addons.first { $0.manifest["id"].string == addon.manifest["id"].string } ?? addon }
    private func install() {
        guard !installing else { return }
        editingURL = false
        let link = url, owner = app.user?.id ?? "guest"
        installing = true; error = nil; tab = .installed; query = ""; category = .all
        Task {
            defer { installing = false }
            do { try await app.install(link); guard owner == (app.user?.id ?? "guest") else { return }; url = "" }
            catch { guard owner == (app.user?.id ?? "guest") else { return }; self.error = safeMessage(error) }
        }
    }
    private func loadDirectory(refresh: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await AddonDirectory.shared.load(refresh: refresh)
            try Task.checkCancellation()
            directory = result.addons; failedSources = result.failedSources; loaded = !directory.isEmpty
        } catch is CancellationError { return }
        catch { failedSources = AddonDirectory.sources.count }
    }
}
private enum AddonStoreTab: String, CaseIterable, Identifiable {
    case discover, browse, installed
    var id: String { rawValue }
    var title: String { switch self { case .discover: "Descubrir"; case .browse: "Explorar"; case .installed: "Instalados" } }
}
private struct AddonStoreCard: View {
    let app: AppModel
    let addon: Addon
    let installed: Bool
    let open: () -> Void
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 14) {
                    AddonLogo(addon: addon, size: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(addon.name).font(HarborTheme.font(15, weight: .semibold))
                        if let text = addon.manifest["description"].string { Text(String(text.prefix(1_000))).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Detalles de \(addon.name)").accessibilityIdentifier("addon-details")
            HStack(spacing: 10) {
                Text(addon.types.prefix(3).joined(separator: " · ").uppercased()).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if installed {
                    Toggle(addon.name, isOn: Binding(get: { app.addons.first { $0.id == addon.id }?.enabled ?? false }, set: { enabled in
                        do { try app.setEnabled(addon, enabled); Task { await app.loadHome() } }
                        catch { self.error = safeMessage(error) }
                    })).labelsHidden().fixedSize().accessibilityLabel(addon.name).disabled(!app.storageReady || app.accountBusy)
                } else { Button(addon.configurable ? "Configurar" : "Instalar", action: open).buttonStyle(HarborAccountButtonStyle(primary: true)) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(18).background(HarborTheme.surface.opacity(0.7), in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.05), lineWidth: 1) }
    }
}
private struct AddonOrderView: View {
    let app: AppModel
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.orange) }
                ForEach(app.addons) { addon in HStack { AddonLogo(addon: addon, size: 30); Text(addon.name) } }
                    .onMove { offsets, destination in Task { do { try await app.move(offsets, to: destination) } catch { self.error = safeMessage(error) } } }
            }.environment(\.editMode, .constant(.active)).disabled(app.accountBusy || !app.storageReady)
                .navigationTitle("Orden de addons").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
        }.font(HarborTheme.font()).tint(HarborTheme.accent).onChange(of: app.user?.id) { _, _ in dismiss() }
    }
}
