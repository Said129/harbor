import SwiftUI

/// Desktop's "Saved stream filters" (`views/settings/stream-filters-panel.tsx`): choose the active filter,
/// create, edit and delete. The builder is `CustomStreamFilterEditor` below (`play-picker/filter-builder.tsx`).
struct CustomStreamFiltersView: View {
    @State private var filters: [CustomStreamFilter] = []
    @State private var activeID: String?
    @State private var editing: CustomStreamFilter?
    @State private var pendingDelete: CustomStreamFilter?

    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HarborSettingsSection(text("Saved stream filters"),
                                      note: text("Save the stream quality you prefer. Streams must match every category you set; leave a category blank to accept any value. If nothing matches, Harbor uses the next best available source.")) {
                    noFilterRow
                    ForEach(filters) { filter in filterRow(filter) }
                    createRow
                }
                Text(text("A filter applies everywhere Harbor picks a stream: the source picker, the instant pick, and Big Picture on TV."))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
        .navigationTitle(text("Saved stream filters")).navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("stream-filters-settings")
        .onAppear(perform: reload)
        .sheet(item: $editing) { filter in
            CustomStreamFilterEditor(initial: filter, isNew: !filters.contains { $0.id == filter.id },
                                     onSave: { saved in save(saved) }, onDelete: { id in delete(id) })
        }
        .alert(text("Delete filter"), isPresented: deleteBinding, presenting: pendingDelete) { filter in
            Button(text("Cancel"), role: .cancel) { pendingDelete = nil }
            Button(text("Delete"), role: .destructive) { delete(filter.id) }
        } message: { filter in
            Text(DesktopInterfaceText.value("Delete {name}? Saved filters cannot be brought back.", variables: ["name": displayName(filter)]))
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func reload() {
        filters = CustomStreamFilterStore.filters()
        activeID = CustomStreamFilterStore.activeFilter()?.id
    }

    private func save(_ filter: CustomStreamFilter) {
        CustomStreamFilterStore.save(filter)
        reload()
    }

    private func toggle(_ id: String) {
        CustomStreamFilterStore.toggleActive(id)
        reload()
    }

    private func delete(_ id: String) {
        CustomStreamFilterStore.delete(id)
        pendingDelete = nil
        reload()
    }

    private func displayName(_ filter: CustomStreamFilter) -> String {
        let trimmed = filter.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text("Untitled filter") : trimmed
    }

    private var noFilterRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowText(text("No filter"), text("Remove the saved quality preference. Your other stream settings still apply."))
            activeButton(on: activeID == nil, disabled: false) {
                CustomStreamFilterStore.setActiveID(nil)
                reload()
            }
        }
    }

    private func filterRow(_ filter: CustomStreamFilter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            rowText(displayName(filter), summaryLine(filter))
            HStack(spacing: 10) {
                activeButton(on: activeID == filter.id, disabled: !filter.hasPreferences) { toggle(filter.id) }
                Button { editing = filter } label: {
                    Label(text("Edit"), systemImage: "pencil").frame(minHeight: 44)
                }.buttonStyle(HarborAccountButtonStyle())
                Button { pendingDelete = filter } label: {
                    Label(text("Delete"), systemImage: "trash").frame(minHeight: 44)
                }.buttonStyle(HarborAccountButtonStyle())
            }
        }.accessibilityIdentifier("stream-filter-row")
    }

    private var createRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowText(text("New filter"), filters.isEmpty
                ? text("Create your first filter with the stream quality you prefer.")
                : text("Choose a name, then select the resolutions, sources, codecs and audio you prefer."))
            Button { editing = CustomStreamFilter(name: "") } label: {
                Label(text("Create"), systemImage: "plus").frame(minHeight: 44)
            }.buttonStyle(HarborAccountButtonStyle(primary: true)).accessibilityIdentifier("stream-filter-create")
        }
    }

    private func summaryLine(_ filter: CustomStreamFilter) -> String {
        filter.hasPreferences
            ? streamFilterSummary(filter)
            : text("No preferences selected. Edit this filter to choose the streams you prefer.")
    }

    private func rowText(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(HarborTheme.font(14, weight: .semibold))
            Text(note).font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func activeButton(on: Bool, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(on ? text("Active") : text("Set active")).frame(minWidth: 140, minHeight: 44)
        }.buttonStyle(HarborAccountButtonStyle(primary: on)).disabled(disabled)
            .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// Desktop's builder (`play-picker/filter-builder.tsx`): name, categories, two toggles and two limits.
struct CustomStreamFilterEditor: View {
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    let onSave: (CustomStreamFilter) -> Void
    let onDelete: (String) -> Void
    @State private var draft: CustomStreamFilter
    @State private var seedersText: String
    @State private var sizeText: String
    @State private var confirmDelete = false
    private let chipColumns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    init(initial: CustomStreamFilter, isNew: Bool, onSave: @escaping (CustomStreamFilter) -> Void, onDelete: @escaping (String) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: initial)
        _seedersText = State(initialValue: initial.minSeeders.map { String($0) } ?? "")
        _sizeText = State(initialValue: initial.maxSizeGb.map { CustomStreamFilters.gigabyteText($0) } ?? "")
    }

    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    private var seeders: (valid: Bool, value: Int?) { CustomStreamFilters.parseMinSeeders(seedersText) }
    private var size: (valid: Bool, value: Double?) { CustomStreamFilters.parseMaxSizeGb(sizeText) }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && seeders.valid && size.valid }

    /// The filter as it would be saved: trimmed name, blank limits as nil.
    private var candidate: CustomStreamFilter {
        var filter = draft
        filter.name = trimmedName
        filter.minSeeders = seeders.value
        filter.maxSizeGb = size.value
        return filter
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    nameField
                    chipSection(text("Resolution"), options: CustomStreamFilters.resolutionOptions, selected: $draft.resolution)
                    chipSection(text("Source"), options: CustomStreamFilters.sourceOptions, selected: $draft.source)
                    chipSection(text("Codec"), options: CustomStreamFilters.codecOptions, selected: $draft.codec)
                    chipSection(text("Audio"), options: CustomStreamFilters.audioOptions, selected: $draft.audio)
                    HarborSettingsToggle(text("HDR only"), note: text("Match Dolby Vision, HDR10 and HLG streams."), isOn: $draft.requireHdr)
                    HarborSettingsToggle(text("Cached only"), note: text("Match streams marked as cached or already in your debrid library."), isOn: $draft.cachedOnly)
                    seedersField
                    sizeField
                    footer
                }.padding(20)
            }
            .background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(isNew ? text("New filter") : text("Edit filter")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(text("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? text("Create") : text("Save")) { saveDraft() }.disabled(!canSave)
                        .accessibilityIdentifier("stream-filter-save")
                }
            }
            .alert(text("Delete filter"), isPresented: $confirmDelete) {
                Button(text("Cancel"), role: .cancel) {}
                Button(text("Delete"), role: .destructive) {
                    onDelete(draft.id)
                    dismiss()
                }
            } message: {
                Text(DesktopInterfaceText.value("Delete {name}? Saved filters cannot be brought back.", variables: ["name": trimmedName.isEmpty ? text("Untitled filter") : trimmedName]))
            }
        }
    }

    private func saveDraft() {
        guard canSave else { return }
        onSave(candidate)
        dismiss()
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("Name")).font(HarborTheme.font(14, weight: .semibold))
            TextField(text("My filter"), text: $draft.name)
                .font(HarborTheme.font(15)).padding(12)
                .background(HarborTheme.surface, in: .rect(cornerRadius: 8))
                .accessibilityIdentifier("stream-filter-name")
        }
    }

    private func chipSection(_ title: String, options: [String], selected: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(HarborTheme.font(14, weight: .semibold))
            LazyVGrid(columns: chipColumns, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    chip(option, on: selected.wrappedValue.contains(option)) {
                        selected.wrappedValue = CustomStreamFilters.toggled(option, in: selected.wrappedValue)
                    }
                }
            }
        }
    }

    private func chip(_ option: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(DesktopInterfaceText.value(option))
                .font(HarborTheme.font(14, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(on ? HarborTheme.background : HarborTheme.ink)
                .background(on ? HarborTheme.ink : HarborTheme.surface, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private var seedersField: some View {
        numberField(title: text("Minimum seeders"),
                    note: text("Excludes streams with fewer seeders or no seeder count. Leave blank or enter 0 for any."),
                    placeholder: text("Any"), value: $seedersText, decimal: false,
                    error: seeders.valid ? nil : text("Enter a whole number of 0 or more."))
    }

    private var sizeField: some View {
        numberField(title: text("Maximum size (GB)"),
                    note: text("Unknown sizes still match. Leave blank or enter 0 for any."),
                    placeholder: text("Any"), value: $sizeText, decimal: true,
                    error: size.valid ? nil : text("Enter a size of 0 or more."))
    }

    private func numberField(title: String, note: String, placeholder: String, value: Binding<String>, decimal: Bool, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(HarborTheme.font(14, weight: .semibold))
            Text(note).font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField(placeholder, text: value)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .font(HarborTheme.font(15)).padding(12)
                .background(HarborTheme.surface, in: .rect(cornerRadius: 8))
            if let error = error {
                Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(footerNote).font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !isNew {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(text("Delete"), systemImage: "trash").frame(minHeight: 44)
                }.buttonStyle(HarborAccountButtonStyle())
            }
        }
    }

    /// Desktop's footer (filter-builder.tsx:222-223): the first problem, else the empty prompt, else the summary.
    private var footerNote: String {
        if !canSave { return text("Check the highlighted values before saving.") }
        if !candidate.hasPreferences { return text("Choose the streams you prefer.") }
        return streamFilterSummary(candidate)
    }
}

/// Desktop's `FilterSummary` (stream-filters-panel.tsx:26-45): categories, then HDR, cached, seeders and size.
private func streamFilterSummary(_ filter: CustomStreamFilter) -> String {
    var parts: [String] = []
    for values in [filter.resolution, filter.source, filter.codec, filter.audio] {
        if let joined = CustomStreamFilters.dimensionText(values) { parts.append(joined) }
    }
    if filter.requireHdr { parts.append(DesktopInterfaceText.value("HDR")) }
    if filter.cachedOnly { parts.append(DesktopInterfaceText.value("Cached")) }
    if let seeders = filter.minSeeders, seeders > 0 {
        parts.append(DesktopInterfaceText.value("{n}+ seeds", variables: ["n": String(seeders)]))
    }
    if let size = filter.maxSizeGb, size > 0 {
        parts.append(DesktopInterfaceText.value("Max {n} GB", variables: ["n": CustomStreamFilters.gigabyteText(size)]))
    }
    return parts.joined(separator: " · ")
}
