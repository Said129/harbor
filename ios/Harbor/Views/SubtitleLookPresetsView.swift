import SwiftUI

/// Desktop's looks bar in the subtitle style settings: save the current look, apply one, or remove one.
struct SubtitleLookPresetsView: View {
    @Binding var options: PlaybackOptions
    private let store = SubtitleLookPresetStore()
    @State private var presets: [SubtitleLookPreset] = []
    @State private var selectedID: String?
    @State private var naming = false
    @State private var draft = ""

    var body: some View {
        let selected = presets.first { $0.id == selectedID }
        let dirty = selected.map { !SubtitleLookPresets.matches(options, $0) } ?? false
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(presets) { preset in
                    presetButton(preset)
                }
            }
            if naming {
                nameField
            } else {
                actions(selected: selected, dirty: dirty)
            }
        }
        .onAppear {
            presets = store.presets()
            selectedID = presets.first { SubtitleLookPresets.matches(options, $0) }?.id
        }
        .accessibilityIdentifier("subtitle-look-presets")
    }

    private func presetButton(_ preset: SubtitleLookPreset) -> some View {
        let matches = SubtitleLookPresets.matches(options, preset)
        let isSelected = preset.id == selectedID
        return Button { apply(preset) } label: {
            HStack(spacing: 6) {
                Text(preset.name).font(HarborTheme.font(14, weight: .semibold)).lineLimit(1)
                if isSelected && !matches {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                        .accessibilityLabel(DesktopInterfaceText.value("unsaved changes"))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(HarborTheme.surface, in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(matches ? HarborTheme.accent : HarborTheme.ink.opacity(0.1), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(matches ? .isSelected : [])
        .accessibilityHint(DesktopInterfaceText.value("Click to apply · Right-click to delete"))
        .contextMenu {
            Button(DesktopInterfaceText.value("Remove"), role: .destructive) { delete(preset) }
        }
        .accessibilityIdentifier("subtitle-look-" + preset.id)
    }

    @ViewBuilder
    private func actions(selected: SubtitleLookPreset?, dirty: Bool) -> some View {
        HStack(spacing: 8) {
            if let selected {
                Button(dirty ? DesktopInterfaceText.value("Override {name}", variables: ["name": selected.name]) : DesktopInterfaceText.value("Saved")) {
                    overwrite(selected)
                }
                .disabled(!dirty)
                .accessibilityHint(dirty ? DesktopInterfaceText.value("Overwrite {name} with this look", variables: ["name": selected.name]) : DesktopInterfaceText.value("No unsaved changes"))
                Button { startNaming() } label: { Image(systemName: "plus") }
                    .accessibilityLabel(DesktopInterfaceText.value("Save as a new look"))
            } else {
                Button(DesktopInterfaceText.value("Save look")) { startNaming() }
                    .accessibilityHint(DesktopInterfaceText.value("Save this look"))
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered)
        .tint(HarborTheme.accent)
        .font(HarborTheme.font(14, weight: .semibold))
    }

    private var nameField: some View {
        HStack(spacing: 8) {
            TextField(presets.isEmpty ? DesktopInterfaceText.value("Name your look") : DesktopInterfaceText.value("New look name"), text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveNamed() }
            Button(DesktopInterfaceText.value("Save")) { saveNamed() }
                .disabled(SubtitleLookPresets.normalizedName(draft) == nil)
            Button(DesktopInterfaceText.value("Cancel")) {
                naming = false
                draft = ""
            }
        }
        .buttonStyle(.bordered)
        .tint(HarborTheme.accent)
    }

    private func apply(_ preset: SubtitleLookPreset) {
        var next = options
        SubtitleLookPresets.apply(preset.values, to: &next)
        options = next
        selectedID = preset.id
    }

    private func startNaming() {
        draft = ""
        naming = true
    }

    private func saveNamed() {
        guard let added = SubtitleLookPresets.adding(name: draft, values: SubtitleLookPresets.snapshot(options), to: presets) else { return }
        commit(added)
        if let id = added.last?.id, presets.contains(where: { $0.id == id }) { selectedID = id }
        draft = ""
        naming = false
    }

    private func overwrite(_ preset: SubtitleLookPreset) {
        commit(SubtitleLookPresets.overriding(id: preset.id, values: SubtitleLookPresets.snapshot(options), in: presets))
    }

    private func delete(_ preset: SubtitleLookPreset) {
        commit(SubtitleLookPresets.removing(id: preset.id, from: presets))
        if selectedID == preset.id { selectedID = nil }
    }

    private func commit(_ list: [SubtitleLookPreset]) {
        presets = SubtitleLookPresets.committed(list)
        store.save(presets)
    }
}
