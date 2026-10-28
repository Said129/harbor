import SwiftUI

private struct CustomListAppKey: EnvironmentKey { static let defaultValue: AppModel? = nil }
extension EnvironmentValues {
    var customListApp: AppModel? {
        get { self[CustomListAppKey.self] }
        set { self[CustomListAppKey.self] = newValue }
    }
}

struct CustomListMembershipButton: View {
    let app: AppModel
    let item: JSONValue
    @State private var showing = false
    @Environment(\.locale) private var locale
    private var store: CustomListStore { app.customLists }
    private var member: Bool { store.lists.contains { $0.items.contains { $0.id == item["id"].string } } }
    var body: some View {
        Button { showing = true } label: {
            Image("desktop-layers").resizable().scaledToFit().frame(width: 20, height: 20)
                .frame(width: 48, height: 48).foregroundStyle(member ? HarborTheme.accent : HarborTheme.ink)
                .background(HarborTheme.background.opacity(0.8), in: .circle)
        }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Add to list", language: locale.identifier))
            .accessibilityIdentifier("detail-custom-lists")
            .popover(isPresented: $showing) { CustomListMembershipPicker(app: app, item: item).presentationCompactAdaptation(.sheet) }
            .onChange(of: app.accountOperationScope) { _, _ in showing = false }
    }
}

struct CustomListMembershipPicker: View {
    let app: AppModel
    let item: JSONValue
    @State private var creating = false
    @State private var notice: String?
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    private var store: CustomListStore { app.customLists }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key, language: locale.identifier) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CustomListStoreFeedback(store: store)
                    if !store.ready { ProgressView() }
                    else if store.lists.isEmpty { Text(text("No lists yet. Create your first one below.")).font(HarborTheme.font(12.5)).foregroundStyle(.secondary) }
                    ForEach(store.lists) { list in
                        let member = store.contains(item["id"].string ?? "", list: list.id)
                        Button { toggle(list, member: member) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: member ? "checkmark.square.fill" : "square").foregroundStyle(member ? HarborTheme.accent : HarborTheme.ink.opacity(0.6))
                                Text(list.name).font(HarborTheme.font(13)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(list.items.count)).font(HarborTheme.font(11)).foregroundStyle(.secondary)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(store.busy || !store.ready).accessibilityIdentifier("custom-list-membership")
                            .accessibilityValue(member ? text("Added") : text("Add to list"))
                    }
                    if let notice { Text(notice).font(.caption).foregroundStyle(HarborTheme.accent).accessibilityIdentifier("custom-list-membership-notice") }
                    Divider()
                    Button { creating = true } label: { Label(text("Create new list"), systemImage: "plus").frame(minHeight: 44) }
                        .disabled(!store.ready || store.busy || store.lists.count >= CustomListsDocument.maximumLists).accessibilityIdentifier("custom-list-membership-create")
                }.padding(20).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }.background(HarborTheme.background).navigationTitle(text("Add to list")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(text("Done")) { dismiss() } } }
        }.frame(idealWidth: 360).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .task(id: app.settingsOwner) { await store.load() }
            .onChange(of: app.accountOperationScope) { _, _ in dismiss() }
            .sheet(isPresented: $creating) {
                CustomListEditor(app: app, target: .create) { id in
                    let target = store, scope = app.accountOperationScope
                    Task { await target.apply(.add(id, item)); guard scope == app.accountOperationScope else { return }; dismiss() }
                }
            }
    }
    private func toggle(_ list: CustomList, member: Bool) {
        guard member || list.items.count < CustomListsDocument.maximumItems else {
            notice = DesktopInterfaceText.value("This list is full ({max} items)", variables: ["max": String(CustomListsDocument.maximumItems)], language: locale.identifier); return
        }
        let target = store, scope = app.accountOperationScope
        Task {
            let result = await target.apply(.toggle(list.id, item)); guard scope == app.accountOperationScope, result?.changed == true else { return }
            notice = DesktopInterfaceText.value(result?.contains == true ? "Added to \"{name}\"" : "Removed from \"{name}\"",
                variables: ["name": list.name], language: locale.identifier)
        }
    }
}
