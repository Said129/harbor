import SwiftUI

struct PageCustomizeButton: View {
    let rails: [PageRail]
    let customization: PageCustomization
    @State private var editing = false
    var body: some View {
        HStack { Spacer(); Button { editing = true } label: { Label("Personalizar página", image: "ui-pencil-outline").font(.caption).padding(.horizontal, 12).padding(.vertical, 8).background(HarborTheme.surface, in: .rect(cornerRadius: 8)) } }.padding(.horizontal)
            .sheet(isPresented: $editing) { PageCustomizationView(rails: rails, customization: customization) }
    }
}

private struct PageCustomizationView: View {
    let rails: [PageRail]
    let customization: PageCustomization
    @Environment(\.dismiss) private var dismiss
    private var ordered: [PageRail] { customization.ordered(rails, includeHidden: true) }
    var body: some View {
        NavigationStack {
            List {
                Section("Destacados") {
                    Picker("Usar una fila como destacados", selection: Binding(get: { customization.layout.heroSource ?? "automatic" }, set: { id in customization.change { $0.heroSource = id == "automatic" ? nil : id } })) {
                        Text("Automático").tag("automatic"); ForEach(ordered) { Text(customization.title($0, among: rails)).tag($0.id) }
                    }
                    Toggle("Botón Reproducir rectangular", isOn: setting(\.playButtonSquare))
                    Toggle("Mostrar Más información", isOn: setting(\.secondaryMoreInfo))
                    if customization.page == "home" { Toggle("Continuar viendo al principio", isOn: setting(\.cwTop)) }
                }.disabled(!customization.ready)
                Section { Text("Arrastra las filas para cambiar su orden. Abre sus opciones para ocultarlas o cambiar el título.").font(.caption).foregroundStyle(.secondary) }
                Section("Filas") {
                    ForEach(ordered) { rail in
                        DisclosureGroup {
                            Toggle("Mostrar fila", isOn: Binding(get: { !customization.layout.hidden.contains(rail.id) }, set: { visible in customization.change { if visible { $0.hidden.remove(rail.id) } else { $0.hidden.insert(rail.id) } } }))
                            TextField("Título", text: Binding(get: { customization.layout.renamed[rail.id] ?? rail.title }, set: { title in customization.change { value in let clean = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)); value.renamed[rail.id] = clean.isEmpty || clean == rail.title ? nil : clean } }))
                            Toggle("Numeración Top 10", isOn: Binding(get: { customization.ranked(rail) }, set: { ranked in customization.change { if ranked { $0.numerals.insert(rail.id); $0.plain.remove(rail.id) } else { $0.numerals.remove(rail.id); $0.plain.insert(rail.id) } } }))
                            if customization.layout.renamed[rail.id] != nil { Button("Restablecer título") { customization.change { $0.renamed[rail.id] = nil } } }
                        } label: { HStack { Text(customization.title(rail, among: rails)); Spacer(); if customization.layout.hidden.contains(rail.id) { Image(systemName: "eye.slash").foregroundStyle(.secondary) } } }
                    }.onMove { from, to in var items = ordered.map(\.id); items.move(fromOffsets: from, toOffset: to); customization.change { $0.order = items } }
                }.disabled(!customization.ready)
                if let error = customization.error { Text(error).font(.caption).foregroundStyle(.orange) }
                Section { Button("Restablecer página", role: .destructive) { customization.reset() }.disabled(!customization.ready) }
            }.environment(\.editMode, .constant(.active)).navigationTitle("Personalizar página")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { dismiss() } } }
        }
    }
    private func setting(_ key: WritableKeyPath<PageLayout, Bool>) -> Binding<Bool> { Binding(get: { customization.layout[keyPath: key] }, set: { value in customization.change { $0[keyPath: key] = value } }) }
}

struct CustomizedRails: View {
    let rails: [PageRail]
    let app: AppModel
    let customization: PageCustomization
    var body: some View {
        LazyVStack(spacing: 24) {
            ForEach(customization.ordered(rails)) { rail in
                let title = customization.title(rail, among: rails)
                if customization.ranked(rail) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text(title).font(.headline).accessibilityIdentifier("catalog-title"); Spacer(); browse(rail) }.padding(.horizontal)
                        TopTenRail(metas: rail.metas)
                    }
                } else {
                    switch rail {
                    case .catalog(let row): CatalogRails(rows: [row], app: app, titleOverrides: [row.id: title])
                    case .discovery(let row):
                        DiscoveryRails(rows: [row], app: app, titleOverrides: [row.id: title], disableDefaultRanking: true)
                    }
                }
            }
        }
    }
    @ViewBuilder private func browse(_ rail: PageRail) -> some View {
        switch rail {
        case .catalog(let row): NavigationLink { CatalogBrowserView(app: app, initial: row) } label: { Label("Ver todo", systemImage: "chevron.right").font(.caption).foregroundStyle(.secondary) }.accessibilityIdentifier("catalog-browser-link")
        case .discovery(let row): NavigationLink("Ver todo") { DiscoveryGrid(rail: row, app: app) }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CustomizedHero: View {
    let rails: [PageRail]
    let defaults: [Media]
    let app: AppModel
    let customization: PageCustomization
    @State private var selected: [Media] = []
    @State private var enrichedSignature = ""
    private var source: PageRail? { rails.first { $0.id == customization.layout.heroSource } }
    private var signature: String { (source?.id ?? "automatic") + "|" + (source?.metas.prefix(5).map(\.identity).joined(separator: "|") ?? "") + "|" + (app.user?.id ?? "guest") + "|" + app.addons.filter(\.enabled).map(\.id).joined() + "|" + MetadataPreferences.shared.region + "|" + MetadataPreferences.shared.language + "|" + String(MetadataPreferences.shared.translateTitles) + "|" + EBookShelf.hash(MetadataPreferences.shared.tmdbKey) }
    private var metas: [Media] { source == nil ? defaults : enrichedSignature == signature && !selected.isEmpty ? selected : Array(source?.metas.prefix(5) ?? []) }
    var body: some View {
        Group { if !metas.isEmpty { CinemaHero(metas: metas, app: app, playSquare: customization.layout.playButtonSquare, moreInfo: customization.layout.secondaryMoreInfo) } }
            .task(id: signature) {
                guard let source else { selected = []; enrichedSignature = ""; return }
                let currentSignature = signature
                let originals = Array(source.metas.prefix(5)); selected = originals; enrichedSignature = currentSignature
                let owner = app.user?.id ?? "guest", service = app.service, addons = app.addons
                let fetched = await withTaskGroup(of: (Int, Media).self, returning: [(Int, Media)].self) { group in
                    for (index, media) in originals.enumerated() { group.addTask { (index, (try? await service.metadata(media, addons: addons)) ?? media) } }
                    var result: [(Int, Media)] = []; for await value in group { result.append(value) }; return result
                }
                guard !Task.isCancelled, owner == (app.user?.id ?? "guest"), customization.layout.heroSource == source.id, currentSignature == signature else { return }
                selected = fetched.sorted { $0.0 < $1.0 }.map(\.1)
            }
    }
}
