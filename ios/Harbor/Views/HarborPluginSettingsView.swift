import SwiftUI

struct HarborPluginSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HarborPluginSettingsDraft
    @State private var saveTask: Task<Void, Never>?

    init(manager: HarborStreamPluginManager, plugin: HarborInstalledStreamPlugin) {
        _draft = State(initialValue: HarborPluginSettingsDraft(manager: manager, plugin: plugin))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(draft.plugin.entry.name).font(HarborTheme.font(22, weight: .semibold))
                if !draft.ready && draft.failure == nil { ProgressView(DesktopInterfaceText.value("Loading plugins...")) }
                if let failure = draft.failure { Text(failure).font(HarborTheme.font(14)).foregroundStyle(ThemePreferences.shared.color("danger")) }
                ForEach(Array(draft.fields.enumerated()), id: \.offset) { index, value in
                    field(value).accessibilityIdentifier("plugin-settings-field-\(index)")
                }
                HStack(spacing: 14) {
                    Button(DesktopInterfaceText.value("Cancel")) { draft.clear(); dismiss() }.buttonStyle(HarborAccountButtonStyle())
                    Spacer()
                    if draft.saving { ProgressView() }
                    Button(DesktopInterfaceText.value("Save")) {
                        saveTask = Task { if await draft.save() { dismiss() } }
                    }.buttonStyle(HarborAccountButtonStyle()).disabled(!draft.ready || draft.saving)
                        .accessibilityIdentifier("plugin-settings-save")
                }
            }.padding(20).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .scrollDismissesKeyboard(.interactively).presentationDragIndicator(.visible)
            .accessibilityIdentifier("plugin-settings-editor")
            .task { await draft.load() }
            .onDisappear { saveTask?.cancel(); saveTask = nil; draft.clear() }
    }

    @ViewBuilder private func field(_ field: HarborPluginSettingsField) -> some View {
        if field.type == "header" {
            Text(field.label).font(HarborTheme.font(18, weight: .semibold)).accessibilityAddTraits(.isHeader)
        } else if field.type == "info" {
            Text(field.label).font(HarborTheme.font(14)).foregroundStyle(.secondary)
        } else if let key = field.key {
            VStack(alignment: .leading, spacing: 8) {
                if field.type == "toggle" {
                    Toggle(field.label, isOn: Binding(get: { draft.values[key] == .bool(true) }, set: { draft.values[key] = .bool($0) }))
                        .tint(HarborTheme.accent).frame(minHeight: 44)
                } else {
                    Text(field.label).font(HarborTheme.font(14, weight: .semibold))
                    if field.type == "select" {
                        selection(field, key: key)
                    } else {
                        Group {
                            if field.isPassword == true { SecureField(field.placeholder ?? "", text: string(key)).privacySensitive() }
                            else { TextField(field.placeholder ?? "", text: string(key)) }
                        }.font(HarborTheme.font(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(14).frame(minHeight: 48).background(HarborTheme.surface, in: .rect(cornerRadius: 8))
                            .accessibilityLabel(field.label)
                    }
                }
                if let description = field.description { Text(description).font(HarborTheme.font(13)).foregroundStyle(.secondary) }
            }.disabled(draft.saving)
        }
    }
    private func string(_ key: String) -> Binding<String> {
        Binding(get: { draft.values[key]?.string ?? "" }, set: { draft.values[key] = .string($0) })
    }
    private func selection(_ field: HarborPluginSettingsField, key: String) -> some View {
        let options = field.options ?? []
        let value = draft.values[key]?.string ?? ""
        return Menu {
            ForEach(options.indices, id: \.self) { index in
                Button(options[index].label) { draft.values[key] = .string(options[index].value) }
            }
        } label: {
            HStack {
                Text(options.first(where: { $0.value == value })?.label ?? value)
                Spacer(minLength: 12)
                Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 16, height: 16).rotationEffect(.degrees(90))
            }.font(HarborTheme.font(15)).padding(14).frame(minHeight: 48)
                .background(HarborTheme.surface, in: .rect(cornerRadius: 8)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(field.label).accessibilityValue(value)
    }
}
