import SwiftUI

struct PageEditPill: View {
    let title: String
    let icon: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(icon).resizable().scaledToFit().frame(width: 12, height: 12)
                Text(title).font(HarborTheme.font(12, weight: .medium)).lineLimit(1)
            }.padding(.horizontal, 10).frame(height: 32)
                .foregroundStyle(selected ? HarborTheme.background : ThemePreferences.shared.color("ink-muted"))
                .background(selected ? HarborTheme.ink : HarborTheme.background.opacity(0.8), in: .rect(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(selected ? HarborTheme.ink : ThemePreferences.shared.color("edge-soft").opacity(0.4), lineWidth: 1) }
                .frame(minHeight: 44)
        }.buttonStyle(.plain)
    }
}

struct PageEditingFooter: View {
    let customization: PageCustomization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if customization.editing {
            HStack(spacing: 8) {
                PageEditPill(title: DesktopInterfaceText.value("Reset"), icon: "audio-reset-sync") { customization.reset() }
                    .accessibilityIdentifier("page-customize-reset")
                PageEditPill(title: DesktopInterfaceText.value("Done editing"), icon: "ui-pencil-outline", selected: true) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { customization.editing = false }
                }.accessibilityIdentifier("page-customize-done")
            }.padding(.horizontal, 12).padding(.vertical, 8)
                .background(HarborTheme.background.opacity(0.95), in: .rect(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
                .shadow(color: .black.opacity(0.5), radius: 16, y: 8).padding(.horizontal, 16).padding(.bottom, 8)
                .disabled(!customization.ready).transition(.opacity)
        }
    }
}

struct PageRowControls: View {
    let rail: PageRail
    let rails: [PageRail]
    let customization: PageCustomization
    @State private var renaming = false
    @State private var draft = ""
    @State private var notice: String?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var title: String { customization.title(rail, among: rails) }
    private var ordered: [PageRail] { customization.ordered(rails, includeHidden: true) }
    private var index: Int? { ordered.firstIndex { $0.id == rail.id } }
    private var hidden: Bool { customization.layout.hidden.contains(rail.id) }
    private var ranked: Bool { customization.ranked(rail) }
    private var hero: Bool { customization.layout.heroSource == rail.id }
    private var canHero: Bool { rail.metas.contains { $0.background != nil || $0.poster != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if renaming {
                    TextField(title, text: $draft).font(HarborTheme.font(13, weight: .medium))
                        .padding(.horizontal, 8).frame(minHeight: 44)
                        .background(ThemePreferences.shared.color("elevated"), in: .rect(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(ThemePreferences.shared.color("edge"), lineWidth: 1) }
                        .focused($focused).submitLabel(.done).onSubmit(commit)
                        .accessibilityIdentifier("page-row-name-\(rail.id)")
                    control("page-save", title: "Save", selected: true, action: commit)
                    control("episode-close", title: "Cancel") { focused = false; renaming = false }
                } else {
                    Text(title).font(HarborTheme.font(13, weight: .medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if customization.layout.renamed[rail.id] != nil {
                        Button {
                            customization.change { $0.renamed[rail.id] = nil }
                            notice = DesktopInterfaceText.value("Reset to original name")
                        } label: {
                            Text(DesktopInterfaceText.value("Renamed").uppercased()).font(HarborTheme.font(10.5, weight: .semibold))
                                .tracking(1.47).padding(.horizontal, 8).padding(.vertical, 3)
                                .foregroundStyle(HarborTheme.accent).background(HarborTheme.accent.opacity(0.15), in: .rect(cornerRadius: 6))
                                .frame(minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Reset to original name"))
                    }
                    control("theme-edit", title: "Rename row") { draft = title; renaming = true; focused = true }
                }
            }
            HStack(spacing: 6) {
                control("page-move-up", title: "Move up", enabled: index.map { $0 > 0 } ?? false) { move(-1) }
                control("page-move-down", title: "Move down", enabled: index.map { $0 < ordered.count - 1 } ?? false) { move(1) }
                control(hidden ? "page-row-hidden" : "page-row-eye", title: hidden ? "Show row" : "Hide row", selected: hidden, danger: hidden) {
                    customization.change { if hidden { $0.hidden.remove(rail.id) } else { $0.hidden.insert(rail.id) } }
                }
                control("page-row-numerals", title: ranked ? "Show as a normal row" : rail.metas.count >= 10 ? "Show as a Top 10 with big numerals" : "Needs at least 10 titles for the Top 10 look", selected: ranked, enabled: ranked || rail.metas.count >= 10) {
                    customization.change {
                        if ranked { $0.numerals.remove(rail.id); $0.plain.insert(rail.id) }
                        else { $0.numerals.insert(rail.id); $0.plain.remove(rail.id) }
                    }
                }
                control("page-row-hero", title: hero ? "Stop feeding the hero carousel (back to automatic)" : canHero ? "Feature this catalog in the hero carousel" : "Needs artwork-rich titles to feed the hero", selected: hero, enabled: hero || canHero) {
                    customization.change { $0.heroSource = hero ? nil : rail.id }
                }
                Spacer(minLength: 0)
            }
        }.padding(.horizontal, 8).padding(.vertical, 6)
            .background(HarborTheme.background.opacity(0.6), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
            .overlay(alignment: .top) {
                if let notice {
                    Text(notice).font(HarborTheme.font(12, weight: .medium)).multilineTextAlignment(.center)
                        .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: 260)
                        .background(ThemePreferences.shared.color("elevated"), in: .rect(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4).offset(y: -38)
                        .allowsHitTesting(false).transition(.opacity)
                }
            }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: notice)
            .disabled(!customization.ready).accessibilityIdentifier("page-row-controls-\(rail.id)")
            .task(id: notice) {
                guard notice != nil else { return }
                do { try await Task.sleep(for: .milliseconds(1700)); try Task.checkCancellation(); notice = nil } catch {}
            }
    }

    private func control(_ icon: String, title: String, selected: Bool = false, danger: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        let color = danger ? ThemePreferences.shared.color("danger") : selected ? HarborTheme.accent : ThemePreferences.shared.color("ink-muted")
        return Button {
            action()
            notice = DesktopInterfaceText.value(title)
        } label: {
            Image(icon).resizable().scaledToFit().frame(width: 14, height: 14)
                .frame(width: 36, height: 32).foregroundStyle(color)
                .background(selected ? color.opacity(0.15) : .clear, in: .rect(cornerRadius: 8))
                .frame(width: 44, height: 44).contentShape(Rectangle()).opacity(enabled ? 1 : 0.3)
        }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel(DesktopInterfaceText.value(title))
    }
    private func move(_ step: Int) {
        guard let index, ordered.indices.contains(index + step) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { customization.move(rail, toward: ordered[index + step]) }
    }
    private func commit() {
        let clean = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        if !clean.isEmpty {
            customization.change { $0.renamed[rail.id] = clean == rail.title ? nil : clean }
        }
        focused = false; renaming = false
    }
}
