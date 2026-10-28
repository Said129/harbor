import SwiftUI

struct CustomListsContent: View {
    let app: AppModel
    @State private var selected: String?
    @State private var editor: CustomListEditorTarget?
    @State private var deleting: CustomList?
    @State private var dropTarget: String?
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var store: CustomListStore { app.customLists }
    private var dragPrefix: String { "harbor-list:" + EBookShelf.hash(app.accountOperationScope) + ":" }
    private func text(_ key: String, _ variables: [String: String] = [:]) -> String { DesktopInterfaceText.value(key, variables: variables, language: locale.identifier) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            CustomListStoreFeedback(store: store)
            if !store.ready { ProgressView().frame(maxWidth: .infinity, minHeight: 100) }
            else if let selected, let list = store.lists.first(where: { $0.id == selected }) {
                CustomListDetailContent(app: app, list: list, onBack: { self.selected = nil },
                    onEdit: { editor = .edit(list) }, onDelete: { deleting = list }).id(list.id)
            } else if store.lists.isEmpty { empty }
            else {
                HStack {
                    Text(text("{n} / {max} lists", ["n": String(store.lists.count), "max": String(CustomListsDocument.maximumLists)]))
                        .font(HarborTheme.font(12)).foregroundStyle(.secondary).accessibilityIdentifier("custom-lists-count")
                    Spacer()
                    createButton
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 20, alignment: .topLeading)], alignment: .leading, spacing: 20) {
                    ForEach(store.lists) { list in
                        Button { selected = list.id } label: { CustomListCard(list: list) }
                            .buttonStyle(.plain).accessibilityLabel(list.name).accessibilityIdentifier("custom-list-card")
                            .contextMenu {
                                Button(text("Rename list")) { editor = .edit(list) }
                                Button(text("Move up")) { move(list.id, by: -1) }.disabled(store.lists.first?.id == list.id || store.busy)
                                Button(text("Move down")) { move(list.id, by: 1) }.disabled(store.lists.last?.id == list.id || store.busy)
                                Button(text("Delete list"), role: .destructive) { deleting = list }
                            }
                            .draggable(dragPrefix + list.id)
                            .dropDestination(for: String.self) { values, _ in
                                guard !store.busy, let value = values.first, value.hasPrefix(dragPrefix) else { return false }
                                return reorder(String(value.dropFirst(dragPrefix.count)), before: list.id)
                            } isTargeted: { active in dropTarget = active ? list.id : nil }
                            .overlay { if dropTarget == list.id { RoundedRectangle(cornerRadius: 12).stroke(HarborTheme.accent, lineWidth: 2).allowsHitTesting(false) } }
                    }
                }.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.lists.map(\.id))
            }
        }.task(id: app.settingsOwner) { await store.load() }
            .onChange(of: app.accountOperationScope) { _, _ in selected = nil; editor = nil; deleting = nil; dropTarget = nil }
            .onChange(of: store.lists.map(\.id)) { _, ids in if let selected, !ids.contains(selected) { self.selected = nil } }
            .sheet(item: $editor) { target in CustomListEditor(app: app, target: target) { id in selected = id } }
            .confirmationDialog(text("Delete list"), isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button(text("Delete list"), role: .destructive) {
                    guard let list = deleting else { return }; deleting = nil
                    let target = store; Task { await target.apply(.delete(list.id)) }
                }.accessibilityIdentifier("custom-list-delete-confirm")
                Button(text("Cancel"), role: .cancel) { deleting = nil }
            } message: { if let deleting { Text(deleting.name) } }
    }
    private var createButton: some View {
        Button { editor = .create } label: { Label(text("Create new list"), systemImage: "plus").font(HarborTheme.font(13, weight: .semibold)).frame(minHeight: 44) }
            .buttonStyle(HarborAccountButtonStyle()).disabled(!store.ready || store.busy || store.lists.count >= CustomListsDocument.maximumLists)
            .accessibilityIdentifier("custom-list-create")
    }
    private var empty: some View {
        VStack(spacing: 16) {
            Image("desktop-layers").resizable().scaledToFit().frame(width: 24, height: 24).padding(16)
                .background(HarborTheme.surface.opacity(0.6), in: .circle).accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(text("Create your first list")).font(HarborTheme.font(20, weight: .medium))
                Text(text("Group the movies and shows you love. Rewatch shelf, weekend picks, whatever keeps them close."))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary)
            }
            createButton
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 32).padding(.vertical, 80)
            .background(HarborTheme.background.opacity(0.3), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
    }
    private func move(_ id: String, by offset: Int) {
        let ids = store.lists.map(\.id); guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        var next = ids; next.swapAt(index, index + offset); let target = store; Task { await target.apply(.reorderLists(next)) }
    }
    private func reorder(_ id: String, before other: String) -> Bool {
        guard id != other, store.lists.contains(where: { $0.id == id }) else { return false }
        var ids = store.lists.map(\.id).filter { $0 != id }; guard let index = ids.firstIndex(of: other) else { return false }
        ids.insert(id, at: index); let target = store; Task { await target.apply(.reorderLists(ids)) }; return true
    }
}

struct CustomListCard: View {
    let list: CustomList
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                HarborTheme.background
                if list.items.isEmpty { Image("desktop-layers").resizable().scaledToFit().frame(width: 22, height: 22).foregroundStyle(.secondary) }
                else {
                    let items = Array(list.items.prefix(3))
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        let offset = Double(index) - Double(items.count - 1) / 2
                        Artwork(url: item.poster, maxPixels: 240).frame(width: 70, height: 105).clipped().clipShape(.rect(cornerRadius: 8))
                            .overlay { RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.25), lineWidth: 1) }
                            .shadow(color: .black.opacity(0.6), radius: 12, y: 10)
                            .rotationEffect(.degrees(offset * 7)).offset(x: offset * 30).zIndex(Double(index))
                    }
                }
                VStack { Spacer(); LinearGradient(colors: [.clear, HarborTheme.surface.opacity(0.95)], startPoint: .top, endPoint: .bottom).frame(height: 64) }
            }.frame(height: 136).clipped().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(list.name).font(.custom("Fraunces-9ptBlack", size: 16).weight(.medium)).lineLimit(1)
                if !list.description.isEmpty { Text(list.description).font(HarborTheme.font(12.5)).foregroundStyle(.secondary).lineLimit(2) }
                Text(CustomListPresentation.count(list, locale: locale))
                    .font(HarborTheme.font(12)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16).frame(maxWidth: .infinity, alignment: .leading)
        }.background(HarborTheme.surface).clipShape(.rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1) }
    }
}

struct CustomListEditorTarget: Identifiable {
    let id: String
    let list: CustomList?
    static var create: Self { .init(id: "create", list: nil) }
    static func edit(_ list: CustomList) -> Self { .init(id: list.id, list: list) }
}

struct CustomListEditor: View {
    let app: AppModel
    let target: CustomListEditorTarget
    let created: (String) -> Void
    @State private var name: String
    @State private var description: String
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    private var store: CustomListStore { app.customLists }
    init(app: AppModel, target: CustomListEditorTarget, created: @escaping (String) -> Void) {
        self.app = app; self.target = target; self.created = created
        _name = State(initialValue: target.list?.name ?? ""); _description = State(initialValue: target.list?.description ?? "")
    }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key, language: locale.identifier) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(text("Group the movies and shows you want to keep close.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(text("List name")).font(.caption.weight(.medium)).textCase(.uppercase)
                        TextField(text("Weekend watchlist"), text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
                            .submitLabel(.done).onSubmit(save).accessibilityIdentifier("custom-list-name")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(text("Description")).font(.caption.weight(.medium)).textCase(.uppercase)
                        TextField(text("A short note about this list"), text: $description, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3...5)
                            .accessibilityIdentifier("custom-list-description")
                    }
                    CustomListStoreFeedback(store: store)
                    if target.list == nil && store.lists.count >= CustomListsDocument.maximumLists {
                        Text(DesktopInterfaceText.value("You have reached {max} lists. Remove one to make room.",
                            variables: ["max": String(CustomListsDocument.maximumLists)], language: locale.identifier)).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }.background(HarborTheme.background).navigationTitle(text(target.list == nil ? "New list" : "Rename list")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(text("Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(text(target.list == nil ? "Create" : "Save")) { save() }
                        .disabled(!store.ready || store.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (target.list == nil && store.lists.count >= CustomListsDocument.maximumLists))
                        .accessibilityIdentifier("custom-list-editor-save") }
                }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .onChange(of: name) { _, value in if value.utf16.count > 60 { name = CustomListPresentation.limit(value, utf16: 60) } }
            .onChange(of: description) { _, value in if value.utf16.count > 240 { description = CustomListPresentation.limit(value, utf16: 240) } }
            .onChange(of: app.accountOperationScope) { _, _ in dismiss() }
    }
    private func save() {
        guard store.ready, !store.busy, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let store = store, scope = app.accountOperationScope, title = name, note = description
        Task {
            if let list = target.list {
                await store.apply(.rename(list.id, title)); guard scope == app.accountOperationScope else { return }
                await store.apply(.describe(list.id, note)); guard scope == app.accountOperationScope else { return }; dismiss()
            } else if let id = await store.apply(.create(title, note, id: UUID().uuidString))?.createdID, scope == app.accountOperationScope {
                created(id); dismiss()
            }
        }
    }
}

enum CustomListPresentation {
    static func limit(_ value: String, utf16 limit: Int) -> String {
        var count = 0
        return String(value.prefix { character in count += String(character).utf16.count; return count <= limit })
    }
    static func updated(_ list: CustomList, locale: Locale) -> String? {
        guard let timestamp = list.raw["updatedAt"].numericValue, timestamp > 0 else { return nil }
        let formatter = RelativeDateTimeFormatter(); formatter.locale = locale; formatter.unitsStyle = .abbreviated
        let when = formatter.localizedString(for: Date(timeIntervalSince1970: timestamp / 1_000), relativeTo: Date())
        return DesktopInterfaceText.value("Updated {when}", variables: ["when": when], language: locale.identifier)
    }
    static func count(_ list: CustomList, locale: Locale, limit: Bool = false) -> String {
        let key = limit ? "{n} / {max} items" : list.items.count == 1 ? "1 item" : "{n} items"
        let count = DesktopInterfaceText.value(key, variables: ["n": String(list.items.count), "max": String(CustomListsDocument.maximumItems)], language: locale.identifier)
        return [count, updated(list, locale: locale)].compactMap { $0 }.joined(separator: " · ")
    }
}

struct CustomListStoreFeedback: View {
    let store: CustomListStore
    @Environment(\.locale) private var locale
    var body: some View {
        if let error = store.error {
            VStack(alignment: .leading, spacing: 8) {
                Text(DesktopInterfaceText.value(error, language: locale.identifier)).font(.caption).foregroundStyle(.orange)
                Button(DesktopInterfaceText.value(store.unsaved ? "Save" : "Retry", language: locale.identifier)) {
                    Task { if store.unsaved { await store.save() } else { await store.load(force: true) } }
                }.disabled(store.busy).frame(minHeight: 44)
            }
        }
    }
}
