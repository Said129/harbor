import SwiftUI

struct CustomSourceRowView: View {
    let row: DesktopSourceRow
    let title: String
    let app: AppModel
    let customization: PageCustomization
    @State private var edit: DesktopSourceFolder?
    @State private var requirement: DesktopSourceFolder.Requirement?
    @FocusState private var focusedFolder: Int?
    private var tileWidth: Double { row.folders.first?.poster == true ? 160 : 320 }
    private var tileHeight: Double { tileWidth * (row.folders.contains(where: \.poster) ? 1.5 : 9.0 / 16) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).padding(.horizontal).accessibilityIdentifier("catalog-title")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(Array(row.folders.enumerated()), id: \.offset) { index, folder in
                        folderAction(folder, index: index).buttonStyle(CustomSourcePressStyle())
                            .focused($focusedFolder, equals: index)
                            .frame(width: tileWidth)
                            .accessibilityLabel(folder.title).accessibilityIdentifier("source-folder-\(row.id)-\(index)")
                            .overlay(alignment: .topTrailing) {
                                if customization.editing {
                                    Button { edit = folder } label: {
                                        Image("ui-pencil-outline").resizable().scaledToFit().frame(width: 16, height: 16)
                                            .frame(width: 36, height: 36).background(.black.opacity(0.65), in: .circle).frame(minWidth: 44, minHeight: 44)
                                    }.buttonStyle(.plain).padding(6).accessibilityLabel(DesktopInterfaceText.value("Edit Folder Images"))
                                        .accessibilityIdentifier("source-images-\(row.id)-\(index)")
                                }
                            }
                    }
                }.padding(.horizontal).frame(height: tileHeight)
            }.scrollIndicators(.hidden).accessibilityIdentifier("source-folders-\(row.id)")
        }.accessibilityElement(children: .contain).accessibilityIdentifier("source-row-\(row.id)")
            .sheet(item: $edit) { folder in SourceFolderImagesEditor(row: row, folder: folder, customization: customization) }
            .popover(item: $requirement) { value in
                SourceFolderRequirementView(requirement: value)
                    .presentationCompactAdaptation(.sheet)
                    .presentationDetents([.height(360), .medium]).presentationDragIndicator(.visible)
                    .presentationCornerRadius(24).presentationBackground(ThemePreferences.shared.color("elevated"))
            }
    }
    @ViewBuilder private func folderAction(_ folder: DesktopSourceFolder, index: Int) -> some View {
        if let missing = folder.missingRequirement(hasTMDBKey: !MetadataPreferences.shared.tmdbKey.isEmpty, addons: app.addons) {
            Button { requirement = missing } label: { CustomSourceFolderCard(folder: folder, focused: focusedFolder == index) }
        } else if folder.destination != nil {
            NavigationLink { CustomSourceFolderBrowser(folder: folder, app: app) } label: {
                CustomSourceFolderCard(folder: folder, focused: focusedFolder == index)
            }
        } else {
            Button {} label: { CustomSourceFolderCard(folder: folder, focused: focusedFolder == index) }
        }
    }
}

private struct SourceFolderPressKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
    var sourceFolderPressed: Bool {
        get { self[SourceFolderPressKey.self] }
        set { self[SourceFolderPressKey.self] = newValue }
    }
}
private struct CustomSourcePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.sourceFolderPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct CustomSourceFolderCard: View {
    let folder: DesktopSourceFolder
    var focused = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sourceFolderPressed) private var pressed
    private var active: Bool { hovering || focused || pressed }
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: folder.cover, maxPixels: 700, showsPlaceholder: true)
            if active && !reduceMotion, let gif = folder.focus, !gif.isEmpty {
                SourceFocusArtwork(url: gif).transition(.opacity.animation(.easeInOut(duration: 0.5)))
            }
            Color.black.opacity(active ? 0 : 0.15)
            LinearGradient(colors: [.clear, .black.opacity(0.3), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
            if !folder.hideTitle {
                Text(folder.title).font(HarborTheme.font(21, weight: .medium)).foregroundStyle(.white)
                    .multilineTextAlignment(.leading).lineLimit(3).padding(.horizontal, 16).padding(.bottom, 14)
            }
        }.aspectRatio(folder.poster ? 2.0 / 3 : 16.0 / 9, contentMode: .fit)
            .background(HarborTheme.surface).clipShape(.rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(ThemePreferences.shared.color(active ? "edge" : "edge-soft"), lineWidth: 1) }
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(active ? 0.15 : 0), lineWidth: 1).padding(1) }
            .shadow(color: .black.opacity(0.5), radius: 9, y: 4)
            .offset(y: active && !reduceMotion ? -2 : 0)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: active)
    }
}

private struct SourceFolderRequirementView: View {
    let requirement: DesktopSourceFolder.Requirement
    @Environment(\.dismiss) private var dismiss
    private var title: String { DesktopInterfaceText.value(requirement == .tmdbKey ? "Missing TMDB Key" : "Addon not installed") }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                Text(title).font(HarborTheme.font(19, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button { dismiss() } label: {
                    Image("desktop-x").resizable().scaledToFit().frame(width: 16, height: 16).frame(width: 44, height: 44)
                        .background(HarborTheme.background.opacity(0.4), in: .circle)
                }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Close")).accessibilityIdentifier("source-requirement-close")
            }
            VStack(spacing: 16) {
                if case .addon(let id) = requirement {
                    Text("\(DesktopInterfaceText.value("This section depends on the addon")) \(Text(id).bold())")
                        .font(HarborTheme.font(15)).foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                    Text(DesktopInterfaceText.value("You must install this addon in your Stremio account first so Harbor can fetch its works."))
                        .font(HarborTheme.font(15)).foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                } else {
                    Text(DesktopInterfaceText.value("This section relies on TMDB discovery features."))
                        .font(HarborTheme.font(15)).foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                    Text(DesktopInterfaceText.value("Please add your TMDB API key in the Library & Metadata settings to view this folder."))
                        .font(HarborTheme.font(15)).foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                }
            }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            Button { dismiss() } label: { Text(DesktopInterfaceText.value("OK")).font(HarborTheme.font(15, weight: .medium)).frame(maxWidth: .infinity).frame(minHeight: 44) }
                .buttonStyle(.plain).foregroundStyle(.white).background(HarborTheme.accent, in: .capsule).accessibilityIdentifier("source-requirement-dismiss")
        }.padding(28).frame(idealWidth: 420, maxWidth: 420).background(ThemePreferences.shared.color("elevated"))
            .foregroundStyle(HarborTheme.ink)
            .accessibilityIdentifier("source-requirement")
    }
}

struct CustomSourceFolderBrowser: View {
    let folder: DesktopSourceFolder
    let app: AppModel
    @State private var catalog: CatalogRow?
    @State private var items: [Media] = []
    @State private var paging = DesktopGridPaging()
    @State private var busy = false
    @State private var error: String?
    @State private var loadedScope: String?
    private var destination: DesktopSourceFolder.Destination? { folder.destination }
    private var missingKey: Bool { folder.requiresTMDBKey && MetadataPreferences.shared.tmdbKey.isEmpty }
    var body: some View {
        Group {
            if missingKey {
                ContentUnavailableView {
                    Text(DesktopInterfaceText.value("Missing TMDB Key"))
                } description: { Text(DesktopInterfaceText.value("Please add your TMDB API key in the Library & Metadata settings to view this folder.")) }
            } else if let catalog { CatalogBrowserView(app: app, initial: catalog, titleOverride: folder.title) }
            else {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        if let error {
                            Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button(DesktopInterfaceText.value("Retry")) { Task { await load() } }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 12, alignment: .top)], spacing: 22) {
                            ForEach(items, id: \.identity) { media in NavigationLink(value: media) { Poster(media: media, width: nil) }.buttonStyle(.plain) }
                        }
                        if busy && items.isEmpty { ProgressView() }
                        if !items.isEmpty && !paging.finished && error == nil { ProgressView().task(id: paging.page) { await load() } }
                        else if !busy && items.isEmpty && paging.finished && error == nil { HarborNoMatchesView() }
                    }.padding()
                }.task(id: app.accountOperationScope) {
                    guard loadedScope != app.accountOperationScope else { return }
                    loadedScope = app.accountOperationScope; busy = false; catalog = nil; items = []; paging = DesktopGridPaging(); await load()
                }
            }
        }.background(HarborTheme.background).navigationTitle(destination?.title ?? folder.title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .accessibilityIdentifier("source-folder-browser")
    }
    private func load() async {
        guard !busy, !paging.finished, !missingKey else { return }
        busy = true; error = nil
        let scope = app.accountOperationScope
        defer { if scope == app.accountOperationScope { busy = false } }
        do {
            guard let destination else { throw HarborError(code: "custom-source-import") }
            if case .catalog(_, let addon, let type, let id) = destination {
                let result = try await app.service.sourceCatalog(addonID: addon, type: type, id: id, addons: app.addons)
                try Task.checkCancellation(); guard scope == app.accountOperationScope else { return }
                catalog = result; return
            }
            let next = try await CustomSourceCatalog().page(destination, page: paging.nextPage, configuration: MetadataPreferences.shared.configuration(), service: app.service)
            try Task.checkCancellation(); guard scope == app.accountOperationScope else { return }
            var seen = Set(items.map(\.identity)); let additions = next.filter { seen.insert($0.identity).inserted }
            items.append(contentsOf: additions); paging.received(next.count)
        } catch is CancellationError { return }
        catch {
            guard scope == app.accountOperationScope else { return }
            if let failure = error as? HarborError, failure.code == "custom-source-addon" {
                self.error = DesktopInterfaceText.value("You must install this addon in your Stremio account first so Harbor can fetch its works.")
            } else { self.error = safeMessage(error) }
        }
    }
}
