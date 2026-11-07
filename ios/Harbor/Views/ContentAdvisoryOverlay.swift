import SwiftUI

/// Desktop's content advisory cards (`components/player/content-advisory-toast.tsx` and `content-advisory-prompt.tsx`), drawn
/// top-left over the picture. Only the cards take touches; the rest of the player stays live. The driver owns the state.
struct ContentAdvisoryOverlay: View {
    let toast: ContentAdvisoryToastState
    let guide: ContentAdvisoryGuide?
    let theme: ContentAdvisoryTheme
    let showsIgnore: Bool
    let prompt: ContentAdvisoryPromptState
    let onToastPointer: (Bool) -> Void
    let onDismiss: () -> Void
    let onIgnore: () -> Void
    let onPromptPointer: (Bool) -> Void
    let onTurnOn: () -> Void
    let onNotNow: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if toast.isVisible, let guide {
                ContentAdvisoryToastCard(
                    categories: ContentAdvisory.rated(guide.categories),
                    mpaRating: guide.mpaRating,
                    theme: theme,
                    showsIgnore: showsIgnore,
                    onPointer: onToastPointer,
                    onDismiss: onDismiss,
                    onIgnore: onIgnore)
                    .opacity(toast.phase == .collapsing ? 0 : 1)
                    .allowsHitTesting(toast.phase == .holding)
            }
            if prompt.isShown {
                ContentAdvisoryPromptCard(onPointer: onPromptPointer, onTurnOn: onTurnOn, onNotNow: onNotNow)
                    .opacity(prompt.phase == .exiting ? 0 : 1)
                    .allowsHitTesting(prompt.phase == .visible)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: ContentAdvisory.exitSeconds), value: toast.phase)
        .animation(reduceMotion ? nil : .easeOut(duration: ContentAdvisory.exitSeconds), value: prompt.phase)
        .frame(width: 280, alignment: .leading)
        .padding(.leading, 20)
        .padding(.top, 72)
    }
}

private struct ContentAdvisoryToastCard: View {
    let categories: [ContentAdvisoryCategory]
    let mpaRating: String?
    let theme: ContentAdvisoryTheme
    let showsIgnore: Bool
    let onPointer: (Bool) -> Void
    let onDismiss: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(DesktopInterfaceText.value("Content advisory"))
                    .font(HarborTheme.font(11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer(minLength: 8)
                if let mpaRating {
                    Text(mpaRating)
                        .font(HarborTheme.font(11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesktopInterfaceText.value("Dismiss"))
            }
            ForEach(Array(categories.enumerated()), id: \.offset) { _, category in
                categoryRow(category)
            }
            if showsIgnore {
                Button(action: onIgnore) {
                    Label(DesktopInterfaceText.value("Ignore this title"), systemImage: "eye.slash")
                        .font(HarborTheme.font(11))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(minHeight: 24, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint(DesktopInterfaceText.value("Never show the content advisory for this title again"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 280, alignment: .leading)
        .background(Color.black.opacity(0.7), in: .rect(cornerRadius: 4))
        .onHover(perform: onPointer)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DesktopInterfaceText.value("Content advisory"))
    }

    private func categoryRow(_ category: ContentAdvisoryCategory) -> some View {
        let presentation = ContentAdvisory.presentation(of: category.category)
        return HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: presentation.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 16)
                Text(DesktopInterfaceText.value(presentation.label))
                    .font(HarborTheme.font(12))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer(minLength: 8)
            Text(DesktopInterfaceText.value(category.severity))
                .font(HarborTheme.font(11))
                .foregroundStyle(color(ContentAdvisory.tone(severity: category.severity, theme: theme)))
                .multilineTextAlignment(.trailing)
        }
    }

    private func color(_ tone: ContentAdvisoryTone) -> Color {
        switch tone {
        case .danger: return ThemePreferences.shared.color("danger")
        case .accent: return HarborTheme.accent
        case .white(let opacity): return Color.white.opacity(opacity)
        }
    }
}

private struct ContentAdvisoryPromptCard: View {
    let onPointer: (Bool) -> Void
    let onTurnOn: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DesktopInterfaceText.value("Show content ratings?"))
                .font(HarborTheme.font(13, weight: .semibold))
            Text(DesktopInterfaceText.value("Age ratings and content notes when playback starts."))
                .font(HarborTheme.font(12))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: onTurnOn) {
                    Text(DesktopInterfaceText.value("Turn on"))
                        .font(HarborTheme.font(12, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Color.white.opacity(0.15), in: .rect(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                Button(action: onNotNow) {
                    Text(DesktopInterfaceText.value("Not now"))
                        .font(HarborTheme.font(12))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .padding(.horizontal, 8)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background(Color.black.opacity(0.8), in: .rect(cornerRadius: 4))
        .onHover(perform: onPointer)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DesktopInterfaceText.value("Show content ratings?"))
    }
}
